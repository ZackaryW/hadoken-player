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
final class SkillPolicy implements OrderedPlayerAbilityPolicy {
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

  SkillContext _context(ProfileId owner, ProfileId actor, Duration now) =>
      SkillContext(
        sessionId: _session,
        owner: owner.name,
        actor: actor.name,
        elapsed: now,
        players: ProfileId.values
            .where(assignments.profileExists)
            .map((p) => p.name),
        support: coordinator.adapters.keys,
      );

  Stream<void> get changes => _changes.stream;

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
    final event = _event(request, now);
    for (final definition in _assigned(request.profile)) {
      final runtime = _runtimes[definition.id]!;
      final denial = runtime.decide(
        PlaybackSkillTarget(event.action),
        _context(request.profile, request.profile, now),
        request.requestId,
      );
      if (denial != null) return denial;
    }
    return null;
  }

  @override
  Future<void> recordSuccess(
    PlayerActionRequest request,
    CommandResult result,
  ) async {
    if (!result.succeeded) return;
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
        context: _context(request.profile, request.profile, event.elapsed),
      );
      if (outcome.stateChanged) changed = true;
      if (outcome.error != null) throw StateError(outcome.error!);
    }
    if (changed) _changes.add(null);
  }

  Future<void> dispose() async {
    await _sessionChanges?.cancel();
    await effects.dispose();
    await _effectChanges?.cancel();
    await _changes.close();
  }
}
