import 'package:troona/skills/skill.dart';

/// Test-only definitions exercise the same registry and adapters as skill code.
final class ScriptedSkill extends SkillDefinition {
  @override
  final SkillId id;
  @override
  final String label;
  @override
  final Effort activationEffort;
  final ScriptedRuntime runtime;
  ScriptedSkill(
    String key, {
    String? label,
    this.activationEffort = Effort.normal,
    required SkillReaction Function(SkillRuntimeEvent, SkillContext) react,
  }) : id = SkillId(key),
       label = label ?? key,
       runtime = ScriptedRuntime(react);
  @override
  String get summary => 'Test skill';
  @override
  String get description => 'Test-only skill definition.';
  @override
  Set<SkillTrigger> get triggers => const {
    SkillTrigger.actionSucceeded,
    SkillTrigger.comboObserved,
    SkillTrigger.manualActivation,
    SkillTrigger.effectExpired,
  };
  @override
  SkillRuntime createRuntime() => runtime;
}

final class ScriptedRuntime extends SkillRuntime {
  final SkillReaction Function(SkillRuntimeEvent, SkillContext) react;
  final events = <SkillRuntimeEvent>[];
  final contexts = <SkillContext>[];
  final results = <CapabilityResult>[];
  ScriptedRuntime(this.react);
  @override
  SkillReaction onEvent(SkillRuntimeEvent event, SkillContext context) {
    events.add(event);
    contexts.add(context);
    return react(event, context);
  }

  @override
  void onCapabilityResult(CapabilityResult result, SkillContext context) {
    results.add(result);
  }
}
