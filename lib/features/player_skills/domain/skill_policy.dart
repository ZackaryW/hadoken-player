import 'dart:async';
import 'package:troona/skills/registry.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../../player_actions/domain/action_dispatcher.dart';
import 'skill_assignments.dart';
import 'effect_ledger.dart';
import 'skill_coordinator.dart';

abstract interface class SkillClock {
  Future<Duration> now();
}

final class SkillCooldown implements Exception {
  final ProfileId profile;
  final Duration remaining;
  final SkillDefinition skill;
  const SkillCooldown(this.profile, this.remaining, {required this.skill});
  @override
  String toString() =>
      '${profile.label} · ${skill.label} · ${remainingSeconds(remaining)}s remaining';
}

final class SkillRecovery {
  final SkillDefinition definition;
  final Duration remaining;
  const SkillRecovery(this.definition, this.remaining);
}

/// Adapts app assignments/actions to independent skill runtimes.
final class SkillPolicy implements ExecutablePlayerAbilityPolicy {
  final SkillAssignmentRepository assignments;
  final SkillClock clock;
  final List<SkillDefinition> definitions;
  final Map<SkillId, SkillRuntime> _runtimes = {};
  final _changes = StreamController<void>.broadcast(sync: true);
  late final EffectLedger effects;
  late final SkillCoordinator coordinator;
  SkillOrder? _order;
  Future<void> _localTail = Future.value();
  StreamSubscription<void>? _effectChanges;
  StreamSubscription<int>? _sessionChanges;
  String _session = 'playback-0';
  final _requestSessions = <String, String>{};
  bool _lifecycleFailed = false;

  SkillPolicy({
    required this.assignments,
    required this.clock,
    Iterable<SkillDefinition> definitions = skillDefinitions,
    Map<SkillCapability, SkillCapabilityAdapter> adapters = const {},
    bool scheduleTimers = true,
  }) : definitions = List.unmodifiable(definitions) {
    for (final definition in this.definitions) {
      if (_runtimes.containsKey(definition.id)) {
        throw ArgumentError('Duplicate skill: ${definition.id.key}');
      }
      _runtimes[definition.id] = definition.createRuntime();
    }
    effects = EffectLedger(
      now: clock.now,
      runOrdered: _runOrdered,
      scheduleTimers: scheduleTimers,
    );
    coordinator = SkillCoordinator(
      runOrdered: _runOrdered,
      effects: effects,
      adapters: adapters,
    );
    _effectChanges = effects.changes.listen((_) => _changes.add(null));
    effects.onExpired = (handles, now) async {
      for (final handle in handles) {
        if (handle.origin.sessionId != _session) continue;
        for (final definition in definitions) {
          if (definition.id.key != handle.origin.skillKey ||
              !definition.triggers.contains(SkillTrigger.effectExpired)) {
            continue;
          }
          final owner = ProfileId.values.byName(handle.origin.owner);
          if (!assignments.catalog.has(owner, definition.id)) continue;
          final outcome = await coordinator.invokeWithinOrder(
            definition: definition,
            runtime: _runtimes[definition.id]!,
            event: SkillEffectExpired('expired:${handle.id}', handle),
            origin: SkillOrigin(
              owner: owner.name,
              skillKey: definition.id.key,
              invocationId: 'expired:${handle.id}',
              sessionId: _session,
            ),
            context: _context(owner, owner, now),
          );
          if (outcome.stateChanged) _changes.add(null);
        }
      }
    };
  }

  @override
  void bindOrder(SkillOrder runOrdered) {
    _order = runOrdered;
  }

  Future<T> _runOrdered<T>(Future<T> Function() operation) {
    final order = _order;
    if (order != null) return order(operation);
    final result = _localTail.then((_) => operation());
    _localTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void observeSessions(Stream<int> generations, int initial) {
    if (_sessionChanges != null) {
      throw StateError('Playback sessions already connected.');
    }
    _session = 'playback-$initial';
    _sessionChanges = generations.listen((generation) {
      final next = 'playback-$generation';
      if (next == _session) return;
      final previous = _session;
      _session = next;
      unawaited(
        _runOrdered(() async {
          await effects.endSession(previous);
          for (final definition in definitions) {
            _runtimes[definition.id] = definition.createRuntime();
          }
          _changes.add(null);
        }).catchError((Object _) {
          _lifecycleFailed = true;
        }),
      );
    });
  }

  SkillContext _context(
    ProfileId owner,
    ProfileId actor,
    Duration now, {
    Effort effort = Effort.normal,
  }) => SkillContext(
    sessionId: _session,
    owner: owner.name,
    actor: actor.name,
    elapsed: now,
    effort: effort,
    players: ProfileId.values
        .where(assignments.profileExists)
        .map((p) => p.name),
    support: coordinator.adapters.keys,
  );

  Stream<void> get changes => _changes.stream;

  SkillDefinition? definitionFor(String key) {
    for (final definition in definitions) {
      if (definition.id.key == key) return definition;
    }
    return null;
  }

  bool macroEnabled(SkillMacroBinding macro) {
    final definition = definitionFor(macro.skillKey);
    return definition != null &&
        definition.triggers.contains(SkillTrigger.manualActivation) &&
        assignments.catalog.has(macro.profile, definition.id);
  }

  @override
  Effort effortFor(ExecutableBinding binding) => binding is SkillMacroBinding
      ? definitionFor(binding.skillKey)?.activationEffort ?? Effort.normal
      : Effort.normal;

  SkillTarget _target(PlayerActionRequest request) =>
      request.binding is SkillMacroBinding
      ? ActivationSkillTarget((request.binding as SkillMacroBinding).skillKey)
      : PlaybackSkillTarget(_event(request, Duration.zero).action);

  @override
  Future<CommandResult> activate(PlayerActionRequest request) async {
    final binding = request.binding;
    if (binding is! SkillMacroBinding || !macroEnabled(binding)) {
      return const CommandResult(
        ActionStatus.denied,
        'This skill is not equipped for this player.',
      );
    }
    final definition = definitionFor(binding.skillKey)!;
    final now = await clock.now();
    final context = _context(
      request.profile,
      request.profile,
      now,
      effort: definition.activationEffort,
    );
    if (!context.support.containsAll(definition.requiredCapabilities)) {
      return const CommandResult(
        ActionStatus.denied,
        'Required skill capabilities are unavailable.',
      );
    }
    if (request.observations.isEmpty) {
      return const CommandResult(
        ActionStatus.denied,
        'A recorded runtime combo is required.',
      );
    }
    final observations = request.observations.map(
      (o) => SkillStrokeObservation(
        stroke: switch ((o.stroke.button, o.stroke.kind)) {
          (InputButton.forward, StrokeKind.tap) => SkillStroke.forwardTap,
          (InputButton.forward, StrokeKind.hold) => SkillStroke.forwardHold,
          (InputButton.pause, StrokeKind.tap) => SkillStroke.pauseTap,
          (InputButton.pause, StrokeKind.hold) => SkillStroke.pauseHold,
          (InputButton.backward, StrokeKind.tap) => SkillStroke.backwardTap,
          (InputButton.backward, StrokeKind.hold) => SkillStroke.backwardHold,
        },
        downAt: o.downAt,
        upAt: o.upAt,
        gapBefore: o.gapBefore ?? Duration.zero,
      ),
    );
    final outcome = await coordinator.invokeWithinOrder(
      definition: definition,
      runtime: _runtimes[definition.id]!,
      event: SkillManualActivation(request.requestId, observations),
      origin: SkillOrigin(
        owner: request.profile.name,
        skillKey: definition.id.key,
        invocationId: 'manual:${request.requestId}',
        sessionId: _session,
      ),
      context: context,
    );
    if (outcome.stateChanged) _changes.add(null);
    if (outcome.error != null) {
      return CommandResult(
        ActionStatus.failure,
        outcome.error!,
        effects: outcome.results,
      );
    }
    final failed = outcome.results.where(
      (r) =>
          r.status == CapabilityStatus.failed ||
          r.status == CapabilityStatus.denied ||
          r.status == CapabilityStatus.unsupported,
    );
    if (failed.isNotEmpty) {
      final result = failed.first;
      return CommandResult(
        result.status == CapabilityStatus.denied
            ? ActionStatus.denied
            : ActionStatus.failure,
        result.reason,
        effects: outcome.results,
      );
    }
    return CommandResult(
      ActionStatus.success,
      '${definition.label} activated.',
      effects: outcome.results,
    );
  }

  Future<Map<SkillId, Duration>> remainingBySkill(ProfileId profile) async {
    final now = await clock.now();
    return {
      for (final definition in definitions)
        definition.id: _remaining(definition, profile, now),
    };
  }

  Duration _remaining(
    SkillDefinition definition,
    ProfileId profile,
    Duration now,
  ) {
    final recovery = assignments.catalog.has(profile, definition.id)
        ? _runtimes[definition.id]!.remaining(profile.name, now)
        : Duration.zero;
    final effect = effects.remaining(profile.name, definition.id.key, now);
    return effect > recovery ? effect : recovery;
  }

  Future<SkillRecovery?> recoveryFor(ProfileId profile) async {
    final remaining = await remainingBySkill(profile);
    SkillRecovery? recovery;
    for (final definition in definitions) {
      final left = remaining[definition.id]!;
      if (left > (recovery?.remaining ?? Duration.zero)) {
        recovery = SkillRecovery(definition, left);
      }
    }
    return recovery;
  }

  Future<Duration> remaining(ProfileId profile) async =>
      (await recoveryFor(profile))?.remaining ?? Duration.zero;

  Iterable<SkillDefinition> _assigned(ProfileId profile) sync* {
    for (final definition in definitions) {
      if (assignments.catalog.has(profile, definition.id)) {
        yield definition;
      }
    }
  }

  SkillEvent _event(PlayerActionRequest request, Duration now) => SkillEvent(
    requestId: request.requestId,
    playerId: request.profile.name,
    action: switch (request.action) {
      PlayerAction.togglePlayback => SkillAction.togglePlayback,
      PlayerAction.nextTrack => SkillAction.nextTrack,
      PlayerAction.previousTrack => SkillAction.previousTrack,
      PlayerAction.seekForward => SkillAction.seekForward,
      PlayerAction.seekBackward => SkillAction.seekBackward,
      PlayerAction.stop => SkillAction.stop,
      null => throw StateError('Skill activation is not a playback action.'),
    },
    elapsed: now,
  );

  @override
  Future<String?> denialFor(PlayerActionRequest request) async {
    if (_lifecycleFailed) {
      return 'Skill session cleanup failed. Restart the player.';
    }
    final now = await clock.now();
    await effects.retireDue(now);
    _requestSessions[request.requestId] = _session;
    final binding = request.binding;
    if (binding is SkillMacroBinding && !macroEnabled(binding)) {
      return 'This skill is not equipped for this player.';
    }
    final effort = binding is SkillMacroBinding
        ? effortFor(binding)
        : request.effort;
    SkillActionBlock? blocking;
    for (final definition in _assigned(request.profile)) {
      final runtime = _runtimes[definition.id]!;
      final denial = runtime.decide(
        _target(request),
        _context(request.profile, request.profile, now, effort: effort),
        request.requestId,
      );
      if (denial != null &&
          !effort.overcomes(denial.effort) &&
          (blocking == null || denial.effort.compareTo(blocking.effort) > 0)) {
        blocking = denial;
      }
    }
    return blocking?.reason;
  }

  @override
  Future<void> recordSuccess(
    PlayerActionRequest request,
    CommandResult result,
  ) async {
    if (!result.succeeded || request.binding is! ActionBinding) return;
    if (_requestSessions[request.requestId] case final session?
        when session != _session) {
      return;
    }
    final event = _event(request, await clock.now());
    var changed = false;
    for (final definition in _assigned(request.profile)) {
      if (!definition.triggers.contains(SkillTrigger.actionSucceeded)) continue;
      final outcome = await coordinator.invokeWithinOrder(
        definition: definition,
        runtime: _runtimes[definition.id]!,
        event: SkillActionSucceeded(
          request.requestId,
          PlaybackSkillTarget(event.action),
        ),
        origin: SkillOrigin(
          owner: request.profile.name,
          skillKey: definition.id.key,
          invocationId: 'success:${request.requestId}',
          sessionId: _session,
        ),
        context: _context(
          request.profile,
          request.profile,
          event.elapsed,
          effort: request.effort,
        ),
      );
      if (outcome.stateChanged) changed = true;
      if (outcome.error != null) throw StateError(outcome.error!);
    }
    if (changed) _changes.add(null);
  }

  Future<void> dispose() async {
    await _sessionChanges?.cancel();
    await _effectChanges?.cancel();
    await effects.dispose();
    await _changes.close();
  }
}
