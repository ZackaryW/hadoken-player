import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/core/theme/app_theme.dart';
import 'package:troona/core/theme/components/glass_theme.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/input_bindings/presentation/combo_pad_page.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/features/profiles/presentation/binding_recorder.dart';
import 'package:troona/features/profiles/presentation/profiles_page.dart';
import 'package:troona/features/profiles/presentation/combo_timing_page.dart';
import 'package:troona/l10n/app_localizations.dart';
import 'package:troona/shared/widgets/app_button.dart';
import '../../helpers/roboto.dart';

class WidgetClock implements InputClock {
  final DateTime Function() now;
  late final DateTime start = now();
  WidgetClock(this.now);
  @override
  Duration get elapsed => now().difference(start);
  @override
  CancelInputTimer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback).cancel;
}

class Store implements ProfileDocumentStore {
  String? document;
  @override
  Future<String?> read() async => document;
  @override
  Future<void> write(String value) async => document = value;
}

class Commands implements PlaybackCommands {
  final actions = <PlayerAction>[];
  @override
  Future<CommandResult> execute(PlayerAction action) async {
    actions.add(action);
    return const CommandResult(ActionStatus.success, 'Playback updated.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRoboto);
  late Store store;
  late ProfileRepository repository;
  late Commands commands;
  late ProfileControls controls;
  void controlsTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        // These futures belong to the widget test's fake clock; finish them
        // here, before the test framework leaves that clock for tearDown.
        await tester.pumpWidget(const SizedBox.shrink());
        await controls.dispatcher.dispose();
        await repository.dispose();
      }
    });
  }

  Future<void> initialize(WidgetTester tester) async {
    GlassTheme.overrideQuality(GlassQuality.off);
    store = Store();
    repository = await ProfileRepository.open(store);
    commands = Commands();
    final dispatcher = PlayerActionDispatcher(
      playback: commands,
      catalog: () => repository.catalog,
    );
    controls = ProfileControls(
      profiles: repository,
      dispatcher: dispatcher,
      clock: WidgetClock(tester.binding.clock.now),
    );
  }

  Future<void> host(WidgetTester tester, Widget child, {double scale = 1}) =>
      tester.pumpWidget(
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
  Future<void> press(WidgetTester tester, String button, {int ms = 100}) async {
    final finder = find.byKey(ValueKey('input-$button'));
    await tester.ensureVisible(finder);
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(Duration(milliseconds: ms));
    await gesture.up();
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  controlsTest(
    'profiles contain only bindings and explicitly add up to three players',
    (tester) async {
      await initialize(tester);
      await host(tester, ProfilesPage(controls: controls));
      expect(find.text('P2'), findsNothing);
      expect(find.text('P3'), findsNothing);
      expect(find.byType(TimingSettings), findsNothing);
      expect(find.text('Open combo pad'), findsNothing);
      expect(find.text('How to set a combo'), findsNothing);
      await tapVisible(tester, find.text('Add profile'));
      expect(repository.catalog.names.keys, [ProfileId.p1, ProfileId.p2]);
      await tapVisible(tester, find.text('Add profile'));
      expect(repository.catalog.names.keys, ProfileId.values);
      expect(find.text('Add profile'), findsNothing);
      final reopened = await ProfileRepository.open(store);
      expect(reopened.catalog.names.keys, ProfileId.values);
      await reopened.dispose();
      expect(commands.actions, isEmpty);
    },
  );

  controlsTest(
    'Set records mixed strokes, saves and persists without playback',
    (tester) async {
      await initialize(tester);
      await host(tester, ProfilesPage(controls: controls));
      await tapVisible(tester, find.byKey(const ValueKey('set-nextTrack')));
      final save = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save combo'),
      );
      expect(save.onPressed, isNull);
      await press(tester, 'forward');
      await press(tester, 'backward', ms: 600);
      expect(
        find.bySemanticsLabel('Forward tap, then Backward hold'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Save combo'));
      expect(repository.catalog.bindings.single.strokes.map((s) => s.kind), [
        StrokeKind.tap,
        StrokeKind.hold,
      ]);
      final recovered = await ProfileRepository.open(store);
      expect(
        recovered.catalog.bindings.single.comboKey,
        repository.catalog.bindings.single.comboKey,
      );
      await recovered.dispose();
      expect(commands.actions, isEmpty);
    },
  );

  controlsTest(
    'duplicate feedback names owner and action; cancel preserves binding',
    (tester) async {
      await initialize(tester);
      await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
        const Stroke(InputButton.forward, StrokeKind.tap),
      ]);
      await host(tester, ProfilesPage(controls: controls));
      await tapVisible(tester, find.text('Add profile'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('set-togglePlayback')),
      );
      await press(tester, 'forward');
      await tapVisible(tester, find.text('Save combo'));
      expect(find.text('Already assigned to P1: Next track.'), findsOneWidget);
      expect(repository.catalog.bindings.length, 1);
      await tapVisible(tester, find.text('Cancel'));
      expect(repository.catalog.bindings.single.profile, ProfileId.p1);
      expect(commands.actions, isEmpty);
    },
  );

  controlsTest(
    'shared prefix details are on demand and Clear stays beside Set',
    (tester) async {
      await initialize(tester);
      const f = Stroke(InputButton.forward, StrokeKind.tap);
      await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [f]);
      await repository.addProfile();
      await repository.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
        f,
        const Stroke(InputButton.backward, StrokeKind.hold),
      ]);
      await host(tester, ProfilesPage(controls: controls));
      expect(find.textContaining('500 ms'), findsNothing);
      final set = find.byKey(const ValueKey('set-nextTrack'));
      final clear = find.byKey(const ValueKey('clear-nextTrack'));
      expect(tester.getCenter(set).dy, tester.getCenter(clear).dy);
      expect(tester.getCenter(clear).dx, greaterThan(tester.getCenter(set).dx));
      await tapVisible(tester, find.byTooltip('Shared prefix details'));
      expect(
        find.text('The shorter combo waits up to 500 ms for the next press.'),
        findsOneWidget,
      );
      expect(commands.actions, isEmpty);
      await tapVisible(tester, find.text('Done'));
      await tapVisible(tester, find.byKey(const ValueKey('clear-nextTrack')));
      expect(
        repository.catalog.bindingFor(ProfileId.p1, PlayerAction.nextTrack),
        isNull,
      );
      expect(ProfileRepository.decode(store.document).bindings.length, 1);
      expect(find.byKey(const ValueKey('prefix-nextTrack')), findsNothing);
      expect(find.byKey(const ValueKey('clear-nextTrack')), findsNothing);
      expect(find.byKey(const ValueKey('set-nextTrack')), findsOneWidget);
    },
  );

  controlsTest(
    'recorder shows live hold, rejects sixth stroke, undo and clear work',
    (tester) async {
      await initialize(tester);
      await host(
        tester,
        Scaffold(
          body: BindingRecorder(
            controls: controls,
            profile: ProfileId.p1,
            action: PlayerAction.stop,
          ),
        ),
      );
      final target = find.byKey(const ValueKey('input-forward'));
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('HOLD'), findsOneWidget);
      expect(find.text('0 / 5 strokes'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await press(tester, 'pause');
      }
      expect(find.text('5 / 5 strokes'), findsOneWidget);
      expect(find.textContaining('Maximum five strokes'), findsOneWidget);
      expect(find.bySemanticsLabel('Backward: tap or hold'), findsOneWidget);
      await tapVisible(tester, find.text('Undo'));
      expect(find.text('4 / 5 strokes'), findsOneWidget);
      await tapVisible(tester, find.text('Clear draft'));
      expect(find.text('0 / 5 strokes'), findsOneWidget);
      expect(commands.actions, isEmpty);
    },
  );

  controlsTest('runtime attributes P2 and practice has no effects', (
    tester,
  ) async {
    await initialize(tester);
    await repository.addProfile();
    await repository.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
      const Stroke(InputButton.forward, StrokeKind.tap),
    ]);
    await host(tester, ComboPadPage(controls: controls));
    await press(tester, 'forward');
    await tester.pumpAndSettle();
    expect(find.text('P2 · success: Playback updated.'), findsOneWidget);
    expect(commands.actions, [PlayerAction.nextTrack]);
    await tapVisible(tester, find.text('Practice'));
    await press(tester, 'forward');
    await tester.pumpAndSettle();
    expect(find.textContaining('Practice · P2'), findsOneWidget);
    expect(commands.actions.length, 1);
  });

  controlsTest('app focus loss cancels a pending prefix and a held release', (
    tester,
  ) async {
    await initialize(tester);
    const f = Stroke(InputButton.forward, StrokeKind.tap);
    await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [f]);
    await repository.addProfile();
    await repository.setBinding(ProfileId.p2, PlayerAction.stop, [
      f,
      const Stroke(InputButton.backward, StrokeKind.hold),
    ]);
    await host(tester, ComboPadPage(controls: controls));
    await press(tester, 'forward');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));
    expect(commands.actions, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('input-forward'))),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(commands.actions, isEmpty);
  });

  controlsTest('timing editor rejects zero and saves shared values', (
    tester,
  ) async {
    await initialize(tester);
    await host(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: TimingSettings(repository: repository),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('hold-ms')), '0');
    await tapVisible(tester, find.text('Save timing'));
    expect(repository.catalog.timing.holdMs, 600);
    expect(find.textContaining('Enter positive'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('hold-ms')), '800');
    await tester.enterText(find.byKey(const ValueKey('gap-ms')), '650');
    await tapVisible(tester, find.text('Save timing'));
    expect(repository.catalog.timing.holdMs, 800);
    expect(repository.catalog.timing.gapMs, 650);
  });

  controlsTest(
    'two recorded profiles survive restart and resolve prefixes exactly once',
    (tester) async {
      await initialize(tester);
      await host(tester, ProfilesPage(controls: controls));
      await tapVisible(tester, find.byKey(const ValueKey('set-nextTrack')));
      await press(tester, 'forward');
      await tapVisible(tester, find.text('Save combo'));
      await tapVisible(tester, find.text('Add profile'));
      await tapVisible(tester, find.byKey(const ValueKey('set-nextTrack')));
      await press(tester, 'forward');
      await press(tester, 'backward', ms: 600);
      await tapVisible(tester, find.text('Save combo'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('set-togglePlayback')),
      );
      await press(tester, 'forward');
      await tapVisible(tester, find.text('Save combo'));
      expect(find.text('Already assigned to P1: Next track.'), findsOneWidget);
      await tapVisible(tester, find.text('Cancel'));
      expect(repository.catalog.bindings.length, 2);
      expect(commands.actions, isEmpty);

      final previousRepository = repository;
      final previousDispatcher = controls.dispatcher;
      repository = await ProfileRepository.open(store);
      controls = ProfileControls(
        profiles: repository,
        dispatcher: PlayerActionDispatcher(
          playback: commands,
          catalog: () => repository.catalog,
        ),
        clock: WidgetClock(tester.binding.clock.now),
      );
      await host(tester, ComboPadPage(controls: controls));
      await previousDispatcher.dispose();
      await previousRepository.dispose();
      await press(tester, 'forward');
      await tester.pump(const Duration(milliseconds: 499));
      expect(commands.actions, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('P1 · success: Playback updated.'), findsOneWidget);
      expect(commands.actions.length, 1);
      await press(tester, 'forward');
      await press(tester, 'backward', ms: 600);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('P2 · success: Playback updated.'), findsOneWidget);
      expect(commands.actions, [
        PlayerAction.nextTrack,
        PlayerAction.nextTrack,
      ]);
    },
  );

  for (final scale in [1.0, 1.3, 2.0]) {
    controlsTest(
      'five-stroke shared binding stays grouped at text scale $scale',
      (tester) async {
        await initialize(tester);
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const f = Stroke(InputButton.forward, StrokeKind.tap);
        const h = Stroke(InputButton.backward, StrokeKind.hold);
        await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
          f,
          h,
          f,
          h,
          f,
        ]);
        await repository.addProfile();
        await repository.setBinding(ProfileId.p2, PlayerAction.nextTrack, [f]);
        await host(tester, ProfilesPage(controls: controls), scale: scale);
        await tester.pumpAndSettle();
        final set = find.byKey(const ValueKey('set-nextTrack'));
        final clear = find.byKey(const ValueKey('clear-nextTrack'));
        final info = find.byKey(const ValueKey('prefix-nextTrack'));
        expect(tester.getCenter(set).dy, tester.getCenter(clear).dy);
        final row = tester.getRect(
          find.byKey(const ValueKey('binding-nextTrack')),
        );
        expect(tester.getRect(info).right, lessThanOrEqualTo(row.right));
        expect(tester.takeException(), isNull);
        await tapVisible(tester, info);
        expect(find.textContaining('500 ms'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('Done'));
        await tapVisible(tester, set);
        expect(find.byType(BindingRecorder), findsOneWidget);
        await tapVisible(tester, find.text('Cancel'));
        expect(
          repository.catalog
              .bindingFor(ProfileId.p1, PlayerAction.nextTrack)!
              .strokes
              .length,
          5,
        );
      },
    );
  }

  for (final scale in [1.3, 2.0]) {
    controlsTest(
      'profiles, recorder and pad fit 360x640 at text scale $scale',
      (tester) async {
        await initialize(tester);
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final page in <Widget>[
          ProfilesPage(controls: controls),
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: BindingRecorder(
                controls: controls,
                profile: ProfileId.p1,
                action: PlayerAction.seekBackward,
              ),
            ),
          ),
          ComboPadPage(controls: controls),
          ComboTimingPage(repository: repository),
        ]) {
          await host(tester, page, scale: scale);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
