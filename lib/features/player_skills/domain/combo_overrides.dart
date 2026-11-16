import 'dart:convert';
import 'package:troona/skills/skill.dart';
import '../../profiles/domain/effective_bindings.dart';
import '../../profiles/domain/profile_catalog.dart';
import 'skill_coordinator.dart';

Stroke appStroke(SkillStroke stroke) => switch (stroke) {
  SkillStroke.forwardTap => const Stroke(InputButton.forward, StrokeKind.tap),
  SkillStroke.forwardHold => const Stroke(InputButton.forward, StrokeKind.hold),
  SkillStroke.pauseTap => const Stroke(InputButton.pause, StrokeKind.tap),
  SkillStroke.pauseHold => const Stroke(InputButton.pause, StrokeKind.hold),
  SkillStroke.backwardTap => const Stroke(InputButton.backward, StrokeKind.tap),
  SkillStroke.backwardHold => const Stroke(
    InputButton.backward,
    StrokeKind.hold,
  ),
};

SkillStroke skillStroke(Stroke stroke) =>
    SkillStroke.values.singleWhere((s) => appStroke(s) == stroke);

final class ComboOverrides implements SkillCapabilityAdapter {
  final EffectiveBindings bindings;
  final String Function(String) sourceLabel;
  ComboOverrides(this.bindings, this.sourceLabel);
  @override
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  ) async {
    AppliedCapability result(CapabilityStatus status, String reason) =>
        AppliedCapability(
          CapabilityResult(
            effectId: request.effectId,
            status: status,
            reason: reason,
          ),
        );
    if (request is! OverrideCombos) {
      return result(CapabilityStatus.unsupported, 'Not a combo override.');
    }
    final handle = EffectHandle(
      id: jsonEncode([
        origin.sessionId,
        origin.owner,
        origin.skillKey,
        origin.invocationId,
        request.effectId,
      ]),
      origin: origin,
      deadline: context.elapsed + request.lifetime,
    );
    try {
      bindings.applyOverrides(
        request.replacements.map(
          (r) => ActionBinding(
            ProfileId.values.byName(r.player),
            PlayerAction.values.byName(r.action.name),
            r.combo.strokes.map(appStroke),
          ),
        ),
        handle,
        sourceLabel(origin.skillKey),
      );
    } on BindingConflict catch (error) {
      return result(CapabilityStatus.denied, '$error');
    } on FormatException catch (error) {
      return result(CapabilityStatus.denied, error.message);
    } on ArgumentError {
      return result(
        CapabilityStatus.denied,
        'The target player is unavailable.',
      );
    }
    return AppliedCapability(
      CapabilityResult(
        effectId: request.effectId,
        status: CapabilityStatus.applied,
        handle: handle,
        appliedRevision: bindings.catalog.revision,
      ),
      cleanup: () async => bindings.removeOverrides(handle.id),
    );
  }
}
