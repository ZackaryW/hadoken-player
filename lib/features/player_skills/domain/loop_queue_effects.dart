import 'dart:convert';
import 'package:troona/skills/skill.dart';
import '../../player/domain/ports/loop_queue_port.dart';
import 'skill_coordinator.dart';

final class LoopQueueEffects implements SkillCapabilityAdapter {
  final LoopQueuePort port;
  final Future<Duration> Function() now;
  const LoopQueueEffects(this.port, this.now);
  @override
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  ) async {
    if (request is FindSongs) {
      return AppliedCapability(
        CapabilityResult(
          effectId: request.effectId,
          status: CapabilityStatus.applied,
          songs: await port.findSkillSongs(request.query, limit: request.limit),
        ),
      );
    }
    if (request is! EditLoopQueue) {
      return AppliedCapability(
        CapabilityResult(
          effectId: request.effectId,
          status: CapabilityStatus.unsupported,
          reason: 'Not a queue request.',
        ),
      );
    }
    final planId = jsonEncode([
      origin.sessionId,
      origin.owner,
      origin.skillKey,
      origin.invocationId,
      request.effectId,
    ]);
    final elapsed = await now();
    final result = await port.editLoopQueue(
      request,
      sessionId: origin.sessionId,
      expectedLoop: context.loop,
      planId: planId,
      elapsed: elapsed,
    );
    final timed =
        result.status == CapabilityStatus.applied &&
        request.loops is! CurrentLoop;
    return AppliedCapability(
      CapabilityResult(
        effectId: request.effectId,
        status: result.status,
        reason: result.reason,
        appliedRevision: result.status == CapabilityStatus.applied
            ? result.revision
            : null,
        handle: timed
            ? EffectHandle(
                id: planId,
                origin: origin,
                deadline: result.deadline!,
              )
            : null,
      ),
      cleanup: timed
          ? () async =>
                port.revokeLoopPlan(origin.sessionId, planId, await now())
          : null,
    );
  }
}
