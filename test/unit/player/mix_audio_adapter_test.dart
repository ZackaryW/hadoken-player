import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/loop_player.dart';
import '../../helpers/fake_player.dart';
import 'skill_mixer_test.dart' show blend, noise;

void main() {
  late MixAudioAdapter adapter;
  late LoopPlayer primary;
  late List<LoopPlayer> layers;
  var elapsed = Duration.zero;
  setUp(() async {
    primary = LoopPlayer();
    layers = [];
    elapsed = Duration.zero;
    adapter = MixAudioAdapter(
      player: primary,
      supportsAudioMix: true,
      schedulePlanTimers: false,
      scheduleMixTimers: false,
      noiseSource: () async => Uri.parse('file:///noise.wav'),
      layerFactory: () {
        final p = LoopPlayer();
        layers.add(p);
        return p;
      },
    )..elapsedNow = (() async => elapsed);
    await adapter.setQueue([
      testTrack('a', durationMs: 60000),
      testTrack('b', durationMs: 60000),
      testTrack('a', durationMs: 60000),
    ]);
    await adapter.pause(fade: Duration.zero);
  });
  tearDown(() => adapter.dispose());
  Future<CapabilityStatus> start({bool useNoise = false}) async =>
      (await adapter.startAudioMix(
        useNoise ? noise() : blend(),
        id: 'effect',
        sessionId: adapter.currentLoop!.sessionId,
      )).status;
  test(
    'transport, user volume, duck and expiry share playback intent',
    () async {
      expect(await start(useNoise: true), CapabilityStatus.applied);
      expect(layers.single.playing, isFalse);
      await adapter.resume();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await adapter.setVolume(.8);
      await adapter.setDuckGain(.3);
      expect(primary.volume, closeTo(.24, .001));
      expect(layers.single.volume, closeTo(.048, .001));
      await adapter.setVolume(.4);
      await adapter.setDuckGain(1);
      expect(primary.volume, .4);
      expect(layers.single.volume, closeTo(.08, .001));
      await adapter.pause(fade: Duration.zero);
      expect(layers.single.playing, isFalse);
      elapsed = const Duration(seconds: 11);
      await adapter.resume();
      expect(layers.single.disposed, isTrue);
      expect(layers.single.playing, isFalse);
    },
  );
  test(
    'native occurrence, skip, replacement and stop tear down layers',
    () async {
      await start();
      primary.advance(1);
      await pumpEventQueue();
      expect(layers.last.disposed, isTrue);
      await start(useNoise: true);
      await adapter.skipToNext();
      expect(layers.last.disposed, isTrue);
      await start(useNoise: true);
      await adapter.setQueue([testTrack('b', durationMs: 60000)]);
      expect(layers.last.disposed, isTrue);
      await start(useNoise: true);
      await adapter.stop();
      expect(layers.every((p) => p.disposed && !p.playing), isTrue);
    },
  );
  test(
    'capability rejects old session, unavailable song and unsupported backend',
    () async {
      final result = await adapter.startAudioMix(
        noise(),
        id: 'stale',
        sessionId: 'old',
      );
      expect(result.status, CapabilityStatus.denied);
      adapter.canReadSong = (_) async => false;
      expect(await start(), CapabilityStatus.failed);
      final unsupported = MixAudioAdapter(
        player: LoopPlayer(),
        supportsAudioMix: false,
      );
      expect(unsupported.supportsAudioMix, isFalse);
      expect(
        (await unsupported.startAudioMix(
          noise(),
          id: 'x',
          sessionId: 'x',
        )).status,
        CapabilityStatus.unsupported,
      );
      await unsupported.dispose();
    },
  );
}
