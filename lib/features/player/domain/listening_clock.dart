import 'package:troona/skills/skill.dart';

/// Accumulates wall-clock playing intervals, never media-position deltas.
final class ListeningClock {
  String? _playId;
  Duration? _sampledAt;
  Duration _listened = Duration.zero;
  bool _playing = false;

  SkillPlaybackSnapshot sample({
    required String? playId,
    required bool playing,
    required Duration elapsed,
  }) {
    final previous = _sampledAt;
    if (previous != null && elapsed < previous) {
      throw ArgumentError('Listening clock must be monotonic.');
    }
    if (playId != _playId) {
      _playId = playId;
      _listened = Duration.zero;
    } else if (playId != null && _playing && previous != null) {
      _listened += elapsed - previous;
    }
    _sampledAt = elapsed;
    _playing = playing && playId != null;
    return SkillPlaybackSnapshot(
      playId: _playId,
      listened: _listened,
      playing: _playing,
    );
  }
}
