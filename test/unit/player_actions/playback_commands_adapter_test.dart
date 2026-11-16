import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/core/error/failures.dart';
import 'package:troona/features/player/domain/entities/playback_state.dart';
import 'package:troona/features/player/domain/entities/queue.dart';
import 'package:troona/features/player/domain/entities/repeat_mode.dart';
import 'package:troona/features/player/domain/ports/audio_service_port.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import '../../helpers/fake_player.dart';

class CommandAudio extends Fake implements AudioServicePort {
  Queue? queue;
  PlaybackStatus status = PlaybackStatus.playing;
  Duration position = const Duration(seconds: 5);
  Duration duration = const Duration(seconds: 30);
  Duration? pauseFade;
  void Function()? onPause;
  bool move = true;
  bool fail = false;
  bool failResume = false;
  int skips = 0;
  @override
  Queue? get currentQueue => queue;
  @override
  get currentTrack => queue?.currentTrack;
  @override
  PlaybackStatus get currentStatus => status;
  @override
  Duration get currentPosition => position;
  @override
  Duration get currentDuration => duration;
  Future<Either<Failure, Unit>> get result async =>
      fail ? const Left(PlaybackFailure()) : const Right(unit);
  @override
  Future<Either<Failure, Unit>> pause({
    Duration fade = AudioServicePort.pauseFade,
  }) async {
    pauseFade = fade;
    onPause?.call();
    if (!fail) status = PlaybackStatus.paused;
    return result;
  }

  @override
  Future<Either<Failure, Unit>> resume() async {
    if (failResume) return const Left(PlaybackFailure());
    if (!fail) status = PlaybackStatus.playing;
    return result;
  }

  Future<Either<Failure, Unit>> skip(int direction) async {
    skips++;
    if (!fail && move) {
      queue = queue!.copyWith(
        currentIndex:
            (queue!.currentIndex + direction + queue!.length) % queue!.length,
      );
    }
    return result;
  }

  @override
  Future<Either<Failure, Unit>> skipToNext() => skip(1);
  @override
  Future<Either<Failure, Unit>> skipToPrevious() => skip(-1);
  @override
  Future<Either<Failure, Unit>> seekTo(Duration target) async {
    if (move && !fail) position = target;
    return result;
  }

  @override
  Future<void> stop() async {
    if (fail) throw StateError('Stop failed');
    if (move) status = PlaybackStatus.stopped;
  }
}

void main() {
  late CommandAudio audio;
  late PlaybackCommandsAdapter adapter;
  setUp(() {
    audio = CommandAudio()
      ..queue = Queue.fromTracks([
        testTrack('a', durationMs: 30000),
        testTrack('b', durationMs: 30000),
      ]);
    adapter = PlaybackCommandsAdapter(audio);
  });

  test(
    'toggle pauses immediately, resumes promptly, stop verifies effect',
    () async {
      expect(
        (await adapter.execute(PlayerAction.togglePlayback)).succeeded,
        isTrue,
      );
      expect(audio.pauseFade, Duration.zero);
      expect(audio.status, PlaybackStatus.paused);
      expect(
        (await adapter.execute(PlayerAction.togglePlayback)).succeeded,
        isTrue,
      );
      expect(audio.status, PlaybackStatus.playing);
      expect((await adapter.execute(PlayerAction.stop)).succeeded, isTrue);
      expect(
        (await adapter.execute(PlayerAction.stop)).status,
        ActionStatus.noOp,
      );
    },
  );

  test(
    'next and previous change one occurrence; boundaries are no-ops',
    () async {
      expect(
        (await adapter.execute(PlayerAction.previousTrack)).status,
        ActionStatus.noOp,
      );
      expect(audio.skips, 0);
      expect((await adapter.execute(PlayerAction.nextTrack)).succeeded, isTrue);
      expect(audio.queue!.currentIndex, 1);
      expect(audio.status, PlaybackStatus.playing);
      expect(
        (await adapter.execute(PlayerAction.nextTrack)).status,
        ActionStatus.noOp,
      );
      expect(
        (await adapter.execute(PlayerAction.previousTrack)).succeeded,
        isTrue,
      );
      expect(audio.queue!.currentIndex, 0);
    },
  );

  test(
    'repeated copies of the same track remain separate occurrences',
    () async {
      final track = testTrack('same', durationMs: 30000);
      audio.queue = Queue.fromTracks([track, track]);
      expect((await adapter.execute(PlayerAction.nextTrack)).succeeded, isTrue);
      expect(audio.queue!.currentIndex, 1);
    },
  );

  test(
    'native pause guards against automatic advancement being credited',
    () async {
      audio.onPause = () {
        audio.queue = audio.queue!.copyWith(currentIndex: 1);
      };
      final result = await adapter.execute(PlayerAction.nextTrack);
      expect(result.status, ActionStatus.noOp);
      expect(audio.skips, 0);
      expect(audio.queue!.currentIndex, 1);
      expect(audio.status, PlaybackStatus.playing);
    },
  );

  test(
    'successful return without a track change is not a successful skip',
    () async {
      audio.move = false;
      expect(
        (await adapter.execute(PlayerAction.nextTrack)).status,
        ActionStatus.noOp,
      );
      audio.fail = true;
      expect(
        (await adapter.execute(PlayerAction.nextTrack)).status,
        ActionStatus.failure,
      );
    },
  );

  test(
    'repeat-all wraps while retaining pause; repeat-one allows manual next',
    () async {
      audio.status = PlaybackStatus.paused;
      audio.queue = audio.queue!.copyWith(
        currentIndex: 1,
        repeatMode: RepeatMode.all,
      );
      expect((await adapter.execute(PlayerAction.nextTrack)).succeeded, isTrue);
      expect(audio.queue!.currentIndex, 0);
      expect(audio.status, PlaybackStatus.paused);
      audio.queue = audio.queue!.copyWith(repeatMode: RepeatMode.one);
      expect((await adapter.execute(PlayerAction.nextTrack)).succeeded, isTrue);
      expect(audio.queue!.currentIndex, 1);
    },
  );

  test(
    'ten-second seek clamps both ends and requires an observed effect',
    () async {
      expect(
        (await adapter.execute(PlayerAction.seekForward)).succeeded,
        isTrue,
      );
      expect(audio.position, const Duration(seconds: 15));
      audio.position = const Duration(seconds: 25);
      await adapter.execute(PlayerAction.seekForward);
      expect(audio.position, const Duration(seconds: 30));
      expect(
        (await adapter.execute(PlayerAction.seekForward)).status,
        ActionStatus.noOp,
      );
      audio.position = const Duration(seconds: 3);
      await adapter.execute(PlayerAction.seekBackward);
      expect(audio.position, Duration.zero);
      audio.move = false;
      expect(
        (await adapter.execute(PlayerAction.seekForward)).status,
        ActionStatus.noOp,
      );
    },
  );

  test('empty session and transport failures never claim success', () async {
    audio.fail = true;
    expect(
      (await adapter.execute(PlayerAction.seekForward)).status,
      ActionStatus.failure,
    );
    expect(
      (await adapter.execute(PlayerAction.stop)).status,
      ActionStatus.failure,
    );
    audio.queue = null;
    for (final action in PlayerAction.values) {
      expect((await adapter.execute(action)).status, ActionStatus.noOp);
    }
  });

  test(
    'a near-boundary no-op seek cannot pass as success through timing tolerance',
    () async {
      audio.position = const Duration(milliseconds: 29900);
      audio.move = false;
      expect(
        (await adapter.execute(PlayerAction.seekForward)).status,
        ActionStatus.noOp,
      );
      expect(audio.status, PlaybackStatus.playing);
    },
  );

  test(
    'actual skip remains attributable if restoring playback fails afterward',
    () async {
      audio.failResume = true;
      final outcome = await adapter.execute(PlayerAction.nextTrack);
      expect(audio.queue!.currentIndex, 1);
      expect(outcome.status, ActionStatus.success);
      expect(outcome.message, contains('Could not restore'));
    },
  );
}
