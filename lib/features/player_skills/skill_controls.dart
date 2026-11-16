import '../profiles/domain/profile_catalog.dart';
import '../profiles/domain/profile_repository.dart';
import '../player_actions/domain/action_dispatcher.dart';
import 'domain/skill_assignments.dart';
import 'domain/skill_catalog.dart';
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
        final left = await policy.remaining(profile);
        if (left > Duration.zero) throw SkillCooldown(profile, left);
        await assignments.setAssigned(profile, skill, enabled);
      });
}
