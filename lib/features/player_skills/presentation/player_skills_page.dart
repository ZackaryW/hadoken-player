import 'dart:async';
import 'package:flutter/material.dart';
import 'package:troona/core/layout/app_layout.dart';
import 'package:troona/core/theme/semantic/app_colors.dart';
import 'package:troona/core/theme/semantic/app_icons.dart';
import 'package:troona/shared/widgets/app_back_button.dart';
import 'package:troona/shared/widgets/app_button.dart';
import 'package:troona/shared/widgets/app_dialog.dart';
import 'package:troona/shared/widgets/app_icon_button.dart';
import 'package:troona/shared/widgets/glass_sliver_header.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../domain/skill_catalog.dart';
import '../domain/skill_assignments.dart';
import '../domain/skill_policy.dart';
import '../skill_controls.dart';

class PlayerSkillsPage extends StatefulWidget {
  final SkillControls controls;
  const PlayerSkillsPage({super.key, required this.controls});
  @override
  State<PlayerSkillsPage> createState() => _PlayerSkillsPageState();
}

class _PlayerSkillsPageState extends State<PlayerSkillsPage>
    with WidgetsBindingObserver {
  ProfileId selected = ProfileId.p1;
  Duration? remaining;
  String? feedback;
  bool busy = false;
  int revision = 0;
  Timer? timer;
  final subscriptions = <StreamSubscription<dynamic>>[];
  SkillControls get controls => widget.controls;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscriptions.add(controls.assignments.changes.listen((_) => refresh()));
    subscriptions.add(controls.policy.changes.listen((_) => refresh()));
    subscriptions.add(controls.profiles.changes.listen((_) => refresh()));
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final version = ++revision;
    final profile = selected;
    try {
      final left = await controls.policy.remaining(profile);
      if (!mounted || version != revision) return;
      setState(() {
        remaining = left;
        if (feedback?.contains('Skip Recovery ·') ?? false) {
          feedback = left > Duration.zero
              ? SkillCooldown(selected, left).toString()
              : null;
        }
      });
    } catch (_) {
      if (!mounted || version != revision) return;
      setState(() {
        remaining = null;
        feedback = 'Recovery status unavailable.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
      timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> assign(bool enabled) async {
    final profile = selected;
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      await controls.setAssigned(profile, SkillId.skipRecovery, enabled);
    } on SkillAlreadyAssigned catch (error) {
      if (mounted) setState(() => feedback = error.toString());
    } on SkillCooldown catch (error) {
      if (mounted) setState(() => feedback = error.toString());
    } catch (_) {
      if (mounted) {
        setState(() => feedback = 'Could not save skill. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assigned = controls.assignments.catalog.has(
      selected,
      SkillId.skipRecovery,
    );
    final owner = controls.assignments.catalog.ownerOf(SkillId.skipRecovery);
    final ownedByAnother = owner != null && owner != selected;
    final status = ownedByAnother
        ? 'Owned by ${owner.label}'
        : !assigned
        ? 'Inactive'
        : remaining == null
        ? 'Checking…'
        : remaining! > Duration.zero
        ? 'Ready in ${remainingSeconds(remaining!)}s'
        : 'Active';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          GlassSliverHeader.largeTitle(
            leading: AppBackButton(),
            title: 'Player skills',
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
                      for (final id in controls.profiles.catalog.names.keys)
                        id == selected
                            ? AppButton.primary(id.label, onPressed: () {})
                            : AppButton.secondary(
                                id.label,
                                onPressed: () {
                                  setState(() {
                                    selected = id;
                                    remaining = null;
                                    feedback = null;
                                  });
                                  unawaited(refresh());
                                },
                              ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final scale =
                          MediaQuery.textScalerOf(context).scale(17) / 17;
                      final columns =
                          ((constraints.maxWidth + 12) / (160 * scale + 12))
                              .floor()
                              .clamp(1, 3);
                      return GridView.count(
                        key: const ValueKey('skill-grid'),
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _SkillTile(
                            assigned: assigned,
                            status: status,
                            onTap: busy || ownedByAnother
                                ? null
                                : () => assign(!assigned),
                            onDetails: () => showMessageDialog(
                              context,
                              title: SkillId.skipRecovery.label,
                              body: SkillId.skipRecovery.description,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (feedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(feedback!),
                      ),
                    ),
                  for (final message
                      in controls.assignments.catalog.recoveryMessages)
                    Text(message),
                  for (final id in controls.assignments.catalog.unavailable(
                    selected,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Unavailable skill: $id'),
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

class _SkillTile extends StatelessWidget {
  final bool assigned;
  final String status;
  final VoidCallback? onTap;
  final VoidCallback onDetails;
  const _SkillTile({
    required this.assigned,
    required this.status,
    required this.onTap,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = assigned ? colors.accent : colors.labelSecondary;
    final radius = BorderRadius.circular(20);
    return AnimatedContainer(
      key: const ValueKey('skill-tile-surface'),
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: assigned
            ? colors.accent.withValues(alpha: .14)
            : colors.bgSecondary,
        border: Border.all(
          color: assigned
              ? colors.accent.withValues(alpha: .7)
              : colors.separatorOpaque,
        ),
        boxShadow: assigned
            ? [
                BoxShadow(
                  color: colors.accent.withValues(alpha: .12),
                  blurRadius: 16,
                ),
              ]
            : [],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: SkillId.skipRecovery.label,
              value: status,
              toggled: assigned,
              enabled: onTap != null,
              button: true,
              onTap: onTap,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('assign-skip-recovery'),
                  borderRadius: radius,
                  onTap: onTap,
                  excludeFromSemantics: true,
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            AppIcons.skipRecovery,
                            size: 32,
                            color: foreground,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            SkillId.skipRecovery.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: assigned
                                  ? colors.labelPrimary
                                  : colors.labelSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            status,
                            key: const ValueKey('skill-status'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              color: foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: AppIconButton(
              icon: AppIcons.skillDetails,
              tooltip: 'About Skip Recovery',
              size: 18,
              onPressed: onDetails,
            ),
          ),
        ],
      ),
    );
  }
}
