import 'package:flutter/material.dart';
import 'package:troona/core/layout/app_layout.dart';
import 'package:troona/core/theme/semantic/app_colors.dart';
import 'package:troona/shared/widgets/app_back_button.dart';
import 'package:troona/shared/widgets/app_button.dart';
import 'package:troona/shared/widgets/app_dialog.dart';
import 'package:troona/shared/widgets/glass_bottom_sheet.dart';
import 'package:troona/shared/widgets/glass_sliver_header.dart';
import '../../input_bindings/presentation/combo_widgets.dart';
import '../../player_actions/profile_controls.dart';
import '../domain/profile_catalog.dart';
import '../domain/profile_repository.dart';
import 'binding_recorder.dart';

class ProfilesPage extends StatefulWidget {
  final ProfileControls controls;
  final VoidCallback onOpenPad;
  const ProfilesPage({
    super.key,
    required this.controls,
    required this.onOpenPad,
  });
  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  ProfileId selected = ProfileId.p1;
  String? feedback;
  ProfileRepository get repository => widget.controls.profiles;

  Future<void> rename() async {
    final name = await showTextInputDialog(
      context,
      title: 'Name ${selected.label}',
      placeholder: 'Player name',
      confirmLabel: 'Save',
      initialValue: repository.catalog.names[selected]!,
    );
    if (name == null || !mounted) return;
    try {
      await repository.rename(selected, name);
    } catch (e) {
      if (mounted) setState(() => feedback = '$e');
    }
  }

  Future<void> record(PlayerAction action) => showGlassBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BindingRecorder(
      controls: widget.controls,
      profile: selected,
      action: action,
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<ProfileCatalog>(
    stream: repository.changes,
    initialData: repository.catalog,
    builder: (context, snapshot) {
      final catalog = snapshot.data!;
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            GlassSliverHeader.largeTitle(
              leading: AppBackButton(),
              title: 'Player profiles',
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                context.bottomBarInset(tabs: false),
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your combo identifies your player. Each complete combo has one owner.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in ProfileId.values)
                          id == selected
                              ? AppButton.primary(
                                  id.label,
                                  onPressed: () =>
                                      setState(() => selected = id),
                                )
                              : AppButton.secondary(
                                  id.label,
                                  onPressed: () =>
                                      setState(() => selected = id),
                                ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${selected.label} · ${catalog.names[selected]}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton.text('Rename player', onPressed: rename),
                    ),
                    if (feedback != null)
                      Text(
                        feedback!,
                        style: TextStyle(color: context.colors.accent),
                      ),
                    for (final message in catalog.recoveryMessages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(message),
                      ),
                    for (final action in PlayerAction.values)
                      _bindingCard(catalog, action),
                    const SizedBox(height: 16),
                    AppButton.primary(
                      'Open combo pad',
                      onPressed: widget.onOpenPad,
                      expanded: true,
                    ),
                    const SizedBox(height: 20),
                    TimingSettings(repository: repository),
                    const SizedBox(height: 24),
                    const Text(
                      'How to set a combo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose P1, P2 or P3, then Set beside an action. Tap or hold Forward, Pause and Backward in order. Save one to five strokes. ● means tap; ━ means hold. Recording and Practice never control the music.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A shorter shared prefix waits for the continuation window. Start the next press before the window ends; a hold can finish later. These buttons capture input only while this screen is active. Music continues in the background.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _bindingCard(ProfileCatalog catalog, PlayerAction action) {
    final binding = catalog.bindingFor(selected, action);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action.label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ComboStrip(binding?.strokes ?? []),
          if (binding != null && catalog.sharedPrefixes(binding).isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Shared prefix: the shorter combo waits for a continuation.',
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              AppButton.text(
                'Set',
                key: ValueKey('set-${action.name}'),
                onPressed: () => record(action),
              ),
              if (binding != null)
                AppButton.text(
                  'Clear',
                  key: ValueKey('clear-${action.name}'),
                  onPressed: () async {
                    try {
                      await repository.setBinding(selected, action, null);
                    } catch (e) {
                      if (mounted) setState(() => feedback = '$e');
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class TimingSettings extends StatefulWidget {
  final ProfileRepository repository;
  const TimingSettings({super.key, required this.repository});
  @override
  State<TimingSettings> createState() => _TimingSettingsState();
}

class _TimingSettingsState extends State<TimingSettings> {
  late final hold = TextEditingController(
    text: '${widget.repository.catalog.timing.holdMs}',
  );
  late final gap = TextEditingController(
    text: '${widget.repository.catalog.timing.gapMs}',
  );
  String? feedback;
  @override
  void dispose() {
    hold.dispose();
    gap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Shared timing',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const Text(
        'Applies to all three players. Timing is not part of combo ownership.',
      ),
      TextField(
        key: const ValueKey('hold-ms'),
        controller: hold,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Hold threshold (ms)'),
      ),
      TextField(
        key: const ValueKey('gap-ms'),
        controller: gap,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Continuation window (ms)',
        ),
      ),
      AppButton.secondary(
        'Save timing',
        onPressed: () async {
          try {
            final timing = RecognitionTiming(
              holdMs: int.parse(hold.text),
              gapMs: int.parse(gap.text),
            );
            await widget.repository.setTiming(timing);
            if (mounted) {
              setState(() => feedback = 'Timing saved for all players.');
            }
          } catch (_) {
            if (mounted) {
              setState(
                () => feedback =
                    'Enter positive whole milliseconds. If saving failed, try again.',
              );
            }
          }
        },
      ),
      if (feedback != null) Text(feedback!),
    ],
  );
}
