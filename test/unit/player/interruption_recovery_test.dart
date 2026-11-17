import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/core/error/failures.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player/domain/ports/audio_service_port.dart';
import 'package:troona/features/settings/domain/entities/app_settings.dart';
import 'package:troona/services/audio/audio_session_service.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';
import 'mix_session_test.dart' show Session;

class ControlledAudio extends LoopAudioAdapter {
  ControlledAudio(LoopPlayer player)
    : super(player: player, schedulePlanTimers: false);
  Completer<void>? pauseGate;
  bool failPause = false;
  int resumes = 0;
  @override
  Future<Either<Failure, Unit>> pause({
    Duration fade = AudioServicePort.pauseFade,
  }) async {
    if (failPause) return const Left(PlaybackFailure());
    final result = await super.pause(fade: fade);
    await pauseGate?.future;
    return result;
  }

  @override
  Future<Either<Failure, Unit>> resume() {
    resumes++;
    return super.resume();
  }
}

void main() {
  late LoopPlayer player;
  late ControlledAudio audio;
  late Session session;
  late AudioSessionService service;
  void event(
    bool begin, [
    AudioInterruptionType type = AudioInterruptionType.pause,
  ]) => session.interruptions.add(AudioInterruptionEvent(begin, type));
  setUp(() async {
    player = LoopPlayer();
    audio = ControlledAudio(player);
    session = Session();
    service = AudioSessionService(audio, const AppSettings(), session: session);
    await service.init();
    await audio.setQueue([testTrack('a', durationMs: 60000)]);
  });
  tearDown(() async {
    await service.dispose();
    await audio.dispose();
    await session.interruptions.close();
    await session.noisy.close();
  });

  for (final stopped in [false, true]) {
    test(
      'previously inactive playback stays inactive; stopped=$stopped',
      () async {
        if (stopped) {
          await audio.stop();
        } else {
          await audio.pause(fade: Duration.zero);
        }
        event(true);
        event(false);
        await pumpEventQueue();
        expect(player.playing, isFalse);
        expect(audio.resumes, 0);
      },
    );
  }
  test(
    'active music resumes once; duplicate and unmatched ends do nothing',
    () async {
      event(false);
      await pumpEventQueue();
      expect(audio.resumes, 0);
      event(true);
      event(true);
      await pumpEventQueue();
      expect(player.playing, isFalse);
      event(false);
      event(false);
      await pumpEventQueue();
      expect(player.playing, isTrue);
      expect(audio.resumes, 1);
    },
  );
  for (final cancel in ['pause', 'stop', 'route', 'replacement']) {
    test('$cancel cancels interruption resumption', () async {
      event(true);
      await pumpEventQueue();
      switch (cancel) {
        case 'pause':
          await audio.pause(fade: Duration.zero);
        case 'stop':
          await audio.stop();
        case 'route':
          session.noisy.add(null);
        case 'replacement':
          await audio.setQueue([testTrack('b', durationMs: 60000)]);
          await audio.pause(fade: Duration.zero);
      }
      await pumpEventQueue();
      event(false);
      await pumpEventQueue();
      expect(player.playing, isFalse);
      expect(audio.resumes, 0);
    });
  }
  test('rapid end waits for pause completion', () async {
    audio.pauseGate = Completer<void>();
    event(true);
    event(false);
    await pumpEventQueue();
    expect(audio.resumes, 0);
    audio.pauseGate!.complete();
    await pumpEventQueue();
    expect(audio.resumes, 1);
    expect(player.playing, isTrue);
  });
  test('route loss while pause is pending cancels resume', () async {
    audio.pauseGate = Completer<void>();
    event(true);
    event(false);
    await pumpEventQueue();
    session.noisy.add(null);
    audio.pauseGate!.complete();
    await pumpEventQueue();
    expect(audio.resumes, 0);
    expect(player.playing, isFalse);
  });
  test('failed pause never grants resume intent', () async {
    audio.failPause = true;
    event(true);
    event(false);
    await pumpEventQueue();
    expect(audio.resumes, 0);
  });
  test(
    'resume setting and unknown interruptions prevent automatic restart',
    () async {
      service.updateSettings(const AppSettings(resumeAfterCallEnabled: false));
      event(true);
      event(false);
      await pumpEventQueue();
      expect(audio.resumes, 0);
      expect(player.playing, isFalse);
      await audio.resume();
      audio.resumes = 0;
      service.updateSettings(const AppSettings());
      event(true, AudioInterruptionType.unknown);
      event(false, AudioInterruptionType.unknown);
      await pumpEventQueue();
      expect(audio.resumes, 0);
      expect(player.playing, isFalse);
    },
  );
  test('disabled call pause never grants resume intent', () async {
    service.updateSettings(const AppSettings(stopOnCallEnabled: false));
    event(true);
    event(false);
    await pumpEventQueue();
    expect(audio.resumes, 0);
    expect(player.playing, isTrue);
  });
}
