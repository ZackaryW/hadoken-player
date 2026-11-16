/// Stable persisted identities. Behavior and metadata belong to definitions.
enum SkillId {
  skipRecovery('skip-recovery');

  final String key;
  const SkillId(this.key);
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

abstract interface class SkillDefinition {
  SkillId get id;
  String get label;
  String get summary;
  String get description;
  SkillRuntime createRuntime();
}

abstract interface class SkillRuntime {
  String? denialFor(SkillEvent event);

  /// Called only after a successful action. Returns whether state changed.
  bool recordSuccess(SkillEvent event);
  Duration remaining(String playerId, Duration elapsed);
}

int remainingSeconds(Duration value) =>
    (value.inMicroseconds / Duration.microsecondsPerSecond).ceil();
