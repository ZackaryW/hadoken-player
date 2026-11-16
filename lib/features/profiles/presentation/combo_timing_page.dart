import 'package:flutter/material.dart';
import 'package:troona/core/layout/app_layout.dart';
import 'package:troona/shared/widgets/app_back_button.dart';
import 'package:troona/shared/widgets/app_button.dart';
import 'package:troona/shared/widgets/glass_sliver_header.dart';
import '../domain/profile_catalog.dart';
import '../domain/profile_repository.dart';

class ComboTimingPage extends StatelessWidget {
  final ProfileRepository repository;
  const ComboTimingPage({super.key, required this.repository});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: CustomScrollView(
      slivers: [
        GlassSliverHeader.largeTitle(
          leading: AppBackButton(),
          title: 'Combo timing',
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            context.bottomBarInset(tabs: false),
          ),
          sliver: SliverToBoxAdapter(
            child: TimingSettings(repository: repository),
          ),
        ),
      ],
    ),
  );
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
              setState(() => feedback = 'Saved');
            }
          } on FormatException {
            if (mounted) {
              setState(() => feedback = 'Enter positive whole milliseconds.');
            }
          } catch (_) {
            if (mounted) {
              setState(() => feedback = 'Could not save. Try again.');
            }
          }
        },
      ),
      if (feedback != null) Text(feedback!),
    ],
  );
}
