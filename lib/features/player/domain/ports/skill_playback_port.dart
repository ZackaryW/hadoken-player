import 'package:troona/skills/skill.dart';

/// Snapshots are evaluated at use time, even while UI timers are suspended.
abstract interface class SkillPlaybackPort {
  SkillPlaybackSnapshot get skillPlayback;
  Stream<void> get skillPlaybackChanges;
}
