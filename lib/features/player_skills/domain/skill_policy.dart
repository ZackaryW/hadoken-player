import 'dart:async';
import 'package:troona/skills/registry.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../../player_actions/domain/action_dispatcher.dart';
import 'skill_assignments.dart';
import 'effect_ledger.dart';
import 'skill_coordinator.dart';
import 'gameplay_effects.dart';
import 'skill_playback.dart';
import 'combo_overrides.dart';
import '../../profiles/domain/effective_bindings.dart';
import '../../player/domain/ports/loop_queue_port.dart';
import 'loop_queue_effects.dart';
import '../../player/domain/ports/skill_audio_effects_port.dart';
import 'skill_audio_effects.dart';
import '../../input_bindings/domain/combo_input.dart';

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
  late final GameplayEffects gameplay;
  ProfileCatalog Function()? _catalog;
  PlaybackCommands? _playback;
  LoopQueuePort? _queue;
  final _budgets = <String, SkillExecutionBudget>{};
  SkillOrder? _order;
  Future<void> _localTail = Future.value();
  StreamSubscription<void>? _effectChanges;
  StreamSubscription<int>? _sessionChanges;
  String _session = 'playback-0';
  final _requestSessions = <String, String>{};
  bool _lifecycleFailed = false;
  final _runtimeOwners = <SkillId, ProfileId>{};
  int _lifecycleSequence = 0;
  Future<SkillPlaybackSnapshot> Function()? playbackSnapshot;

  Future<void> synchronize() async {
    final now = await clock.now();
    for (final definition in definitions) {
      final owner = assignments.catalog.ownerOf(definition.id);
      final previous = _runtimeOwners[definition.id];
      if (owner == previous) continue;
      var runtime = _runtimes[definition.id]!;
      if (previous != null) {
        await _lifecycleEvent(
          definition,
          runtime,
          previous,
          SkillUnequipped('unequip:${_lifecycleSequence++}'),
          now,
        );
        runtime.resetSessionState();
        runtime = definition.createRuntime();
        runtime.resetSessionState();
        _runtimes[definition.id] = runtime;
      }
      _runtimeOwners.remove(definition.id);
      if (owner != null) {
        _runtimeOwners[definition.id] = owner;
        runtime.configureListeners(definition);
        await _lifecycleEvent(
          definition,
          runtime,
          owner,
          SkillEquipped('equip:${_lifecycleSequence++}'),
          now,
        );
      }
    }
    final snapshot = await playbackSnapshot?.call();
    if (snapshot != null) {
      for (final definition in definitions) {
        final owner = _runtimeOwners[definition.id];
        if (owner == null) continue;
        await _lifecycleEvent(
          definition,
          _runtimes[definition.id]!,
          owner,
          SkillPlaybackObserved('playback:${_lifecycleSequence++}', snapshot),
          now,
        );
      }
    }
  }

  Future<void> _lifecycleEvent(
    SkillDefinition definition,
    SkillRuntime runtime,
    ProfileId owner,
    SkillRuntimeEvent event,
    Duration now,
  ) async {
    if (!definition.listeners.any((l) => l.trigger == event.trigger)) return;
    final outcome = await coordinator.invokeWithinOrder(
      definition: definition,
      runtime: runtime,
      event: event,
      origin: SkillOrigin(
        owner: owner.name,
        skillKey: definition.id.key,
        invocationId: event.id,
        sessionId: _session,
      ),
      context: _context(owner, null, now),
      allowPlayback: false,
      transient: true,
    );
    if (outcome.error != null) throw StateError(outcome.error!);
    if (outcome.stateChanged) _changes.add(null);
  }

  Future<Map<SkillId, String?>> statuses(ProfileId profile) =>
      _runOrdered(() async {
        await synchronize();
        final now = await clock.now();
        return {
          for (final definition in _assigned(profile))
            definition.id: _runtimes[definition.id]!.status(
              _context(profile, profile, now),
            ),
        };
      });

  Future<String?> assignmentDenial(ProfileId profile) async {
    await synchronize();
    final now = await clock.now();
    for (final definition in _assigned(profile)) {
      final reason = _runtimes[definition.id]!.assignmentLock(
        _context(profile, profile, now),
      );
      if (reason != null) return reason;
    }
    return null;
  }

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
      originIsActive: (origin) {
        final definition = definitionFor(origin.skillKey);
        final owners = ProfileId.values.where((p) => p.name == origin.owner);
        return !_lifecycleFailed &&
            origin.sessionId == _session &&
            definition != null &&
            owners.isNotEmpty &&
            assignments.catalog.has(owners.first, definition.id);
      },
    );
    _effectChanges = effects.changes.listen((_) => _changes.add(null));
    gameplay = GameplayEffects(ledger: effects, definitionFor: definitionFor);
    coordinator.adapters.putIfAbsent(SkillCapability.listener, () => gameplay);
    coordinator.adapters.putIfAbsent(
      SkillCapability.restriction,
      () => gameplay,
    );
    effects.onExpired = (handles, now) async {
      for (final handle in handles) {
        if (handle.origin.sessionId != _session) continue;
        for (final definition in definitions) {
          if (definition.id.key != handle.origin.skillKey ||
              !definition.supports(SkillTrigger.effectExpired)) {
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

  void bindEffectiveBindings(EffectiveBindings bindings) {
    bindings.elapsedNow = clock.now;
    coordinator.adapters[SkillCapability.comboOverride] = ComboOverrides(
      bindings,
      (key) => definitionFor(key)?.label ?? key,
    );
  }

  void bindQueue(LoopQueuePort queue) {
    _queue = queue;
    coordinator.adapters[SkillCapability.queueEdit] = LoopQueueEffects(
      queue,
      clock.now,
    );
  }

  void bindAudio(SkillAudioEffectsPort audio) {
    if (audio.supportsAudioMix) {
      coordinator.adapters[SkillCapability.audioMix] = SkillAudioEffects(audio);
    }
  }

  @override
  void bindExecution(
    PlaybackCommands playback,
    ProfileCatalog Function() catalog,
  ) {
    _catalog = catalog;
    _playback = playback;
    coordinator.adapters.putIfAbsent(
      SkillCapability.playbackAction,
      () => SkillPlayback(_executeGenerated),
    );
  }

  List<SkillStrokeObservation> _observations(
    Iterable<StrokeObservation> observations,
  ) => observations
      .map(
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
      )
      .toList();

  @override
  Future<List<CapabilityResult>> observeInput(
    PlayerActionRequest request,
  ) async {
    await synchronize();
    final now = await clock.now();
    await effects.retireDue(now);
    final catalog = _catalog?.call();
    if (request.observations.isEmpty ||
        catalog == null ||
        (request.catalogRevision != null &&
            request.catalogRevision != catalog.revision) ||
        catalog.executableById(request.bindingId)?.comboKey !=
            request.binding.comboKey) {
      return const [];
    }
    final observations = _observations(request.observations);
    final combo = SkillCombo(observations.map((o) => o.stroke));
    final snapshot = gameplay.matching(request.profile.name, combo, now);
    final results = <CapabilityResult>[];
    final budget = _budgets.putIfAbsent(
      request.requestId,
      SkillExecutionBudget.new,
    );
    for (final definition in definitions) {
      final owner = assignments.catalog.ownerOf(definition.id);
      if (owner == null || !definition.listeners.any((l) => l.combo == combo)) {
        continue;
      }
      final outcome = await coordinator.invokeWithinOrder(
        definition: definition,
        runtime: _runtimes[definition.id]!,
        event: SkillComboObserved(
          request.requestId,
          listenerKey: 'declared',
          target: _target(request),
          observations: observations,
        ),
        origin: SkillOrigin(
          owner: owner.name,
          skillKey: definition.id.key,
          invocationId: 'declared:${request.requestId}',
          sessionId: _session,
        ),
        context: _context(owner, request.profile, now, effort: request.effort),
        budget: budget,
      );
      results.addAll(outcome.results);
      if (outcome.stateChanged) _changes.add(null);
    }
    for (final listener in snapshot) {
      final current = await clock.now();
      if (!effects.isEffective(listener.handle.id, current)) continue;
      final definition = definitionFor(listener.handle.origin.skillKey);
      final owner = ProfileId.values.byName(listener.handle.origin.owner);
      if (definition == null ||
          !assignments.catalog.has(owner, definition.id)) {
        continue;
      }
      if (listener.declaration.once) await effects.revoke(listener.handle.id);
      final outcome = await coordinator.invokeWithinOrder(
        definition: definition,
        runtime: _runtimes[definition.id]!,
        event: SkillComboObserved(
          request.requestId,
          listenerKey: listener.declaration.listenerKey,
          target: _target(request),
          observations: observations,
        ),
        origin: SkillOrigin(
          owner: owner.name,
          skillKey: definition.id.key,
          invocationId: 'listen:${listener.handle.id}:${request.requestId}',
          sessionId: _session,
        ),
        context: _context(
          owner,
          request.profile,
          current,
          effort: request.effort,
        ),
        budget: budget,
      );
      results.addAll(outcome.results);
      if (outcome.error != null) {
        results.add(
          CapabilityResult(
            effectId: 'listener:${listener.handle.id}:${request.requestId}',
            status: CapabilityStatus.failed,
            reason: outcome.error!,
          ),
        );
      }
      if (outcome.stateChanged) _changes.add(null);
    }
    return List.unmodifiable(results);
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
          if (!await effects.endSession(previous)) {
            _lifecycleFailed = true;
          }
          for (final definition in definitions) {
            _runtimes[definition.id]!.resetSessionState();
            _runtimes[definition.id] = definition.createRuntime();
          }
          _runtimeOwners.clear();
          _changes.add(null);
        }).catchError((Object _) {
          _lifecycleFailed = true;
        }),
      );
    });
  }

  SkillContext _context(
    ProfileId owner,
    ProfileId? actor,
    Duration now, {
    Effort effort = Effort.normal,
  }) => SkillContext(
    sessionId: _session,
    owner: owner.name,
    actor: actor?.name,
    elapsed: now,
    effort: effort,
    players: ProfileId.values
        .where(assignments.profileExists)
        .map((p) => p.name),
    support: coordinator.adapters.keys,
    loop: _queue?.currentLoop?.ordinal ?? 0,
    queueRevision: _queue?.currentLoop?.revision ?? 0,
    queue: [
      for (final item in _queue?.currentLoop?.occurrences ?? [])
        SkillQueueOccurrence(item.id, item.song),
    ],
    songs: _queue?.currentLoop?.occurrences.map((o) => o.song).toSet() ?? {},
    bindingRevision: _catalog?.call().revision ?? 0,
    bindings: [
      for (final binding
          in _catalog?.call().executableBindings ?? <ExecutableBinding>[])
        SkillBindingView(binding.profile.name, switch (binding) {
          ActionBinding(:final action) => PlaybackSkillTarget(
            SkillAction.values.byName(action.name),
          ),
          SkillMacroBinding(:final skillKey) => ActivationSkillTarget(skillKey),
        }, SkillCombo(binding.strokes.map(skillStroke))),
    ],
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
        definition.supports(SkillTrigger.manualActivation) &&
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
    await synchronize();
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
    final observations = _observations(request.observations);
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
      budget: _budgets.putIfAbsent(request.requestId, SkillExecutionBudget.new),
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
    await synchronize();
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
    return _blockFor(
      request.profile,
      _target(request),
      effort,
      now,
      request.requestId,
    )?.reason;
  }

  SkillActionBlock? _blockFor(
    ProfileId actor,
    SkillTarget target,
    Effort effort,
    Duration now,
    String requestId,
  ) {
    SkillActionBlock? blocking = gameplay.restrictionFor(
      actor.name,
      target,
      effort,
      now,
    );
    for (final definition in definitions) {
      final owner = assignments.catalog.ownerOf(definition.id);
      if (owner == null ||
          !PlayerSelector(definition.decisionScope)
              .resolve(
                owner.name,
                ProfileId.values
                    .where(assignments.profileExists)
                    .map((p) => p.name),
              )
              .contains(actor.name)) {
        continue;
      }
      final runtime = _runtimes[definition.id]!;
      final denial = runtime.decide(
        target,
        _context(owner, actor, now, effort: effort),
        requestId,
      );
      if (denial != null &&
          !effort.overcomes(denial.effort) &&
          (blocking == null || denial.effort.compareTo(blocking.effort) > 0)) {
        blocking = denial;
      }
    }
    return blocking;
  }

  Future<CapabilityResult> _executeGenerated(
    ExecutePlayerAction request,
    SkillOrigin origin,
    SkillExecutionBudget budget,
  ) async {
    CapabilityResult result(CapabilityStatus status, String reason) =>
        CapabilityResult(
          effectId: request.effectId,
          status: status,
          reason: reason,
        );
    await synchronize();
    final now = await clock.now();
    await effects.retireDue(now);
    final definition = definitionFor(origin.skillKey);
    final owners = ProfileId.values.where((p) => p.name == origin.owner);
    final actors = ProfileId.values.where((p) => p.name == request.player);
    if (_lifecycleFailed ||
        origin.sessionId != _session ||
        definition == null ||
        owners.isEmpty ||
        actors.isEmpty ||
        !assignments.catalog.has(owners.first, definition.id) ||
        !assignments.profileExists(actors.first)) {
      return result(
        CapabilityStatus.denied,
        'The skill source or player is no longer available.',
      );
    }
    final actor = actors.first;
    final id =
        'generated:${origin.sessionId}:${origin.owner}:${origin.skillKey}:${request.effectId}';
    final block = _blockFor(
      actor,
      PlaybackSkillTarget(request.action),
      request.effort,
      now,
      id,
    );
    if (block != null) return result(CapabilityStatus.denied, block.reason);
    final playback = _playback;
    if (playback == null) {
      return result(CapabilityStatus.unsupported, 'Playback is unavailable.');
    }
    final action = PlayerAction.values.byName(request.action.name);
    final outcome = await playback.execute(action);
    if (!outcome.succeeded) {
      return result(switch (outcome.status) {
        ActionStatus.denied => CapabilityStatus.denied,
        ActionStatus.noOp => CapabilityStatus.noOp,
        _ => CapabilityStatus.failed,
      }, outcome.message);
    }
    var message = outcome.message;
    if (origin.sessionId == _session) {
      try {
        await _recordAttributedSuccess(
          actor,
          request.action,
          id,
          request.effort,
          budget,
          allowPlayback: false,
        );
      } catch (_) {
        // The native effect happened. Preserve that fact and fail closed next time.
        _lifecycleFailed = true;
        message =
            '$message Skill update failed; restart before more combo actions.';
      }
    }
    return result(CapabilityStatus.applied, message);
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
    await _recordAttributedSuccess(
      request.profile,
      _event(request, Duration.zero).action,
      request.requestId,
      request.effort,
      _budgets.putIfAbsent(request.requestId, SkillExecutionBudget.new),
      allowPlayback: true,
    );
  }

  Future<void> _recordAttributedSuccess(
    ProfileId actor,
    SkillAction action,
    String requestId,
    Effort effort,
    SkillExecutionBudget budget, {
    required bool allowPlayback,
  }) async {
    final now = await clock.now();
    var changed = false;
    for (final definition in definitions) {
      final owner = assignments.catalog.ownerOf(definition.id);
      if (owner == null ||
          !definition.listeners.any(
            (l) => l.trigger == SkillTrigger.actionSucceeded,
          )) {
        continue;
      }
      final outcome = await coordinator.invokeWithinOrder(
        definition: definition,
        runtime: _runtimes[definition.id]!,
        event: SkillActionSucceeded(requestId, PlaybackSkillTarget(action)),
        origin: SkillOrigin(
          owner: owner.name,
          skillKey: definition.id.key,
          invocationId: 'success:$requestId',
          sessionId: _session,
        ),
        context: _context(owner, actor, now, effort: effort),
        budget: budget,
        allowPlayback: allowPlayback,
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
