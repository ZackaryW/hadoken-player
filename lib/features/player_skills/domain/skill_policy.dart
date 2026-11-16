import 'dart:async';
import 'package:troona/skills/registry.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../../player_actions/domain/action_dispatcher.dart';
import 'skill_assignments.dart';

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
final class SkillPolicy implements PlayerAbilityPolicy {
  final SkillAssignmentRepository assignments;
  final SkillClock clock;
  final List<SkillDefinition> definitions;
  final Map<SkillId, SkillRuntime> _runtimes = {};
  final _changes = StreamController<void>.broadcast(sync: true);

  SkillPolicy({
    required this.assignments,
    required this.clock,
    Iterable<SkillDefinition> definitions = skillDefinitions,
  }) : definitions = List.unmodifiable(definitions) {
    for (final definition in this.definitions) {
      if (_runtimes.containsKey(definition.id)) {
        throw ArgumentError('Duplicate skill: ${definition.id.key}');
      }
      _runtimes[definition.id] = definition.createRuntime();
    }
  }

  Stream<void> get changes => _changes.stream;

  Future<Map<SkillId, Duration>> remainingBySkill(ProfileId profile) async {
    final now = await clock.now();
    return {
      for (final definition in definitions)
        definition.id: assignments.catalog.has(profile, definition.id)
            ? _runtimes[definition.id]!.remaining(profile.name, now)
            : Duration.zero,
    };
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

  Iterable<SkillRuntime> _assigned(ProfileId profile) sync* {
    for (final definition in definitions) {
      if (assignments.catalog.has(profile, definition.id)) {
        yield _runtimes[definition.id]!;
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
    final runtimes = _assigned(request.profile).toList();
    if (runtimes.isEmpty) return null;
    final event = _event(request, await clock.now());
    for (final runtime in runtimes) {
      final denial = runtime.denialFor(event);
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
    final runtimes = _assigned(request.profile).toList();
    if (runtimes.isEmpty) return;
    final event = _event(request, await clock.now());
    var changed = false;
    for (final runtime in runtimes) {
      if (runtime.recordSuccess(event)) changed = true;
    }
    if (changed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
