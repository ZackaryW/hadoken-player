import 'dart:async';
import 'package:flutter/material.dart';
import 'package:troona/core/layout/app_layout.dart';
import 'package:troona/core/theme/semantic/app_colors.dart';
import 'package:troona/shared/widgets/app_back_button.dart';
import 'package:troona/shared/widgets/app_button.dart';
import 'package:troona/shared/widgets/glass_bottom_sheet.dart';
import 'package:troona/shared/widgets/glass_sliver_header.dart';
import 'package:troona/skills/skill.dart';
import '../../input_bindings/presentation/combo_widgets.dart';
import '../../player_actions/profile_controls.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../../profiles/presentation/binding_recorder.dart';
import '../skill_controls.dart';

class SkillMacroPage extends StatefulWidget {
  final SkillControls controls;
  final ProfileId profile;
  final SkillDefinition definition;
  const SkillMacroPage({
    super.key,
    required this.controls,
    required this.profile,
    required this.definition,
  });
  @override
  State<SkillMacroPage> createState() => _SkillMacroPageState();
}

class _SkillMacroPageState extends State<SkillMacroPage> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  late final ProfileControls _recordingControls;
  String? _feedback;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _recordingControls = ProfileControls(
      profiles: widget.controls.profiles,
      dispatcher: widget.controls.dispatcher,
    );
    _subscriptions.add(
      widget.controls.profiles.changes.listen((_) {
        if (mounted) setState(() {});
      }),
    );
    _subscriptions.add(
      widget.controls.assignments.changes.listen((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _record() => showGlassBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BindingRecorder.macro(
      controls: _recordingControls,
      profile: widget.profile,
      label: widget.definition.label,
      onSave: (strokes) => widget.controls.setMacro(
        widget.profile,
        widget.definition.id,
        strokes,
      ),
    ),
  );
  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await widget.controls.setMacro(
        widget.profile,
        widget.definition.id,
        null,
      );
    } catch (error) {
      if (mounted) setState(() => _feedback = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final macro = widget.controls.profiles.catalog.macroFor(
      widget.profile,
      widget.definition.id.key,
    );
    final equipped = widget.controls.assignments.catalog.has(
      widget.profile,
      widget.definition.id,
    );
    return Scaffold(
      backgroundColor: context.colors.bgPrimary,
      body: CustomScrollView(
        slivers: [
          GlassSliverHeader.largeTitle(
            leading: AppBackButton(),
            title: 'Activation macro',
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              context.bottomBarInset(tabs: false),
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.profile.label} · ${widget.definition.label}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!equipped) const Text('Not equipped'),
                  if (macro != null)
                    ComboStrip(macro.strokes)
                  else
                    const Text('Not set'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppButton.secondary(
                        'Set',
                        key: const ValueKey('set-skill-macro'),
                        onPressed: !_busy && equipped ? _record : null,
                      ),
                      if (macro != null)
                        AppButton.text(
                          'Clear',
                          key: const ValueKey('clear-skill-macro'),
                          onPressed: !_busy ? _clear : null,
                        ),
                    ],
                  ),
                  if (_feedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_feedback!),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
