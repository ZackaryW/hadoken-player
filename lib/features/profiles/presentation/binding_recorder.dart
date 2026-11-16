import 'dart:async';
import 'package:flutter/material.dart';
import 'package:troona/shared/widgets/app_button.dart';
import '../../input_bindings/domain/combo_input.dart';
import '../../input_bindings/presentation/combo_widgets.dart';
import '../../player_actions/profile_controls.dart';
import '../domain/profile_catalog.dart';

class BindingRecorder extends StatefulWidget {
  final ProfileControls controls;
  final ProfileId profile;
  final PlayerAction? action;
  final String? macroLabel;
  final Future<void> Function(List<Stroke>)? saveMacro;
  const BindingRecorder({
    super.key,
    required this.controls,
    required this.profile,
    required this.action,
  }) : macroLabel = null,
       saveMacro = null;
  const BindingRecorder.macro({
    super.key,
    required this.controls,
    required this.profile,
    required String label,
    required Future<void> Function(List<Stroke>) onSave,
  }) : action = null,
       macroLabel = label,
       saveMacro = onSave;
  @override
  State<BindingRecorder> createState() => _BindingRecorderState();
}

class _BindingRecorderState extends State<BindingRecorder>
    with WidgetsBindingObserver {
  late final ComboInput input;
  StreamSubscription<ProfileCatalog>? subscription;
  String? feedback;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    input = widget.controls.createInput(
      mode: InputMode.recording,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    subscription = widget.controls.profiles.changes.listen(
      input.replaceCatalog,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) input.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(subscription?.cancel());
    input.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || input.strokes.isEmpty) return;
    setState(() => saving = true);
    try {
      final saveMacro = widget.saveMacro;
      if (saveMacro != null) {
        await saveMacro(input.strokes);
      } else {
        await widget.controls.profiles.setBinding(
          widget.profile,
          widget.action!,
          input.strokes,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          feedback = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onFocusChange: (focused) {
      if (!focused) input.cancel();
    },
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.profile.label} · ${widget.macroLabel ?? widget.action!.label}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('● Tap   ━ Hold'),
            const SizedBox(height: 16),
            ComboStrip(input.strokes),
            const SizedBox(height: 8),
            Text('${input.strokes.length} / 5 strokes'),
            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: saving,
              child: ComboButtons(
                input: input,
                timing: widget.controls.profiles.catalog.timing,
              ),
            ),
            if (input.feedback != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(input.feedback!),
              ),
            if (feedback != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(feedback!),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton.secondary(
                  'Undo',
                  onPressed: saving || input.strokes.isEmpty
                      ? null
                      : input.undo,
                ),
                AppButton.secondary(
                  'Clear draft',
                  onPressed: saving || input.strokes.isEmpty
                      ? null
                      : input.clearDraft,
                ),
                AppButton.text(
                  'Cancel',
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                ),
                AppButton.primary(
                  saving ? 'Saving…' : 'Save combo',
                  onPressed: saving || input.strokes.isEmpty ? null : save,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
