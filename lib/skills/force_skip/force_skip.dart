import '../skill.dart';

final class ForceSkip extends SkillDefinition {
  static const power = Effort.maximum;
  const ForceSkip();
  @override
  SkillId get id => SkillId.forceSkip;
  @override
  String get label => 'Force Skip';
  @override
  String get summary => 'Manual · next track ($power)';
  @override
  String get description => 'Skip to the next song ($power).';
  @override
  Effort get activationEffort => power;
  @override
  Set<SkillCapability> get requiredCapabilities => const {
    SkillCapability.playbackAction,
  };
  @override
  List<SkillListener> get listeners => [
    SkillListener('force-skip', SkillTrigger.manualActivation),
  ];
  @override
  SkillRuntime createRuntime() => _ForceSkipRuntime();
}

final class _ForceSkipRuntime extends SkillRuntime {
  @override
  SkillReaction onListener(
    String key,
    SkillRuntimeEvent event,
    SkillContext context,
  ) => event is SkillManualActivation
      ? SkillReaction(
          requests: [
            ExecutePlayerAction(
              '${event.id}:force-skip',
              player: context.owner,
              action: SkillAction.nextTrack,
              effort: ForceSkip.power,
            ),
          ],
        )
      : SkillReaction.none;
}
