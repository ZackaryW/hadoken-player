import 'capabilities/capability.dart';

enum SkillTrigger {
  actionSucceeded,
  comboObserved,
  manualActivation,
  effectExpired,
}

enum SkillFailureCleanup { retainApplied, revokeInvocationEffects }

final class SkillBindingView {
  final String player;
  final SkillTarget target;
  final SkillCombo combo;
  const SkillBindingView(this.player, this.target, this.combo);
}

final class SkillQueueOccurrence {
  final String id;
  final SongReference song;
  const SkillQueueOccurrence(this.id, this.song);
}

final class SkillContext {
  final String sessionId;
  final String owner;
  final String? actor;
  final Duration elapsed;
  final int loop;
  final int queueRevision;
  final int bindingRevision;
  final Set<String> players;
  final Set<SkillCapability> support;
  final List<SkillBindingView> bindings;
  final List<SkillQueueOccurrence> queue;
  final List<SongReference> songs;
  SkillContext({
    required String sessionId,
    required String owner,
    this.actor,
    required this.elapsed,
    this.loop = 0,
    this.queueRevision = 0,
    this.bindingRevision = 0,
    Iterable<String> players = const [],
    Iterable<SkillCapability> support = const [],
    Iterable<SkillBindingView> bindings = const [],
    Iterable<SkillQueueOccurrence> queue = const [],
    Iterable<SongReference> songs = const [],
  }) : sessionId = requireIdentity(sessionId),
       owner = requireIdentity(owner),
       players = Set.unmodifiable(players.map(requireIdentity)),
       support = Set.unmodifiable(support),
       bindings = List.unmodifiable(bindings),
       queue = List.unmodifiable(queue),
       songs = List.unmodifiable(songs) {
    if (actor != null) requireIdentity(actor!);
    if (elapsed < Duration.zero ||
        loop < 0 ||
        queueRevision < 0 ||
        bindingRevision < 0) {
      throw ArgumentError('Invalid context time or revision.');
    }
  }
}

sealed class SkillRuntimeEvent {
  final String id;
  SkillRuntimeEvent(String id) : id = requireIdentity(id);
  SkillTrigger get trigger;
}

final class SkillComboObserved extends SkillRuntimeEvent {
  final String listenerKey;
  final SkillTarget target;
  final List<SkillStrokeObservation> observations;
  SkillComboObserved(
    super.id, {
    required this.listenerKey,
    required this.target,
    required Iterable<SkillStrokeObservation> observations,
  }) : observations = List.unmodifiable(observations) {
    SkillCombo(this.observations.map((o) => o.stroke));
  }
  @override
  SkillTrigger get trigger => SkillTrigger.comboObserved;
}

final class SkillManualActivation extends SkillRuntimeEvent {
  final List<SkillStrokeObservation> observations;
  SkillManualActivation(super.id, Iterable<SkillStrokeObservation> observations)
    : observations = List.unmodifiable(observations) {
    SkillCombo(this.observations.map((o) => o.stroke));
  }
  @override
  SkillTrigger get trigger => SkillTrigger.manualActivation;
}

final class SkillActionSucceeded extends SkillRuntimeEvent {
  final PlaybackSkillTarget target;
  SkillActionSucceeded(super.id, this.target);
  @override
  SkillTrigger get trigger => SkillTrigger.actionSucceeded;
}

final class SkillEffectExpired extends SkillRuntimeEvent {
  final EffectHandle handle;
  SkillEffectExpired(super.id, this.handle);
  @override
  SkillTrigger get trigger => SkillTrigger.effectExpired;
}

final class SkillReaction {
  static final none = SkillReaction();
  final List<CapabilityRequest> requests;
  final bool stateChanged;
  SkillReaction({
    Iterable<CapabilityRequest> requests = const [],
    this.stateChanged = false,
  }) : requests = List.unmodifiable(requests) {
    if (this.requests.length > 16 ||
        this.requests.map((r) => r.effectId).toSet().length !=
            this.requests.length) {
      throw ArgumentError('A reaction allows at most 16 distinct effects.');
    }
  }
}
