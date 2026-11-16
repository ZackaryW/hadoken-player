import 'dart:async';
import 'package:flutter/material.dart';
import 'package:troona/core/layout/app_layout.dart';
import 'package:troona/shared/widgets/app_back_button.dart';
import 'package:troona/shared/widgets/app_button.dart';
import 'package:troona/shared/widgets/glass_sliver_header.dart';
import '../../player_actions/domain/action_dispatcher.dart';
import '../../player_actions/profile_controls.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../domain/combo_input.dart';
import 'combo_widgets.dart';

class ComboPadPage extends StatefulWidget {
  final ProfileControls controls;
  const ComboPadPage({super.key, required this.controls});
  @override
  State<ComboPadPage> createState() => _ComboPadPageState();
}

class _ComboPadPageState extends State<ComboPadPage>
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
      onPracticeMatch: (match) => setState(
        () => outcome =
            'Practice · ${match.binding.profile.label}: ${match.binding.label}.',
      ),
    );
    catalogSubscription = widget.controls.changes.listen(input.replaceCatalog);
    outcomeSubscription = widget.controls.dispatcher.outcomes.listen((event) {
      if (mounted) {
        setState(
          () => outcome =
              '${event.request.profile.label} · ${event.result.status.name}: ${event.result.message}',
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) input.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(catalogSubscription?.cancel());
    unawaited(outcomeSubscription?.cancel());
    input.dispose();
    super.dispose();
  }

  void mode(InputMode value) {
    input.setMode(value);
    setState(() => outcome = null);
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onFocusChange: (focused) {
      if (!focused) input.cancel();
    },
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          GlassSliverHeader.largeTitle(
            leading: AppBackButton(),
            title: 'Combo pad',
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
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      input.mode == InputMode.runtime
                          ? AppButton.primary(
                              'Play mode',
                              onPressed: () => mode(InputMode.runtime),
                            )
                          : AppButton.secondary(
                              'Play mode',
                              onPressed: () => mode(InputMode.runtime),
                            ),
                      input.mode == InputMode.practice
                          ? AppButton.primary(
                              'Practice',
                              onPressed: () => mode(InputMode.practice),
                            )
                          : AppButton.secondary(
                              'Practice',
                              onPressed: () => mode(InputMode.practice),
                            ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    input.mode == InputMode.practice ? 'Practice only' : 'Live',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  ComboStrip(input.strokes),
                  const SizedBox(height: 20),
                  ComboButtons(
                    input: input,
                    timing: widget.controls.profiles.catalog.timing,
                  ),
                  const SizedBox(height: 16),
                  if (input.waitingForContinuation)
                    const Text('Waiting for a longer combo…'),
                  if (input.feedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(input.feedback!),
                    ),
                  if (outcome != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(liveRegion: true, child: Text(outcome!)),
                    ),
                  AppButton.text(
                    'Cancel current combo',
                    onPressed: input.cancel,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '● Tap   ━ Hold   → Next stroke',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (widget.controls.profiles.catalog.bindings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('No combos set'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
