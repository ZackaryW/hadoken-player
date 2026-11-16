import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/core/theme/app_theme.dart';
import 'package:troona/core/theme/components/glass_theme.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_catalog.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/skill_controls.dart';
import 'package:troona/features/player_skills/presentation/player_skills_page.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/input_bindings/presentation/now_playing_combo_controls.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/l10n/app_localizations.dart';
import '../../helpers/skill_fakes.dart';
import '../../helpers/roboto.dart';

void main() {
  setUpAll(loadRoboto);
  late ProfileRepository profiles;
  late SkillAssignmentRepository assignments;
  late SkillPolicy policy;
  late PlayerActionDispatcher dispatcher;
  late SkillControls controls;
  late FakeSkillClock clock;
  late SkillCommands commands;
  late MemorySkills store;

  Future<void> initialize() async {
    GlassTheme.overrideQuality(GlassQuality.off);
    profiles = await ProfileRepository.open(MemoryProfiles());
    await profiles.addProfile();
    await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
      const Stroke(InputButton.forward, StrokeKind.tap),
    ]);
    store = MemorySkills();
    assignments = await SkillAssignmentRepository.open(
      store,
      profileExists: (id) => profiles.catalog.names.containsKey(id),
    );
    clock = FakeSkillClock();
    commands = SkillCommands();
    policy = SkillPolicy(assignments: assignments, clock: clock);
    dispatcher = PlayerActionDispatcher(
      playback: commands,
      catalog: () => profiles.catalog,
      abilities: policy,
    );
    controls = SkillControls(
      profiles: profiles,
      assignments: assignments,
      policy: policy,
      dispatcher: dispatcher,
    );
  }

  Future<void> host(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: robotoTheme(AppTheme.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  void check(String title, Future<void> Function(WidgetTester) body) {
    testWidgets(title, (tester) async {
      await initialize();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await dispatcher.dispose();
        await policy.dispose();
        await assignments.dispose();
        await profiles.dispose();
        GlassTheme.overrideQuality(null);
      }
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  PlayerActionRequest request(String id) => PlayerActionRequest(
    requestId: id,
    binding: profiles.catalog.bindingFor(ProfileId.p2, PlayerAction.nextTrack)!,
    recognizedAt: Duration.zero,
  );

  check(
    'focused skills page persists assignments and opens descriptions only on demand',
    (tester) async {
      await host(tester, PlayerSkillsPage(controls: controls));
      expect(find.text('P3'), findsNothing);
      expect(find.text('Set'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(SkillId.skipRecovery.description), findsNothing);
      await tap(tester, find.text('P2'));
      await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
      expect(
        assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
        isTrue,
      );
      expect(find.text('Ready'), findsOneWidget);
      final reloaded = SkillAssignmentRepository.decode(store.document);
      expect(reloaded.has(ProfileId.p2, SkillId.skipRecovery), isTrue);
      await tap(tester, find.byTooltip('About Skip Recovery'));
      expect(find.text(SkillId.skipRecovery.description), findsOneWidget);
      await tap(tester, find.text('Done'));
    },
  );
  check(
    'cooldown rejects edits, survives navigation and refreshes on resume without replay',
    (tester) async {
      await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
      await dispatcher.dispatch(request('skip'));
      await host(tester, PlayerSkillsPage(controls: controls));
      await tap(tester, find.text('P2'));
      expect(find.text('Ready in 10s'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
      expect(
        assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
        isTrue,
      );
      expect(find.textContaining('P2 · Skip Recovery'), findsOneWidget);
      await host(tester, const Scaffold());
      clock.elapsed = const Duration(seconds: 3);
      await host(tester, PlayerSkillsPage(controls: controls));
      await tap(tester, find.text('P2'));
      expect(find.text('Ready in 7s'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.elapsed = const Duration(seconds: 12);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
      expect(commands.calls.length, 1);
      await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
      expect(
        assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
        isFalse,
      );
    },
  );
  check('Now Playing denial identifies owner skill and remaining time', (
    tester,
  ) async {
    await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
    await dispatcher.dispatch(request('first'));
    clock.elapsed = const Duration(seconds: 6);
    final inputs = ProfileControls(profiles: profiles, dispatcher: dispatcher);
    await host(
      tester,
      Scaffold(body: NowPlayingComboControls(controls: inputs)),
    );
    await tap(tester, find.byKey(const ValueKey('input-forward')));
    expect(find.text('P2 · Skip Recovery · 4s remaining'), findsOneWidget);
    expect(commands.calls.length, 1);
  });
  check('failed assignment shows feedback and retains switch state', (
    tester,
  ) async {
    store.fail = true;
    await host(tester, PlayerSkillsPage(controls: controls));
    await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
    expect(find.text('Could not save skill. Try again.'), findsOneWidget);
    expect(
      assignments.catalog.has(ProfileId.p1, SkillId.skipRecovery),
      isFalse,
    );
  });
  check('unknown skills are visible and layout supports large text', (
    tester,
  ) async {
    await assignments.dispose();
    store.document = '{"version":1,"profiles":{"p1":["unknown"]}}';
    assignments = await SkillAssignmentRepository.open(
      store,
      profileExists: (_) => true,
    );
    // Replace policy as a new process would, with the loaded assignments.
    await policy.dispose();
    await dispatcher.dispose();
    policy = SkillPolicy(assignments: assignments, clock: clock);
    dispatcher = PlayerActionDispatcher(
      playback: commands,
      catalog: () => profiles.catalog,
      abilities: policy,
    );
    controls = SkillControls(
      profiles: profiles,
      assignments: assignments,
      policy: policy,
      dispatcher: dispatcher,
    );
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await host(tester, PlayerSkillsPage(controls: controls), scale: 2);
    expect(find.text('Unavailable skill: unknown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
