// Device-only acceptance of the production adapters; no saved user state.
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:troona/features/library/domain/entities/track.dart';
import 'package:troona/features/player/data/adapters/audio_handler_impl.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player_skills/data/android_skill_clock.dart';
import 'package:troona/features/player_skills/domain/skill_audio_effects.dart';
import 'package:troona/features/player_skills/domain/skill_coordinator.dart';
import 'package:troona/features/settings/domain/entities/app_settings.dart';
import 'package:troona/services/audio/audio_session_service.dart';
import 'package:troona/skills/skill.dart';
import 'mixer_probe.dart' show tone, report, phaseLabel;

class ObservedPlayer extends AudioPlayer {
  bool released = false;
  ObservedPlayer()
    : super(handleInterruptions: false, handleAudioSessionActivation: false);
  @override
  Future<void> dispose() async {
    await super.dispose();
    released = true;
  }
}

Track track(String id, File file) => Track(
  id: id,
  title: 'Probe $id',
  artist: 'Test',
  artistId: 1,
  album: 'Probe',
  albumId: 1,
  path: file.path,
  uri: '',
  size: file.lengthSync(),
  durationMs: 60000,
  fileName: '$id.wav',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final layers = <ObservedPlayer>[];
  final adapter = MixAudioAdapter(
    layerFactory: () {
      final player = ObservedPlayer();
      layers.add(player);
      return player;
    },
  )..elapsedNow = const AndroidSkillClock().now;
  final handler = await AudioService.init(
    builder: () => AudioHandlerImpl(adapter),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hadoken.player.probe',
      androidNotificationChannelName: 'Integrated audio probe',
    ),
  );
  final session = AudioSessionService(adapter, const AppSettings());
  await session.init();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: phaseLabel,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  unawaited(
    runProbe(
      adapter,
      handler,
      layers,
    ).then((_) => session.dispose()).catchError((Object e, StackTrace st) {
      report('failed', {'error': '$e', 'stack': '$st'});
    }),
  );
}

Future<void> runProbe(
  MixAudioAdapter audio,
  AudioHandler handler,
  List<ObservedPlayer> layers,
) async {
  final directory = await getTemporaryDirectory();
  final a = track('a', await tone(directory, 'integrated-440', frequency: 440));
  final b = track(
    'b',
    await tone(directory, 'integrated-880', frequency: 880, pulse: true),
  );
  final missing = Track(
    id: 'missing',
    title: 'Missing',
    artist: '',
    artistId: 1,
    album: '',
    albumId: 1,
    path: '${directory.path}/does-not-exist.wav',
    uri: '',
    size: 0,
    durationMs: 0,
    fileName: 'missing.wav',
  );
  audio.resolveSong = (id) async => {'a': a, 'b': b, 'missing': missing}[id];
  final effects = SkillAudioEffects(audio);
  var sequence = 0;
  Future<AppliedCapability> mix({
    double pitch = 1,
    double speed = 1,
    bool noise = false,
    bool fail = false,
    Duration lifetime = const Duration(seconds: 30),
  }) async {
    final id = 'mix-${sequence++}';
    final origin = SkillOrigin(
      owner: 'p1',
      skillKey: 'probe',
      invocationId: id,
      sessionId: audio.currentLoop!.sessionId,
    );
    return effects.apply(
      StartAudioMix(
        id,
        lifetime: lifetime,
        layers: noise
            ? [MixLayer(kind: MixLayerKind.noise, gain: .25)]
            : [
                MixLayer(
                  kind: MixLayerKind.song,
                  song: SongReference(fail ? 'b' : 'a'),
                  gain: 1,
                ),
                MixLayer(
                  kind: MixLayerKind.song,
                  song: SongReference(fail ? 'missing' : 'b'),
                  gain: 1,
                  pitch: pitch,
                  speed: speed,
                ),
              ],
      ),
      origin,
      SkillContext(
        sessionId: origin.sessionId,
        owner: 'p1',
        elapsed: await audio.elapsedNow(),
      ),
      SkillExecutionBudget(),
    );
  }

  Map<String, Object?> state() => {
    'primary': audio.currentStatus.name,
    'layers': layers.where((p) => !p.released).length,
    'playingLayers': layers.where((p) => !p.released && p.playing).length,
  };
  Future<void> phase(String name, int seconds) async {
    report(name, state());
    await Future<void>.delayed(Duration(seconds: seconds));
  }

  await phase('ready', 8);
  await audio.setQueue([a, b]);
  await audio.setVolume(.5);
  var effect = await mix();
  if (effect.result.status != CapabilityStatus.applied) {
    throw StateError(effect.result.reason);
  }
  await phase('blend', 4);
  await effect.cleanup!();
  effect = await mix(pitch: 1.5);
  await phase('pitch_1_5', 4);
  await effect.cleanup!();
  effect = await mix(speed: 1.5);
  final position = layers.last.position;
  final watch = Stopwatch()..start();
  await phase('speed_1_5', 4);
  report('speed_measured', {
    'sourceMs': (layers.last.position - position).inMilliseconds,
    'elapsedMs': watch.elapsedMilliseconds,
  });
  await handler.pause();
  await phase('paused', 3);
  await handler.play();
  await phase('resumed', 2);
  await audio.setDuckGain(.2);
  await phase('ducked', 3);
  await audio.setVolume(.4);
  await audio.setDuckGain(1);
  await effect.cleanup!();
  effect = await mix(noise: true);
  await phase('noise', 4);
  await effect.cleanup!();
  effect = await mix(pitch: 1.5, lifetime: const Duration(seconds: 5));
  report('screen_off_mix', state());
  await Future<void>.delayed(const Duration(milliseconds: 5500));
  report('screen_off_expired', state());
  await Future<void>.delayed(const Duration(seconds: 2));
  await effect.cleanup!();
  effect = await mix(fail: true);
  report('failed_source', {'status': effect.result.status.name, ...state()});
  await Future<void>.delayed(const Duration(seconds: 2));
  effect = await mix();
  report('request_system_pause');
  await Future<void>.delayed(const Duration(seconds: 1));
  await phase('system_paused', 3);
  await handler.play();
  await phase('system_resumed', 2);
  report('request_call');
  await Future<void>.delayed(const Duration(seconds: 2));
  await phase('interrupted', 3);
  report('end_call');
  await Future<void>.delayed(const Duration(seconds: 2));
  await phase('after_call', 2);
  await effect.cleanup!();
  for (var i = 0; i < 3; i++) {
    effect = await mix(noise: true);
    await effect.cleanup!();
    await effect.cleanup!();
  }
  report('repeated_cleanup', state());
  await handler.stop();
  await phase('stopped', 2);
  await audio.dispose();
  report('done', {'remainingLayers': layers.where((p) => !p.released).length});
}
