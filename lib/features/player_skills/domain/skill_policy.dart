import 'dart:async';
import '../../profiles/domain/profile_catalog.dart';
import '../../player_actions/domain/action_dispatcher.dart';
import 'skill_assignments.dart';
import 'skill_catalog.dart';

abstract interface class SkillClock {
  Future<Duration> now();
}

final class SkillCooldown implements Exception {
  final ProfileId profile;
  final Duration remaining;
  const SkillCooldown(this.profile, this.remaining);
  @override
  String toString() =>
      '${profile.label} · Skip Recovery · ${remainingSeconds(remaining)}s remaining';
}

int remainingSeconds(Duration value) =>
    (value.inMicroseconds / Duration.microsecondsPerSecond).ceil();

final class SkillPolicy implements PlayerAbilityPolicy {
  final SkillAssignmentRepository assignments;
  final SkillClock clock;
  final _deadlines = <ProfileId, Duration>{};
  final _recorded = <String>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  SkillPolicy({required this.assignments, required this.clock});
  Stream<void> get changes => _changes.stream;
  Future<Duration> remaining(ProfileId profile) async {
    final now = await clock.now();
    final left = (_deadlines[profile] ?? Duration.zero) - now;
    return left > Duration.zero ? left : Duration.zero;
  }

  @override
  Future<String?> denialFor(PlayerActionRequest request) async {
    if (request.action != PlayerAction.nextTrack ||
        !assignments.catalog.has(request.profile, SkillId.skipRecovery)) {
      return null;
    }
    final left = await remaining(request.profile);
    return left > Duration.zero
        ? SkillCooldown(request.profile, left).toString()
        : null;
  }

  @override
  Future<void> recordSuccess(
    PlayerActionRequest request,
    CommandResult result,
  ) async {
    if (!result.succeeded ||
        request.action != PlayerAction.nextTrack ||
        !assignments.catalog.has(request.profile, SkillId.skipRecovery) ||
        _recorded.contains(request.requestId)) {
      return;
    }
    final completed = await clock.now();
    if (!_recorded.add(request.requestId)) return;
    _deadlines[request.profile] = completed + skipRecoveryDuration;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
