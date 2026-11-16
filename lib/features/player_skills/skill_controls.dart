import '../profiles/domain/profile_catalog.dart';
import '../profiles/domain/profile_repository.dart';
import '../player_actions/domain/action_dispatcher.dart';
import 'domain/skill_assignments.dart';
import 'package:troona/skills/registry.dart';
import 'domain/skill_policy.dart';

final class SkillControls {
  final ProfileRepository profiles;
  final SkillAssignmentRepository assignments;
  final SkillPolicy policy;
  final PlayerActionDispatcher dispatcher;
  const SkillControls({
    required this.profiles,
    required this.assignments,
    required this.policy,
    required this.dispatcher,
  });

  Future<void> setMacro(
    ProfileId profile,
    SkillId skill,
    List<Stroke>? strokes,
  ) {
    final draft = strokes == null ? null : List<Stroke>.unmodifiable(strokes);
    return dispatcher.runOrdered(() async {
      final definition = policy.definitionFor(skill.key);
      if (definition == null ||
          !definition.triggers.contains(SkillTrigger.manualActivation)) {
        throw const FormatException('This skill has no manual activation.');
      }
      if (draft != null && !assignments.catalog.has(profile, skill)) {
        throw const FormatException('Equip this skill to record its macro.');
      }
      await profiles.setSkillMacro(profile, skill.key, draft);
    });
  }

  Future<void> setAssigned(ProfileId profile, SkillId skill, bool enabled) =>
      dispatcher.runOrdered(() async {
        await policy.effects.retireDue(await policy.clock.now());
        final recovery = await policy.recoveryFor(profile);
        if (recovery != null) {
          throw SkillCooldown(
            profile,
            recovery.remaining,
            skill: recovery.definition,
          );
        }
        await assignments.setAssigned(profile, skill, enabled);
      });
}
