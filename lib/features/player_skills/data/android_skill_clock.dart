import 'package:flutter/services.dart';
import '../domain/skill_policy.dart';

/// Android's elapsedRealtime includes deep sleep and ignores wall-clock changes.
/// Queried only at action/status boundaries; never awaited during app startup.
final class AndroidSkillClock implements SkillClock {
  static const channel = MethodChannel('com.hadoken.player/elapsed_clock');
  const AndroidSkillClock();
  @override
  Future<Duration> now() async {
    final milliseconds = await channel.invokeMethod<int>('elapsedRealtime');
    if (milliseconds == null || milliseconds < 0) {
      throw StateError('Elapsed clock unavailable');
    }
    return Duration(milliseconds: milliseconds);
  }
}
