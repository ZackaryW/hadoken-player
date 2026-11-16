import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/settings/domain/entities/app_settings.dart';
import 'package:troona/services/audio/audio_session_service.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';
import 'skill_mixer_test.dart' show noise;

class Session implements AudioSession {
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast(
    sync: true,
  );
  final noisy = StreamController<void>.broadcast(sync: true);
  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptions.stream;
  @override
  Stream<void> get becomingNoisyEventStream => noisy.stream;
  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'session duck, interruption and headphone events affect every layer',
    () async {
      final primary = LoopPlayer();
      final layer = LoopPlayer();
      final session = Session();
      final adapter = MixAudioAdapter(
        player: primary,
        layerFactory: () => layer,
        supportsAudioMix: true,
        scheduleMixTimers: false,
        schedulePlanTimers: false,
        noiseSource: () async => Uri.parse('file:///noise.wav'),
      );
      final service = AudioSessionService(
        adapter,
        const AppSettings(),
        session: session,
      );
      await service.init();
      await adapter.setQueue([testTrack('a', durationMs: 60000)]);
      await adapter.startAudioMix(
        noise(),
        id: 'effect',
        sessionId: adapter.currentLoop!.sessionId,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      session.interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      await pumpEventQueue();
      expect(primary.volume, .3);
      expect(layer.volume, closeTo(.06, .001));
      await adapter.setVolume(.4);
      session.interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      await pumpEventQueue();
      expect(primary.volume, .4);
      expect(layer.volume, closeTo(.08, .001));
      session.interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();
      expect(primary.playing, isFalse);
      expect(layer.playing, isFalse);
      session.interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();
      expect(primary.playing, isTrue);
      expect(layer.playing, isTrue);
      session.noisy.add(null);
      await pumpEventQueue();
      expect(primary.playing, isFalse);
      expect(layer.playing, isFalse);
      await service.dispose();
      await session.interruptions.close();
      await session.noisy.close();
      await adapter.dispose();
    },
  );
}
