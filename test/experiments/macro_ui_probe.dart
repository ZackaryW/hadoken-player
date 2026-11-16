// In-memory device-only UI fixture. Never reads or writes saved user profiles.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:troona/core/theme/app_theme.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/presentation/player_skills_page.dart';
import 'package:troona/features/player_skills/skill_controls.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/l10n/app_localizations.dart';
import 'package:troona/skills/skill.dart';
import '../helpers/scripted_skill.dart';
import '../helpers/skill_fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profiles = await ProfileRepository.open(MemoryProfiles());
  await profiles.addProfile();
  final skill = ScriptedSkill(
    'device-probe',
    label: 'Capability probe',
    react: (_, _) => SkillReaction.none,
  );
  final assignments = await SkillAssignmentRepository.open(
    MemorySkills(),
    profileExists: (_) => true,
    definitions: [skill],
  );
  await assignments.setAssigned(ProfileId.p1, skill.id, true);
  final policy = SkillPolicy(
    assignments: assignments,
    clock: FakeSkillClock(),
    definitions: [skill],
  );
  final dispatcher = PlayerActionDispatcher(
    playback: SkillCommands(),
    abilities: policy,
    catalog: () => profiles.catalog,
  );
  final controls = SkillControls(
    profiles: profiles,
    assignments: assignments,
    policy: policy,
    dispatcher: dispatcher,
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: PlayerSkillsPage(controls: controls)),
      ),
    ],
  );
  runApp(
    MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
