import 'package:troona/skills/skill.dart';

final class ManualTestSkill extends SkillDefinition {
  final runtime = ManualTestRuntime();
  @override
  SkillId get id => SkillId.skipRecovery;
  @override
  String get label => 'Manual test';
  @override
  String get summary => 'Test activation';
  @override
  String get description => 'Test-only manual activation.';
  @override
  Set<SkillTrigger> get triggers => const {SkillTrigger.manualActivation};
  @override
  Effort get activationEffort => Effort(80);
  @override
  SkillRuntime createRuntime() => runtime;
}

final class ManualTestRuntime extends SkillRuntime {
  final events = <SkillRuntimeEvent>[];
  final contexts = <SkillContext>[];
  @override
  SkillReaction onEvent(SkillRuntimeEvent event, SkillContext context) {
    events.add(event);
    contexts.add(context);
    return SkillReaction(stateChanged: true);
  }
}
