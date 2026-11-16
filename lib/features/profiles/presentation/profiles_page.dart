import 'package:flutter/material.dart';
import 'package:troona/core/layout/app_layout.dart';
import 'package:troona/core/theme/semantic/app_colors.dart';
import 'package:troona/core/theme/semantic/app_icons.dart';
import 'package:troona/shared/widgets/app_icon_button.dart';
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
  const ProfilesPage({super.key, required this.controls});
  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  ProfileId selected = ProfileId.p1;
  String? feedback;
  bool adding = false;
  ProfileRepository get repository => widget.controls.profiles;

  Future<void> addProfile() async {
    setState(() {
      adding = true;
      feedback = null;
    });
    try {
      final id = await repository.addProfile();
      if (mounted) setState(() => selected = id);
    } catch (_) {
      if (mounted) {
        setState(() => feedback = 'Could not add profile. Try again.');
      }
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in ProfileId.values.where(
                          catalog.names.containsKey,
                        ))
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
                        if (catalog.names.length < 3)
                          AppButton.secondary(
                            'Add profile',
                            onPressed: adding ? null : addProfile,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            catalog.names[selected]!,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        AppButton.text('Rename', onPressed: rename),
                      ],
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
    final sharedPrefix =
        binding != null && catalog.sharedPrefixes(binding).isNotEmpty;
    return Container(
      key: ValueKey('binding-${action.name}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  action.label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppButton.text(
                'Set',
                size: AppButtonSize.small,
                key: ValueKey('set-${action.name}'),
                onPressed: () => record(action),
              ),
              if (binding != null)
                AppButton.text(
                  'Clear',
                  size: AppButtonSize.small,
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
          if (binding != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Flexible(child: ComboStrip(binding.strokes)),
                  if (sharedPrefix)
                    AppIconButton(
                      key: ValueKey('prefix-${action.name}'),
                      icon: AppIcons.bindingTiming,
                      size: 18,
                      tooltip: 'Shared prefix details',
                      onPressed: () => showMessageDialog(
                        context,
                        title: 'Shared prefix',
                        body:
                            'The shorter combo waits up to ${catalog.timing.gapMs} ms for the next press.',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
