import 'package:troona/skills/skill.dart';

final class AudioMixResult {
  final CapabilityStatus status;
  final String reason;
  final Duration? deadline;
  const AudioMixResult(this.status, this.reason, {this.deadline});
}

abstract interface class AudioDuckingPort {
  Future<void> setDuckGain(double gain);
}

abstract interface class SkillAudioEffectsPort implements AudioDuckingPort {
  bool get supportsAudioMix;
  Future<AudioMixResult> startAudioMix(
    StartAudioMix request, {
    required String id,
    required String sessionId,
  });
  Future<void> stopAudioMix(String id);
}
