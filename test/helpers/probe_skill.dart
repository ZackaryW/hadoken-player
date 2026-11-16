import 'package:troona/skills/skill.dart';

/// Replaces a registered definition to prove consumers use its contract.
final class ProbeSkill extends SkillDefinition {
  final runtime = ProbeSkillRuntime();
  @override
  SkillId get id => SkillId.skipRecovery;
  @override
  String get label => 'Probe skill';
  @override
  String get summary => 'Probe summary';
  @override
  String get description => 'Probe description';
  @override
  SkillRuntime createRuntime() => runtime;
}

final class ProbeSkillRuntime extends SkillRuntime {
  final checks = <SkillEvent>[];
  final successes = <SkillEvent>[];
  String? denial;
  Effort blockEffort = Effort.normal;
  Duration recovery = Duration.zero;
  @override
  String? denialFor(SkillEvent event) {
    checks.add(event);
    return denial;
  }

  @override
  SkillActionBlock? decide(
    SkillTarget target,
    SkillContext context,
    String requestId,
  ) {
    final block = super.decide(target, context, requestId);
    return block == null
        ? null
        : SkillActionBlock(block.reason, effort: blockEffort);
  }

  @override
  bool recordSuccess(SkillEvent event) {
    successes.add(event);
    return true;
  }

  @override
  Duration remaining(String playerId, Duration elapsed) => recovery;
}
