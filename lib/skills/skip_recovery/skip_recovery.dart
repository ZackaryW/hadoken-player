import '../skill.dart';

const skipRecoveryDuration = Duration(seconds: 10);

final class SkipRecovery extends SkillDefinition {
  const SkipRecovery();
  @override
  SkillId get id => SkillId.skipRecovery;
  @override
  String get label => 'Skip Recovery';
  @override
  String get summary => 'Next track · 10s recovery';
  @override
  String get description =>
      'After your skip (${Effort.normal}): block your skip (${Effort.normal}) for 10s.\n'
      'Other players: skip (${Effort.normal}).';
  @override
  SkillRuntime createRuntime() => _SkipRecoveryRuntime(this);
}

final class _SkipRecoveryRuntime extends SkillRuntime {
  final SkipRecovery definition;
  final _deadlines = <String, Duration>{};
  final _recorded = <String>{};
  _SkipRecoveryRuntime(this.definition);

  @override
  Duration remaining(String playerId, Duration elapsed) {
    final left = (_deadlines[playerId] ?? Duration.zero) - elapsed;
    return left > Duration.zero ? left : Duration.zero;
  }

  @override
  String? denialFor(SkillEvent event) {
    if (event.action != SkillAction.nextTrack) return null;
    final left = remaining(event.playerId, event.elapsed);
    return left > Duration.zero
        ? '${definition.label} · ${remainingSeconds(left)}s remaining'
        : null;
  }

  @override
  bool recordSuccess(SkillEvent event) {
    if (event.action != SkillAction.nextTrack ||
        !_recorded.add(event.requestId)) {
      return false;
    }
    _deadlines[event.playerId] = event.elapsed + skipRecoveryDuration;
    return true;
  }
}
