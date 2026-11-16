import 'dart:async';
import 'package:flutter/cupertino.dart';
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
    final status = !assigned
        ? 'Not assigned'
        : remaining == null
        ? 'Checking…'
        : remaining! > Duration.zero
        ? 'Ready in ${remainingSeconds(remaining!)}s'
        : 'Ready';
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
                  Container(
                    padding: const EdgeInsets.all(14),
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
                                SkillId.skipRecovery.label,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            AppIconButton(
                              icon: AppIcons.skillDetails,
                              tooltip: 'About Skip Recovery',
                              size: 20,
                              onPressed: () => showMessageDialog(
                                context,
                                title: SkillId.skipRecovery.label,
                                body: SkillId.skipRecovery.description,
                              ),
                            ),
                            Semantics(
                              label:
                                  'Assign Skip Recovery to ${selected.label}',
                              child: CupertinoSwitch(
                                key: const ValueKey('assign-skip-recovery'),
                                value: assigned,
                                activeTrackColor: context.colors.accent,
                                onChanged: busy ? null : assign,
                              ),
                            ),
                          ],
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            status,
                            key: const ValueKey('skill-status'),
                            style: TextStyle(
                              color: context.colors.labelSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
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
