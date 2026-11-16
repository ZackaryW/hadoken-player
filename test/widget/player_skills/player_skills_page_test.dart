import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/core/theme/app_theme.dart';
import 'package:troona/core/theme/components/glass_theme.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/skills/registry.dart';
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
import '../../helpers/probe_skill.dart';
import '../../helpers/manual_skill.dart';

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

  Future<void> drainServices(
    WidgetTester tester,
    Future<void> Function() operation,
  ) async {
    // Domain queues and subscription cancellation can straddle the widget's
    // fake-time zone. Drive both schedulers instead of leaving teardown pending.
    var done = false;
    Object? failure;
    operation().then(
      (_) {
        done = true;
      },
      onError: (Object error) {
        failure = error;
        done = true;
      },
    );
    for (var i = 0; i < 100 && !done; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(done, isTrue, reason: 'Service operation did not settle.');
    if (failure != null) throw failure!;
  }

  void check(String title, Future<void> Function(WidgetTester) body) {
    testWidgets(title, (tester) async {
      await drainServices(tester, initialize);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await drainServices(tester, () async {
          await dispatcher.dispose();
          await policy.dispose();
          await assignments.dispose();
          await profiles.dispose();
        });
        GlassTheme.overrideQuality(null);
      }
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  PlayerActionRequest request(String id) => PlayerActionRequest(
    requestId: id,
    binding: profiles.catalog.bindingFor(ProfileId.p2, PlayerAction.nextTrack)!,
    recognizedAt: Duration.zero,
  );

  for (final scale in [1.0, 2.0]) {
    check(
      'manual macro has a focused editor, conflicts and clearing at scale $scale',
      (tester) async {
        final definition = ManualTestSkill();
        await drainServices(tester, () async {
          await policy.dispose();
          await dispatcher.dispose();
          policy = SkillPolicy(
            assignments: assignments,
            clock: clock,
            definitions: [definition],
          );
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
          await controls.setAssigned(ProfileId.p1, definition.id, true);
        });
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await host(tester, PlayerSkillsPage(controls: controls), scale: scale);
        expect(find.text('Configure macro'), findsNothing);
        await tap(tester, find.byTooltip('About Manual test'));
        expect(find.textContaining('Activate (80)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Configure macro'));
        expect(find.text('Activation macro'), findsWidgets);
        expect(find.text('Not set'), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('set-skill-macro')));
        await tap(tester, find.byKey(const ValueKey('input-forward')));
        await tap(tester, find.text('Save combo'));
        expect(find.textContaining('Already assigned to P2'), findsOneWidget);
        await tap(tester, find.text('Clear draft'));
        await tap(tester, find.byKey(const ValueKey('input-pause')));
        await tap(tester, find.text('Save combo'));
        expect(
          profiles.catalog.macroFor(ProfileId.p1, definition.id.key)!.strokes,
          [const Stroke(InputButton.pause, StrokeKind.tap)],
        );
        expect(definition.runtime.events, isEmpty);
        expect(commands.calls, isEmpty);
        expect(find.text('Effort'), findsNothing);
        expect(find.text('Hold threshold'), findsNothing);
        await tap(tester, find.byKey(const ValueKey('clear-skill-macro')));
        expect(profiles.catalog.macros, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  check('passive-only skill details have no macro editor', (tester) async {
    await host(tester, PlayerSkillsPage(controls: controls));
    await tap(tester, find.byTooltip('About Skip Recovery'));
    expect(find.text('Configure macro'), findsNothing);
    expect(find.byKey(const ValueKey('set-skill-macro')), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    check('recovery details show action effort at scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await host(tester, PlayerSkillsPage(controls: controls), scale: scale);
      await tap(tester, find.byTooltip('About Skip Recovery'));
      expect(find.textContaining('skip (50)'), findsOneWidget);
      expect(
        find.textContaining('block your skip (50) for 10s'),
        findsOneWidget,
      );
      expect(find.textContaining('Other players: skip (50)'), findsOneWidget);
      expect(find.textContaining('Activate ('), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Done'));
      expect(find.textContaining('block your skip'), findsNothing);
    });
  }

  check('registered definition supplies tile metadata and recovery feedback', (
    tester,
  ) async {
    await drainServices(tester, policy.dispose);
    await drainServices(tester, dispatcher.dispose);
    final definition = ProbeSkill();
    policy = SkillPolicy(
      assignments: assignments,
      clock: clock,
      definitions: [definition],
    );
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
    await host(tester, PlayerSkillsPage(controls: controls));
    expect(find.text('Probe skill'), findsOneWidget);
    expect(find.text('Skip Recovery'), findsNothing);
    await tap(tester, find.byTooltip('About Probe skill'));
    expect(find.text('Probe description'), findsOneWidget);
    await tap(tester, find.text('Done'));
    await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
    definition.runtime.recovery = const Duration(seconds: 4);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Ready in 4s'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
    expect(find.text('P1 · Probe skill · 4s remaining'), findsOneWidget);
    expect(assignments.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p1);
    definition.runtime.recovery = Duration.zero;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
    await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
    expect(find.text('Inactive'), findsOneWidget);
  });

  check('square tile lights up, turns gray and exposes exclusive owner state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(411, 891));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await host(tester, PlayerSkillsPage(controls: controls));
    final tile = find.byKey(const ValueKey('assign-skip-recovery'));
    final surface = find.byKey(
      const ValueKey('skill-tile-surface-skip-recovery'),
    );
    final size = tester.getSize(surface);
    expect(size.width, closeTo(size.height, .01));
    expect(size.width, lessThan(200));
    BoxDecoration decoration() =>
        tester.widget<AnimatedContainer>(surface).decoration! as BoxDecoration;
    final gray = decoration().color;
    expect(find.text('Inactive'), findsOneWidget);
    await tap(tester, tile);
    expect(decoration().color, isNot(gray));
    expect(decoration().boxShadow, isNotEmpty);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Skip Recovery'))
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isTrue,
    );
    semantics.dispose();
    await tap(tester, find.text('P2'));
    expect(find.text('Owned by P1'), findsOneWidget);
    expect(decoration().color, gray);
    expect(tester.widget<InkWell>(tile).onTap, isNull);
    await tap(tester, tile);
    expect(assignments.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p1);
    await tap(tester, find.byTooltip('About Skip Recovery'));
    expect(find.text(SkillId.skipRecovery.description), findsOneWidget);
    await tap(tester, find.text('Done'));
    await tap(tester, find.text('P1'));
    await tap(tester, tile);
    expect(find.text('Inactive'), findsOneWidget);
    expect(decoration().color, gray);
    expect(decoration().boxShadow, isEmpty);
    await tap(tester, find.text('P2'));
    await tap(tester, tile);
    expect(assignments.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p2);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    check('skill tiles fit 360x640 at $scale text scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
      await host(tester, PlayerSkillsPage(controls: controls), scale: scale);
      expect(find.text('Owned by P2'), findsOneWidget);
      final surface = find.byKey(
        const ValueKey('skill-tile-surface-skip-recovery'),
      );
      final size = tester.getSize(surface);
      expect(size.width, closeTo(size.height, .01));
      await tap(tester, find.text('P2'));
      await tap(tester, find.byKey(const ValueKey('assign-skip-recovery')));
      expect(find.text('Inactive'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
      expect(find.text('Active'), findsOneWidget);
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
      expect(find.text('Active'), findsOneWidget);
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
  check('failed assignment shows feedback and retains inactive tile state', (
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
    await drainServices(tester, assignments.dispose);
    store.document = '{"version":1,"profiles":{"p1":["unknown"]}}';
    assignments = await SkillAssignmentRepository.open(
      store,
      profileExists: (_) => true,
    );
    // Replace policy as a new process would, with the loaded assignments.
    await drainServices(tester, policy.dispose);
    await drainServices(tester, dispatcher.dispose);
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
