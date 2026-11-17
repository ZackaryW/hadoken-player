import 'capabilities/capability.dart';
import 'skill_context.dart';
import 'effort.dart';
import 'listener.dart';

export 'capabilities/capability.dart';
export 'skill_context.dart';
export 'effort.dart';
export 'listener.dart';

/// Stable persisted identities. Behavior and metadata belong to definitions.
final class SkillId {
  static const skipRecovery = SkillId._('skip-recovery');
  static const songCommitment = SkillId._('song-commitment');
  static const forceSkip = SkillId._('force-skip');
  static const values = [songCommitment, forceSkip];
  final String key;
  const SkillId._(this.key);
  SkillId(String key) : key = requireIdentity(key);
  @override
  bool operator ==(Object other) => other is SkillId && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

enum SkillAction {
  togglePlayback,
  nextTrack,
  previousTrack,
  seekForward,
  seekBackward,
  stop,
}

/// App-independent input: callers supply stable identities and elapsed time.
final class SkillEvent {
  final String requestId;
  final String playerId;
  final SkillAction action;
  final Duration elapsed;
  const SkillEvent({
    required this.requestId,
    required this.playerId,
    required this.action,
    required this.elapsed,
  });
}

abstract class SkillDefinition {
  const SkillDefinition();
  SkillId get id;
  String get label;
  String get summary;
  String get description;
  SkillRuntime createRuntime();
  Set<SkillTrigger> get triggers => const {SkillTrigger.actionSucceeded};
  Set<SkillCapability> get requiredCapabilities => const {};
  SkillFailureCleanup get failureCleanup => SkillFailureCleanup.retainApplied;
  Effort get activationEffort => Effort.normal;
  PlayerScope get decisionScope => PlayerScope.owner;
  List<SkillListener> get listeners => [
    for (final trigger in triggers)
      SkillListener(
        trigger.name,
        trigger,
        armedOnly: trigger == SkillTrigger.comboObserved,
        scope: trigger == SkillTrigger.comboObserved
            ? PlayerScope.all
            : PlayerScope.owner,
      ),
  ];

  bool supports(SkillTrigger trigger) =>
      listeners.any((l) => l.trigger == trigger);

  /// Read-only details; effort belongs beside the action it qualifies.
  String get details => supports(SkillTrigger.manualActivation)
      ? 'Activate ($activationEffort)\n\n$description'
      : description;
}

abstract class SkillRuntime {
  final state = SkillStateStore();
  Map<String, SkillListener>? _listeners;
  final _activeListeners = <String>{};

  void configureListeners(SkillDefinition definition) {
    if (_listeners != null) return;
    final declarations = definition.listeners;
    if (declarations.map((l) => l.key).toSet().length != declarations.length) {
      throw ArgumentError('Duplicate listener key.');
    }
    _listeners = {for (final listener in declarations) listener.key: listener};
    _activeListeners.addAll(
      declarations.where((l) => l.initiallyActive).map((l) => l.key),
    );
  }

  void setListenerActive(String key, bool active) {
    if (!(_listeners?.containsKey(key) ?? false)) {
      throw ArgumentError('Undeclared listener: $key');
    }
    active ? _activeListeners.add(key) : _activeListeners.remove(key);
  }

  List<SkillListener> matchingListeners(
    SkillRuntimeEvent event,
    SkillContext context,
  ) => [
    for (final listener in _listeners?.values ?? <SkillListener>[])
      if (_activeListeners.contains(listener.key) &&
          listener.matches(event, context))
        listener,
  ];

  void resetSessionState() {
    state.clear();
    _listeners = null;
    _activeListeners.clear();
  }

  SkillReaction onListener(
    String key,
    SkillRuntimeEvent event,
    SkillContext context,
  ) => onEvent(event, context);
  String? status(SkillContext context) => null;
  String? assignmentLock(SkillContext context) => null;

  String? denialFor(SkillEvent event) => null;

  /// Called only after a successful action. Returns whether state changed.
  bool recordSuccess(SkillEvent event) => false;
  Duration remaining(String playerId, Duration elapsed) => Duration.zero;

  SkillActionBlock? decide(
    SkillTarget target,
    SkillContext context,
    String requestId,
  ) {
    final reason = target is PlaybackSkillTarget
        ? denialFor(
            SkillEvent(
              requestId: requestId,
              playerId: context.actor ?? context.owner,
              action: target.action,
              elapsed: context.elapsed,
            ),
          )
        : null;
    return reason == null ? null : SkillActionBlock(reason);
  }

  SkillReaction onEvent(SkillRuntimeEvent event, SkillContext context) {
    if (event is SkillActionSucceeded) {
      return SkillReaction(
        stateChanged: recordSuccess(
          SkillEvent(
            requestId: event.id,
            playerId: context.actor ?? context.owner,
            action: event.target.action,
            elapsed: context.elapsed,
          ),
        ),
      );
    }
    return SkillReaction.none;
  }

  /// Results are notifications, never another reaction-producing input.
  void onCapabilityResult(CapabilityResult result, SkillContext context) {}
}

int remainingSeconds(Duration value) =>
    (value.inMicroseconds / Duration.microsecondsPerSecond).ceil();
