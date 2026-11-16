import '../skill.dart';

final class SongCommitment extends SkillDefinition {
  static const listeningThreshold = Duration(seconds: 20);
  static final blockEffort = Effort(90);
  static const protectedActions = {
    SkillAction.nextTrack,
    SkillAction.previousTrack,
    SkillAction.seekForward,
    SkillAction.seekBackward,
  };
  const SongCommitment();
  @override
  SkillId get id => SkillId.songCommitment;
  @override
  String get label => 'Song Commitment';
  @override
  String get summary => 'Global · after 20s listening';
  @override
  String get description =>
      'After 20s of listening, everyone must finish the song.\n'
      'Block next ($blockEffort), previous ($blockEffort), '
      'seek forward ($blockEffort), seek back ($blockEffort).';
  @override
  PlayerScope get decisionScope => PlayerScope.all;
  @override
  List<SkillListener> get listeners => [
    SkillListener(
      'song-listening',
      SkillTrigger.playbackObserved,
      scope: PlayerScope.all,
    ),
  ];
  @override
  SkillRuntime createRuntime() => _SongCommitmentRuntime();
}

final class _CommitmentState {
  final String? playId;
  final bool locked;
  const _CommitmentState(this.playId, this.locked);
}

final class _SongCommitmentRuntime extends SkillRuntime {
  static const _commitment = SkillStateKey<_CommitmentState>('commitment');
  _CommitmentState get current =>
      state.read(_commitment) ?? const _CommitmentState(null, false);
  String get lockedMessage =>
      'Song Commitment (${SongCommitment.blockEffort}) · finish this song';
  @override
  SkillReaction onListener(
    String key,
    SkillRuntimeEvent event,
    SkillContext context,
  ) {
    if (event is! SkillPlaybackObserved) return SkillReaction.none;
    final playback = event.playback;
    final before = current;
    final locked =
        playback.playId != null &&
        ((before.playId == playback.playId && before.locked) ||
            playback.listened >= SongCommitment.listeningThreshold);
    state.write(_commitment, _CommitmentState(playback.playId, locked));
    return SkillReaction(
      stateChanged: before.playId != playback.playId || before.locked != locked,
    );
  }

  @override
  SkillActionBlock? decide(
    SkillTarget target,
    SkillContext context,
    String requestId,
  ) =>
      current.locked &&
          target is PlaybackSkillTarget &&
          SongCommitment.protectedActions.contains(target.action)
      ? SkillActionBlock(lockedMessage, effort: SongCommitment.blockEffort)
      : null;
  @override
  String? assignmentLock(SkillContext context) =>
      current.locked ? lockedMessage : null;
  @override
  String status(SkillContext context) => current.locked
      ? 'Song locked'
      : current.playId == null
      ? 'Ready'
      : 'Listening';
}
