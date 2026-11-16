import 'package:dartz/dartz.dart';
import 'package:troona/core/error/failures.dart';
import '../../player/domain/entities/playback_state.dart';
import '../../player/domain/entities/queue.dart';
import '../../player/domain/entities/repeat_mode.dart';
import '../../player/domain/ports/audio_service_port.dart';
import '../../profiles/domain/profile_catalog.dart';
import '../domain/action_dispatcher.dart';

/// Uses the existing singleton. No ownership of its lifetime or system controls.
final class PlaybackCommandsAdapter implements PlaybackCommands {
  final AudioServicePort audio;
  const PlaybackCommandsAdapter(this.audio);

  static const _noTrack = CommandResult(
    ActionStatus.noOp,
    'Choose a track first.',
  );
  static const _failed = CommandResult(
    ActionStatus.failure,
    'Playback could not complete the action.',
  );
  static const _unchanged = CommandResult(
    ActionStatus.noOp,
    'Playback did not change.',
  );

  @override
  Future<CommandResult> execute(PlayerAction action) async {
    try {
      if (audio.currentTrack == null) return _noTrack;
      return switch (action) {
        PlayerAction.togglePlayback => await _toggle(),
        PlayerAction.nextTrack => await _skip(1),
        PlayerAction.previousTrack => await _skip(-1),
        PlayerAction.seekForward => await _seek(10),
        PlayerAction.seekBackward => await _seek(-10),
        PlayerAction.stop => await _stop(),
      };
    } catch (_) {
      return _failed;
    }
  }

  Future<CommandResult> _toggle() async {
    final playing = audio.currentStatus == PlaybackStatus.playing;
    final result = playing
        ? await audio.pause(fade: Duration.zero)
        : await audio.resume();
    if (result.isLeft()) return _failed;
    final changed = playing
        ? audio.currentStatus == PlaybackStatus.paused
        : audio.currentStatus == PlaybackStatus.playing;
    return changed
        ? CommandResult(ActionStatus.success, playing ? 'Paused.' : 'Playing.')
        : _unchanged;
  }

  Future<CommandResult> _skip(int direction) async {
    final before = audio.currentQueue;
    if (before == null || before.length < 2) return _unchanged;
    var target = before.currentIndex + direction;
    if (target < 0 || target >= before.length) {
      if (before.repeatMode != RepeatMode.all) return _unchanged;
      target = (target + before.length) % before.length;
    }
    final wasPlaying = audio.currentStatus == PlaybackStatus.playing;
    if (audio.currentStatus == PlaybackStatus.buffering) return _unchanged;

    // Quiesce the native player before attributing a transition. A before/after
    // comparison alone can falsely credit auto-advance during an awaited skip.
    // Normal app/notification skips keep Troona's conventional fade behavior.
    if (wasPlaying && (await audio.pause(fade: Duration.zero)).isLeft()) {
      return _failed;
    }
    var outcome = _unchanged;
    try {
      if (audio.currentStatus == PlaybackStatus.playing ||
          !sameOccurrence(before, audio.currentQueue)) {
        outcome = const CommandResult(
          ActionStatus.noOp,
          'The queue advanced or changed before the combo skip.',
        );
      } else {
        final Either<Failure, Unit> result = direction > 0
            ? await audio.skipToNext()
            : await audio.skipToPrevious();
        final after = audio.currentQueue;
        if (result.isLeft()) {
          outcome = _failed;
        } else if (sameOrder(before, after) && after!.currentIndex == target) {
          outcome = CommandResult(
            ActionStatus.success,
            direction > 0
                ? 'Skipped to next track.'
                : 'Moved to previous track.',
          );
        }
      }
    } catch (_) {
      outcome = _failed;
    } finally {
      outcome = await _restorePlayback(wasPlaying, outcome);
    }
    return outcome;
  }

  Future<CommandResult> _restorePlayback(
    bool wasPlaying,
    CommandResult outcome,
  ) async {
    // Keep a pre-existing pause, including Troona's repeat-all path, which
    // ordinarily resumes while wrapping around a queue boundary.
    try {
      if (wasPlaying) {
        final resumed = await audio.resume();
        if (resumed.isLeft()) throw StateError('Could not restore playback');
      } else if (audio.currentStatus == PlaybackStatus.playing) {
        final paused = await audio.pause(fade: Duration.zero);
        if (paused.isLeft()) throw StateError('Could not retain pause');
      }
    } catch (_) {
      // The queue transition is still a success for skill accounting even
      // when a separate attempt to restore play/pause subsequently fails.
      outcome = outcome.succeeded
          ? CommandResult(
              ActionStatus.success,
              '${outcome.message} Could not restore play/pause state.',
            )
          : _failed;
    }
    return outcome;
  }

  static bool sameOrder(Queue a, Queue? b) {
    if (b == null || a.length != b.length) return false;
    // Occurrences are indices, including repeated copies of the same track.
    // Queue replacements/order edits also invalidate the comparison.
    for (var i = 0; i < a.length; i++) {
      if (!identical(a.playbackTracks[i], b.playbackTracks[i])) return false;
    }
    return a.repeatMode == b.repeatMode && a.shuffleEnabled == b.shuffleEnabled;
  }

  static bool sameOccurrence(Queue a, Queue? b) =>
      sameOrder(a, b) && a.currentIndex == b!.currentIndex;

  Future<CommandResult> _seek(int seconds) async {
    final before = audio.currentQueue;
    final duration = audio.currentDuration.inMilliseconds;
    if (before == null || duration <= 0) return _unchanged;
    final wasPlaying = audio.currentStatus == PlaybackStatus.playing;
    if (audio.currentStatus == PlaybackStatus.buffering) return _unchanged;
    if (wasPlaying && (await audio.pause(fade: Duration.zero)).isLeft()) {
      return _failed;
    }
    var outcome = _unchanged;
    try {
      if (audio.currentStatus != PlaybackStatus.playing &&
          sameOccurrence(before, audio.currentQueue)) {
        final position = audio.currentPosition.inMilliseconds;
        final target = (position + seconds * 1000).clamp(0, duration);
        if (target != position) {
          final result = await audio.seekTo(Duration(milliseconds: target));
          if (result.isLeft()) {
            outcome = _failed;
          } else if (sameOccurrence(before, audio.currentQueue) &&
              audio.currentPosition.inMilliseconds == target) {
            outcome = const CommandResult(
              ActionStatus.success,
              'Position changed.',
            );
          }
        }
      }
    } catch (_) {
      outcome = _failed;
    } finally {
      outcome = await _restorePlayback(wasPlaying, outcome);
    }
    return outcome;
  }

  Future<CommandResult> _stop() async {
    if (audio.currentStatus == PlaybackStatus.stopped) return _unchanged;
    await audio.stop();
    return audio.currentStatus == PlaybackStatus.stopped
        ? const CommandResult(ActionStatus.success, 'Stopped.')
        : _unchanged;
  }
}
