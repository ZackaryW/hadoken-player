import 'package:troona/skills/skill.dart';
import 'skill_coordinator.dart';

/// Enters the policy's already ordered operation, never the input dispatcher.
final class SkillPlayback implements SkillCapabilityAdapter {
  final Future<CapabilityResult> Function(
    ExecutePlayerAction,
    SkillOrigin,
    SkillExecutionBudget,
  )
  execute;

  const SkillPlayback(this.execute);

  @override
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  ) async => AppliedCapability(
    request is ExecutePlayerAction
        ? await execute(request, origin, budget)
        : CapabilityResult(
            effectId: request.effectId,
            status: CapabilityStatus.unsupported,
            reason: 'Not a playback request.',
          ),
  );
}
