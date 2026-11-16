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

  Future<void> setAssigned(ProfileId profile, SkillId skill, bool enabled) =>
      dispatcher.runOrdered(() async {
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
