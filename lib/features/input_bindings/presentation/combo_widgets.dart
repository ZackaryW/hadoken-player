import 'package:flutter/material.dart';
import 'package:troona/core/theme/semantic/app_colors.dart';
import 'package:troona/core/theme/semantic/app_icons.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../domain/combo_input.dart';

String buttonLabel(InputButton button) => switch (button) {
  InputButton.forward => 'Forward',
  InputButton.pause => 'Pause',
  InputButton.backward => 'Backward',
};
IconData buttonIcon(InputButton button) => switch (button) {
  InputButton.forward => AppIcons.comboForward,
  InputButton.pause => AppIcons.comboPause,
  InputButton.backward => AppIcons.comboBackward,
};

class ComboStrip extends StatelessWidget {
  final List<Stroke> strokes;
  const ComboStrip(this.strokes, {super.key});
  @override
  Widget build(BuildContext context) {
    if (strokes.isEmpty) return const Text('No combo');
    return Semantics(
      label: strokes
          .map((s) => '${buttonLabel(s.button)} ${s.kind.name}')
          .join(', then '),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < strokes.length; i++) ...[
              if (i > 0) const Text('→'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.bgSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.colors.accent.withValues(alpha: .5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(buttonIcon(strokes[i].button), size: 20),
                    Text(
                      strokes[i].kind == StrokeKind.hold ? '━ Hold' : '● Tap',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Raw pointer events are required: gesture recognizers can consume the up
/// event or impose a different long-press threshold than our shared settings.
class ComboButtons extends StatelessWidget {
  final ComboInput input;
  final RecognitionTiming timing;
  final bool playerStyle;
  const ComboButtons({
    super.key,
    required this.input,
    required this.timing,
    this.playerStyle = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final button
          in playerStyle
              ? [InputButton.backward, InputButton.pause, InputButton.forward]
              : InputButton.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Semantics(
              label: '${buttonLabel(button)}: tap or hold',
              button: true,
              hint: 'Hold for ${timing.holdMs} milliseconds or longer.',
              onTap: () => input.semanticPress(button),
              onLongPress: () => input.semanticPress(button, hold: true),
              child: Listener(
                key: ValueKey('input-${button.name}'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => input.down(button, event.pointer),
                onPointerUp: (event) => input.up(event.pointer),
                onPointerCancel: (_) => input.cancel(),
                child: ExcludeSemantics(
                  child: playerStyle
                      ? _PlayerInputFace(
                          button: button,
                          pressed: input.pressedButton == button,
                          holding: input.holding,
                        )
                      : Container(
                          constraints: const BoxConstraints(minHeight: 104),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: input.pressedButton == button
                                ? context.colors.accent.withValues(alpha: .35)
                                : context.colors.bgSecondary,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: input.pressedButton == button
                                  ? context.colors.accent
                                  : context.colors.labelTertiary,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(buttonIcon(button), size: 28),
                              const SizedBox(height: 6),
                              Text(
                                buttonLabel(button),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (input.pressedButton == button)
                                Text(
                                  input.holding ? 'HOLD' : 'TAP',
                                  style: const TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _PlayerInputFace extends StatelessWidget {
  final InputButton button;
  final bool pressed;
  final bool holding;
  const _PlayerInputFace({
    required this.button,
    required this.pressed,
    required this.holding,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pressed
              ? context.colors.accent
              : Colors.white.withValues(alpha: .07),
          border: Border.all(
            color: pressed
                ? context.colors.accent
                : Colors.white.withValues(alpha: .20),
          ),
        ),
        child: Icon(
          buttonIcon(button),
          size: 28,
          color: pressed ? context.colors.accentForeground : Colors.white,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        buttonLabel(button),
        style: TextStyle(fontSize: 11, color: context.colors.labelSecondary),
      ),
      SizedBox(
        height: 18,
        child: Text(
          pressed ? (holding ? 'HOLD' : 'TAP') : '',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: context.colors.accent,
          ),
        ),
      ),
    ],
  );
}
