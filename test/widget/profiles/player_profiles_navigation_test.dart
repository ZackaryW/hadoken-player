import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:troona/core/di/injection.dart';
import 'package:troona/core/router/app_router.dart';
import 'package:troona/core/theme/app_theme.dart';
import 'package:troona/core/theme/components/glass_theme.dart';
import 'package:troona/features/player/presentation/bloc/palette/track_palette_cubit.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/features/profiles/presentation/profiles_page.dart';
import 'package:troona/l10n/app_localizations.dart';
import 'package:troona/shared/widgets/app_button.dart';

class _Store implements ProfileDocumentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) async {}
}

class _Commands implements PlaybackCommands {
  @override
  Future<CommandResult> execute(PlayerAction action) async =>
      const CommandResult(ActionStatus.noOp, 'No track');
}

void main() {
  testWidgets(
    'root player profile route opens and returns without another shell',
    (tester) async {
      GlassTheme.overrideQuality(GlassQuality.off);
      final profiles = await ProfileRepository.open(_Store());
      final dispatcher = PlayerActionDispatcher(
        playback: _Commands(),
        catalog: () => profiles.catalog,
      );
      final controls = ProfileControls(
        profiles: profiles,
        dispatcher: dispatcher,
      );
      getIt.registerSingleton<ProfileControls>(controls);
      final palette = TrackPaletteCubit();
      final route = appRouter.configuration.routes
          .whereType<GoRoute>()
          .singleWhere((route) => route.name == AppRoute.playerProfiles);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: AppButton.primary(
                'Open profiles',
                onPressed: () => context.pushNamed(AppRoute.playerProfiles),
              ),
            ),
          ),
          route,
        ],
      );
      try {
        await tester.pumpWidget(
          BlocProvider.value(
            value: palette,
            child: MaterialApp.router(
              theme: AppTheme.dark,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Open profiles'));
          await tester.pumpAndSettle();
          expect(find.byType(ProfilesPage), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(find.text('Add profile'), findsOneWidget);
          expect(find.text('Open combo pad'), findsNothing);
          router.pop();
          await tester.pumpAndSettle();
          expect(find.text('Open profiles'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await dispatcher.dispose();
        await profiles.dispose();
        await palette.close();
        getIt.unregister<ProfileControls>();
        GlassTheme.overrideQuality(null);
      }
    },
  );
}
