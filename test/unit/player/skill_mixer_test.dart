import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:troona/features/player/data/adapters/skill_mixer.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/loop_player.dart';

MixLayer song(
  String id, {
  double gain = 1,
  double pitch = 1,
  double speed = 1,
  Duration offset = Duration.zero,
}) => MixLayer(
  kind: MixLayerKind.song,
  song: SongReference(id),
  gain: gain,
  pitch: pitch,
  speed: speed,
  offset: offset,
);
StartAudioMix blend({
  List<MixLayer>? layers,
  MixSourceChange sourceChange = MixSourceChange.cancel,
}) => StartAudioMix(
  'mix',
  layers: layers ?? [song('a', gain: .5), song('b', gain: .25)],
  lifetime: const Duration(seconds: 10),
  sourceChange: sourceChange,
);
StartAudioMix noise() => StartAudioMix(
  'noise',
  layers: [MixLayer(kind: MixLayerKind.noise, gain: .2)],
  lifetime: const Duration(seconds: 10),
);

void main() {
  test('service timer expires a mix without a UI tick or command', () async {
    final primary = LoopPlayer();
    final layer = LoopPlayer();
    final clock = Stopwatch()..start();
    final mixer = SkillMixer(
      primary: primary,
      createPlayer: () => layer,
      sourceFor: (_) async => AudioSource.uri(Uri.parse('file:///noise.wav')),
      now: () async => clock.elapsed,
      sessionId: () => 's',
      sourceIdentity: () => 'a',
      currentSong: () => 'a',
      playIntent: () => true,
      supported: true,
    );
    final result = await mixer.start(
      StartAudioMix(
        'short',
        layers: [MixLayer(kind: MixLayerKind.noise)],
        lifetime: const Duration(milliseconds: 25),
      ),
      id: 'short',
      session: 's',
    );
    expect(result.status, CapabilityStatus.applied);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(layer.disposed, isTrue);
    expect(layer.playing, isFalse);
    await mixer.dispose();
    await primary.dispose();
  });
  late LoopPlayer primary;
  late SkillMixer mixer;
  late List<LoopPlayer> layers;
  var elapsed = Duration.zero;
  var identity = 'session:0:a';
  var intent = true;
  LoopPlayer Function()? factory;
  setUp(() {
    elapsed = Duration.zero;
    identity = 'session:0:a';
    intent = true;
    factory = null;
    primary = LoopPlayer()..playing = true;
    layers = [];
    mixer = SkillMixer(
      primary: primary,
      createPlayer: () {
        final p = factory?.call() ?? LoopPlayer();
        layers.add(p);
        return p;
      },
      sourceFor: (layer) async {
        if (layer.song?.libraryId == 'missing') throw StateError('unreadable');
        return AudioSource.uri(Uri.parse('file:///test.wav'));
      },
      now: () async => elapsed,
      sessionId: () => 'session',
      sourceIdentity: () => identity,
      currentSong: () => 'a',
      playIntent: () => intent,
      supported: true,
      scheduleTimers: false,
    );
  });
  tearDown(() async {
    for (final p in layers) {
      p.failDispose = false;
    }
    await mixer.dispose();
    await primary.dispose();
  });
  Future<CapabilityStatus> start(
    StartAudioMix request, {
    String id = 'one',
  }) async => (await mixer.start(request, id: id, session: 'session')).status;

  test(
    'reuses current source, applies offsets/transforms and rejects competition',
    () async {
      expect(
        await start(
          blend(
            layers: [
              song(
                'a',
                gain: .4,
                pitch: 1.5,
                speed: .8,
                offset: const Duration(seconds: 2),
              ),
              song('b', gain: .6, pitch: .8, speed: 1.5),
            ],
          ),
        ),
        CapabilityStatus.applied,
      );
      expect(layers.length, 1);
      expect(primary.pitch, 1.5);
      expect(primary.speed, .8);
      expect(primary.position, const Duration(seconds: 2));
      expect(layers.single.speed, 1.5);
      expect(layers.single.pitch, .8);
      expect(layers.single.playing, isTrue);
      expect(await start(noise()), CapabilityStatus.denied);
      await mixer.applyGain(.5);
      expect(primary.volume, .2);
      expect(layers.single.volume, .3);
      await mixer.applySpeed(1.2);
      expect(primary.speed, .8);
      await mixer.cancel('one');
      expect(primary.speed, 1.2);
      expect(primary.pitch, 1);
      expect(primary.volume, .5);
      expect(layers.single.disposed, isTrue);
    },
  );
  test('noise loops over primary; latest gain restored on cleanup', () async {
    expect(await start(noise()), CapabilityStatus.applied);
    expect(layers.single.mode, LoopMode.one);
    await mixer.applyGain(.3);
    expect(primary.volume, .3);
    expect(layers.single.volume, closeTo(.06, 1e-9));
    await mixer.cancel();
    expect(primary.volume, .3);
    expect(primary.playing, isTrue);
  });
  test(
    'independent blend mutes primary, continued layers retain identity',
    () async {
      expect(
        await start(blend(sourceChange: MixSourceChange.continueUntilDeadline)),
        CapabilityStatus.applied,
      );
      expect(layers.length, 2);
      expect(primary.volume, 0);
      identity = 'session:0:b';
      await mixer.sourceChanged();
      expect(mixer.activeId, 'one');
      elapsed = const Duration(seconds: 10);
      await mixer.synchronize();
      expect(mixer.ownedLayerCount, 0);
      expect(primary.volume, 1);
    },
  );
  test('pause/resume and expiry while paused cannot restart layers', () async {
    intent = false;
    await start(blend());
    expect(layers.single.playing, isFalse);
    intent = true;
    await mixer.synchronize();
    expect(layers.single.playing, isTrue);
    intent = false;
    await mixer.synchronize();
    expect(layers.single.playing, isFalse);
    elapsed = const Duration(seconds: 11);
    await mixer.synchronize();
    intent = true;
    await mixer.synchronize();
    expect(layers.single.disposed, isTrue);
    expect(layers.single.playing, isFalse);
  });
  test('duplicate occurrence change cancels source-bound mix', () async {
    await start(blend());
    identity = 'session:1:a';
    await mixer.sourceChanged();
    expect(mixer.activeId, isNull);
    expect(mixer.ownedLayerCount, 0);
  });
  test('failed second source disposes already prepared first source', () async {
    expect(
      await start(blend(layers: [song('b'), song('missing')])),
      CapabilityStatus.failed,
    );
    expect(layers.single.disposed, isTrue);
    expect(mixer.activeId, isNull);
    expect(primary.volume, 1);
    expect(primary.playing, isTrue);
    expect(await start(noise(), id: 'next'), CapabilityStatus.applied);
  });
  test(
    'bad native source and offset clean resources; unsupported bounds are truthful',
    () async {
      factory = () => LoopPlayer()..failNextLoad = true;
      expect(await start(noise()), CapabilityStatus.failed);
      expect(layers.single.disposed, isTrue);
      factory = null;
      expect(
        await start(
          blend(
            layers: [
              song('b', offset: const Duration(minutes: 2)),
              song('c'),
            ],
          ),
        ),
        CapabilityStatus.failed,
      );
      expect(
        await start(blend(layers: [song('a', pitch: 3), song('b')])),
        CapabilityStatus.unsupported,
      );
      expect(mixer.ownedLayerCount, 0);
    },
  );
  test(
    'failed disposal retains ownership, blocks new mix, retries without restarting',
    () async {
      await start(noise());
      layers.single.failDispose = true;
      await expectLater(mixer.cancel('one'), throwsStateError);
      expect(await start(noise(), id: 'two'), CapabilityStatus.denied);
      layers.single.failDispose = false;
      await mixer.cancel('one');
      expect(await start(noise(), id: 'two'), CapabilityStatus.applied);
      await mixer.cancel('one');
      expect(mixer.activeId, 'two');
    },
  );
  test(
    'cancel during asynchronous preparation waits for cleanup; stale handle is harmless',
    () async {
      final gate = Completer<void>();
      factory = () => LoopPlayer()..loadGate = gate;
      final pending = start(noise());
      await pumpEventQueue();
      final cancel = mixer.cancel('one');
      gate.complete();
      expect(await pending, CapabilityStatus.failed);
      await cancel;
      expect(layers.single.disposed, isTrue);
      expect(mixer.ownedLayerCount, 0);
      factory = null;
      await start(noise(), id: 'two');
      await mixer.cancel('one');
      expect(mixer.activeId, 'two');
    },
  );
}
