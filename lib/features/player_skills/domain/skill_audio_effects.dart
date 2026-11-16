import 'dart:convert';
import 'package:troona/skills/skill.dart';
import '../../player/domain/ports/skill_audio_effects_port.dart';
import 'skill_coordinator.dart';

final class SkillAudioEffects implements SkillCapabilityAdapter {
  final SkillAudioEffectsPort port;
  const SkillAudioEffects(this.port);
  @override
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  ) async {
    if (request is! StartAudioMix) {
      return AppliedCapability(
        CapabilityResult(
          effectId: request.effectId,
          status: CapabilityStatus.unsupported,
        ),
      );
    }
    final id = jsonEncode([
      origin.sessionId,
      origin.owner,
      origin.skillKey,
      origin.invocationId,
      request.effectId,
    ]);
    final result = await port.startAudioMix(
      request,
      id: id,
      sessionId: origin.sessionId,
    );
    final applied = result.status == CapabilityStatus.applied;
    return AppliedCapability(
      CapabilityResult(
        effectId: request.effectId,
        status: result.status,
        reason: result.reason,
        handle: applied
            ? EffectHandle(id: id, origin: origin, deadline: result.deadline!)
            : null,
      ),
      cleanup: applied ? () => port.stopAudioMix(id) : null,
    );
  }
}
