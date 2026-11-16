import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:troona/core/theme/semantic/app_colors.dart';
import 'package:troona/core/theme/semantic/app_icons.dart';
import 'package:troona/shared/widgets/app_icon_button.dart';
import '../../player_actions/domain/action_dispatcher.dart';
import '../../player_actions/profile_controls.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../domain/combo_input.dart';
import 'combo_widgets.dart';

/// Uses the same restrained pill and icon vocabulary as the player utility dock.
class PlayerModeSwitch extends StatelessWidget {
  final bool combo;
  final ValueChanged<bool> onChanged;
  final VoidCallback onProfiles;
  const PlayerModeSwitch({
    super.key,
    required this.combo,
    required this.onChanged,
    required this.onProfiles,
  });

  static const height = 44.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: CupertinoSlidingSegmentedControl<bool>(
            groupValue: combo,
            backgroundColor: Colors.white.withValues(alpha: .06),
            thumbColor: Colors.white.withValues(alpha: .16),
            children: {
              for (final value in [false, true])
                value: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  child: Text(
                    value ? 'Combo' : 'Player',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: value == combo
                          ? Colors.white
                          : context.colors.labelSecondary,
                    ),
                  ),
                ),
            },
            onValueChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        AppIconButton(
          icon: AppIcons.profiles,
          tooltip: 'Player profiles and combos',
          onPressed: onProfiles,
          size: 22,
        ),
      ],
    ),
  );
}

/// Route-owned input only. The shared playback service outlives this widget.
class NowPlayingComboControls extends StatefulWidget {
  final ProfileControls controls;
  const NowPlayingComboControls({super.key, required this.controls});
  static const height = 160.0;
  @override
  State<NowPlayingComboControls> createState() =>
      NowPlayingComboControlsState();
}

class NowPlayingComboControlsState extends State<NowPlayingComboControls>
    with WidgetsBindingObserver {
  late final ComboInput input;
  StreamSubscription<ProfileCatalog>? catalogSubscription;
  StreamSubscription<PlayerActionOutcome>? outcomeSubscription;
  String? outcome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    input = widget.controls.createInput(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    catalogSubscription = widget.controls.profiles.changes.listen((catalog) {
      outcome = null;
      input.replaceCatalog(catalog);
    });
    outcomeSubscription = widget.controls.dispatcher.outcomes.listen((event) {
      if (mounted) {
        setState(
          () => outcome =
              '${event.request.profile.label} · ${event.result.message}',
        );
      }
    });
  }

  void cancelPendingInput() => input.cancel();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) input.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    unawaited(catalogSubscription?.cancel());
    unawaited(outcomeSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strokes = input.strokes.isNotEmpty
        ? input.strokes
        : input.lastMatch?.binding.strokes ?? <Stroke>[];
    final message = input.waitingForContinuation
        ? 'Waiting for a longer combo…'
        : outcome ??
              input.feedback ??
              (widget.controls.profiles.catalog.bindings.isEmpty
                  ? 'No combos set'
                  : 'Tap or hold');
    return Focus(
      autofocus: true,
      onFocusChange: (focused) {
        if (!focused) input.cancel();
      },
      child: SizedBox(
        height: NowPlayingComboControls.height,
        child: Column(
          children: [
            SizedBox(
              height: 28,
              child: Center(
                child: strokes.isEmpty
                    ? Text(
                        '● TAP   ━ HOLD',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: context.colors.labelSecondary,
                        ),
                      )
                    : Semantics(
                        label: strokes
                            .map(
                              (s) => '${buttonLabel(s.button)} ${s.kind.name}',
                            )
                            .join(', then '),
                        child: ExcludeSemantics(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < strokes.length; i++) ...[
                                if (i > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Text(
                                      '›',
                                      style: TextStyle(
                                        color: context.colors.labelTertiary,
                                      ),
                                    ),
                                  ),
                                Icon(
                                  buttonIcon(strokes[i].button),
                                  size: 18,
                                  color: Colors.white,
                                ),
                                Text(
                                  strokes[i].kind == StrokeKind.hold
                                      ? '━'
                                      : '●',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: context.colors.accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            SizedBox(
              height: 26,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.labelSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ComboButtons(
              input: input,
              timing: widget.controls.profiles.catalog.timing,
              playerStyle: true,
            ),
          ],
        ),
      ),
    );
  }
}
