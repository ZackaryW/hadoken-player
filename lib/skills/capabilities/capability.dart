import '../skill.dart';

enum SkillCapability {
  queueEdit,
  audioMix,
  restriction,
  comboOverride,
  listener,
  playbackAction,
}

enum CapabilityStatus { applied, denied, noOp, unsupported, failed }

enum SkillStroke {
  forwardTap,
  forwardHold,
  pauseTap,
  pauseHold,
  backwardTap,
  backwardHold,
}

enum PlayerScope { owner, others, all, explicit }

String requireIdentity(String value) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, 'identity');
  return value;
}

Duration requireLifetime(Duration value) {
  if (value <= Duration.zero) throw ArgumentError.value(value, 'duration');
  return value;
}

final class SkillCombo {
  final List<SkillStroke> strokes;
  SkillCombo(Iterable<SkillStroke> strokes)
    : strokes = List.unmodifiable(strokes) {
    if (this.strokes.isEmpty || this.strokes.length > 5) {
      throw ArgumentError('A combo requires one to five strokes.');
    }
  }
  String get key => strokes.map((stroke) => stroke.name).join('.');
  @override
  bool operator ==(Object other) => other is SkillCombo && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

final class SkillStrokeObservation {
  final SkillStroke stroke;
  final Duration downAt;
  final Duration upAt;
  final Duration gapBefore;
  SkillStrokeObservation({
    required this.stroke,
    required this.downAt,
    required this.upAt,
    required this.gapBefore,
  }) {
    if (downAt < Duration.zero || upAt < downAt || gapBefore < Duration.zero) {
      throw ArgumentError('Invalid stroke timing.');
    }
  }
}

sealed class SkillTarget {
  const SkillTarget();
  String get key;
  @override
  bool operator ==(Object other) => other is SkillTarget && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

final class PlaybackSkillTarget extends SkillTarget {
  final SkillAction action;
  const PlaybackSkillTarget(this.action);
  @override
  String get key => 'playback:${action.name}';
}

final class ActivationSkillTarget extends SkillTarget {
  final String skillKey;
  ActivationSkillTarget(String skillKey) : skillKey = requireIdentity(skillKey);
  @override
  String get key => 'skill:$skillKey';
}

final class PlayerSelector {
  final PlayerScope scope;
  final Set<String> players;
  PlayerSelector(this.scope, [Iterable<String> players = const []])
    : players = Set.unmodifiable(players.map(requireIdentity)) {
    if ((scope == PlayerScope.explicit) != this.players.isNotEmpty) {
      throw ArgumentError('Only an explicit selector supplies player IDs.');
    }
  }
  Set<String> resolve(String owner, Iterable<String> added) {
    final available = added.toSet();
    return Set.unmodifiable(switch (scope) {
      PlayerScope.owner => available.intersection({owner}),
      PlayerScope.others => available.difference({owner}),
      PlayerScope.all => available,
      PlayerScope.explicit => available.intersection(players),
    });
  }
}

final class SkillOrigin {
  final String owner;
  final String skillKey;
  final String invocationId;
  final String sessionId;
  SkillOrigin({
    required String owner,
    required String skillKey,
    required String invocationId,
    required String sessionId,
  }) : owner = requireIdentity(owner),
       skillKey = requireIdentity(skillKey),
       invocationId = requireIdentity(invocationId),
       sessionId = requireIdentity(sessionId);
}

final class EffectHandle {
  final String id;
  final SkillOrigin origin;
  final Duration deadline;
  EffectHandle({
    required String id,
    required this.origin,
    required this.deadline,
  }) : id = requireIdentity(id) {
    if (deadline < Duration.zero) {
      throw ArgumentError.value(deadline, 'deadline');
    }
  }
}

final class SongReference {
  final String libraryId;
  SongReference(String libraryId) : libraryId = requireIdentity(libraryId);
  @override
  bool operator ==(Object other) =>
      other is SongReference && libraryId == other.libraryId;
  @override
  int get hashCode => libraryId.hashCode;
}

sealed class LoopSelector {
  const LoopSelector();
}

final class CurrentLoop extends LoopSelector {
  const CurrentLoop();
}

final class FutureLoop extends LoopSelector {
  final int ordinal;
  FutureLoop(this.ordinal) {
    if (ordinal < 1) throw ArgumentError.value(ordinal, 'ordinal');
  }
}

final class FutureLoopRange extends LoopSelector {
  final int first;
  final int? last;
  FutureLoopRange(this.first, [this.last]) {
    if (first < 1 || (last != null && last! < first)) {
      throw ArgumentError('Invalid future loop range.');
    }
  }
}

sealed class QueueOperation {
  const QueueOperation();
}

final class InsertSong extends QueueOperation {
  final SongReference song;
  final String occurrenceId;
  final String? beforeOccurrenceId;
  InsertSong(this.song, String occurrenceId, {String? beforeOccurrenceId})
    : occurrenceId = requireIdentity(occurrenceId),
      beforeOccurrenceId = beforeOccurrenceId == null
          ? null
          : requireIdentity(beforeOccurrenceId);
}

final class RemoveOccurrence extends QueueOperation {
  final String occurrenceId;
  RemoveOccurrence(String occurrenceId)
    : occurrenceId = requireIdentity(occurrenceId);
}

sealed class CapabilityRequest {
  final String effectId;
  CapabilityRequest(String effectId) : effectId = requireIdentity(effectId);
  SkillCapability? get capability;
}

final class EditLoopQueue extends CapabilityRequest {
  final LoopSelector loops;
  final int expectedRevision;
  final List<QueueOperation> operations;
  final Duration? lifetime;
  EditLoopQueue(
    super.effectId, {
    required this.loops,
    required this.expectedRevision,
    required Iterable<QueueOperation> operations,
    this.lifetime,
  }) : operations = List.unmodifiable(operations) {
    if (expectedRevision < 0 || this.operations.isEmpty) {
      throw ArgumentError('A queue edit requires a revision and operations.');
    }
    if (loops is! CurrentLoop && lifetime == null) {
      throw ArgumentError('A future plan requires a bounded lifetime.');
    }
    if (lifetime != null) requireLifetime(lifetime!);
  }
  @override
  SkillCapability get capability => SkillCapability.queueEdit;
}

enum MixLayerKind { song, noise }

final class MixLayer {
  final MixLayerKind kind;
  final SongReference? song;
  final Duration offset;
  final double gain;
  final double speed;
  final double pitch;
  MixLayer({
    required this.kind,
    this.song,
    this.offset = Duration.zero,
    this.gain = 1,
    this.speed = 1,
    this.pitch = 1,
  }) {
    if ((kind == MixLayerKind.song) != (song != null) ||
        offset < Duration.zero ||
        !gain.isFinite ||
        gain < 0 ||
        gain > 1 ||
        !speed.isFinite ||
        speed <= 0 ||
        !pitch.isFinite ||
        pitch <= 0) {
      throw ArgumentError('Invalid audio layer.');
    }
  }
}

enum MixSourceChange { cancel, continueUntilDeadline }

final class StartAudioMix extends CapabilityRequest {
  final List<MixLayer> layers;
  final Duration lifetime;
  final MixSourceChange sourceChange;
  StartAudioMix(
    super.effectId, {
    required Iterable<MixLayer> layers,
    required Duration lifetime,
    this.sourceChange = MixSourceChange.cancel,
  }) : layers = List.unmodifiable(layers),
       lifetime = requireLifetime(lifetime) {
    final noise =
        this.layers.length == 1 &&
        this.layers.single.kind == MixLayerKind.noise;
    final songs =
        this.layers.length == 2 &&
        this.layers.every((l) => l.kind == MixLayerKind.song);
    if (!noise && !songs) {
      throw ArgumentError('Use one noise layer or two songs.');
    }
  }
  @override
  SkillCapability get capability => SkillCapability.audioMix;
}

final class RestrictActions extends CapabilityRequest {
  final PlayerSelector players;
  final Set<SkillTarget> actions;
  final Duration lifetime;
  final Effort effort;
  RestrictActions(
    super.effectId, {
    required this.players,
    required Iterable<SkillTarget> actions,
    required Duration lifetime,
    this.effort = Effort.normal,
  }) : actions = Set.unmodifiable(actions),
       lifetime = requireLifetime(lifetime) {
    if (this.actions.isEmpty) {
      throw ArgumentError('Select an action to restrict.');
    }
  }
  @override
  SkillCapability get capability => SkillCapability.restriction;
}

final class ComboReplacement {
  final String player;
  final SkillAction action;
  final SkillCombo combo;
  ComboReplacement(String player, this.action, this.combo)
    : player = requireIdentity(player);
  String get targetKey => '$player:${action.name}';
}

final class OverrideCombos extends CapabilityRequest {
  final List<ComboReplacement> replacements;
  final Duration lifetime;
  OverrideCombos(
    super.effectId, {
    required Iterable<ComboReplacement> replacements,
    required Duration lifetime,
  }) : replacements = List.unmodifiable(replacements),
       lifetime = requireLifetime(lifetime) {
    if (this.replacements.isEmpty ||
        this.replacements.map((r) => r.targetKey).toSet().length !=
            this.replacements.length) {
      throw ArgumentError('Provide distinct replacement targets.');
    }
  }
  @override
  SkillCapability get capability => SkillCapability.comboOverride;
}

final class ArmComboListener extends CapabilityRequest {
  final String listenerKey;
  final SkillCombo combo;
  final PlayerSelector players;
  final Duration lifetime;
  final bool once;
  ArmComboListener(
    super.effectId, {
    required String listenerKey,
    required this.combo,
    required this.players,
    required Duration lifetime,
    this.once = false,
  }) : listenerKey = requireIdentity(listenerKey),
       lifetime = requireLifetime(lifetime);
  @override
  SkillCapability get capability => SkillCapability.listener;
}

final class RevokeSkillEffect extends CapabilityRequest {
  final String handleId;
  RevokeSkillEffect(super.effectId, String handleId)
    : handleId = requireIdentity(handleId);
  @override
  SkillCapability? get capability => null;
}

final class ExecutePlayerAction extends CapabilityRequest {
  final String player;
  final SkillAction action;
  final Effort effort;
  ExecutePlayerAction(
    super.effectId, {
    required String player,
    required this.action,
    this.effort = Effort.normal,
  }) : player = requireIdentity(player);
  @override
  SkillCapability get capability => SkillCapability.playbackAction;
}

final class CapabilityResult {
  final String effectId;
  final CapabilityStatus status;
  final String reason;
  final int? appliedRevision;
  final EffectHandle? handle;
  final List<SongReference> songs;
  CapabilityResult({
    required String effectId,
    required this.status,
    this.reason = '',
    this.appliedRevision,
    this.handle,
    Iterable<SongReference> songs = const [],
  }) : effectId = requireIdentity(effectId),
       songs = List.unmodifiable(songs) {
    if (this.songs.length > 200 ||
        (status != CapabilityStatus.applied && this.songs.isNotEmpty)) {
      throw ArgumentError(
        'Only applied catalog queries return up to 200 songs.',
      );
    }
    if (appliedRevision != null && appliedRevision! < 0) {
      throw ArgumentError('Invalid revision.');
    }
    if (status != CapabilityStatus.applied &&
        (handle != null || appliedRevision != null)) {
      throw ArgumentError('Only an applied effect has a handle or revision.');
    }
  }
}

final class FindSongs extends CapabilityRequest {
  final String query;
  final int limit;
  FindSongs(super.effectId, {this.query = '', this.limit = 50}) {
    if (query.length > 200 || limit < 1 || limit > 200) {
      throw ArgumentError('Invalid song query bounds.');
    }
  }
  @override
  SkillCapability get capability => SkillCapability.queueEdit;
}
