// Device-only feasibility entry point; never part of the production catalog.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

final phaseLabel = ValueNotifier('Preparing audio probe');
void report(String phase, [Map<String, Object?> details = const {}]) {
  phaseLabel.value = phase;
  debugPrint(
    'AUDIO_PROBE ${jsonEncode({'phase': phase, 'wallUs': DateTime.now().microsecondsSinceEpoch, ...details})}',
  );
}

Future<File> tone(
  Directory directory,
  String name, {
  double? frequency,
  bool pulse = false,
}) async {
  const rate = 48000;
  const frames = rate * 60;
  final bytes = ByteData(44 + frames * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + frames * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, frames * 2, Endian.little);
  final random = Random(7);
  for (var i = 0; i < frames; i++) {
    final sample = frequency == null
        ? random.nextDouble() * 2 - 1
        : sin(2 * pi * frequency * i / rate);
    final envelope = pulse && (i % (rate ~/ 2) > rate ~/ 4) ? 0.15 : 1.0;
    bytes.setInt16(
      44 + i * 2,
      (sample * envelope * 6000).round(),
      Endian.little,
    );
  }
  return File('${directory.path}/$name.wav')
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

class ProbeHandler extends BaseAudioHandler {
  final players = <AudioPlayer>[];
  void publish(bool playing) => playbackState.add(
    PlaybackState(
      controls: [
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
      ],
      processingState: AudioProcessingState.ready,
      playing: playing,
    ),
  );
  @override
  Future<void> play() async {
    for (final player in players) {
      unawaited(player.play());
    }
    publish(true);
  }

  @override
  Future<void> pause() async {
    await Future.wait(players.map((p) => p.pause()));
    publish(false);
  }

  @override
  Future<void> stop() async {
    await Future.wait(players.map((p) => p.stop()));
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }

  Future<void> gain(double value) =>
      Future.wait(players.map((p) => p.setVolume(value)));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  final handler = await AudioService.init(
    builder: ProbeHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hadoken.player.probe',
      androidNotificationChannelName: 'Audio probe',
    ),
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: phaseLabel,
            builder: (_, value, _) => Text(value, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
  unawaited(
    runProbe(handler).catchError((Object error, StackTrace stack) {
      report('failed', {'error': '$error', 'stack': '$stack'});
    }),
  );
}

Future<void> runProbe(ProbeHandler handler) async {
  final directory = await getTemporaryDirectory();
  final first = await tone(directory, 'probe-440', frequency: 440);
  final second = await tone(
    directory,
    'probe-880',
    frequency: 880,
    pulse: true,
  );
  final noise = await tone(directory, 'probe-noise');
  final primary = AudioPlayer(handleInterruptions: false);
  final secondary = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  final overlay = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  await primary.setFilePath(first.path);
  await secondary.setFilePath(second.path);
  await overlay.setFilePath(noise.path);
  await primary.setLoopMode(LoopMode.one);
  await secondary.setLoopMode(LoopMode.one);
  await overlay.setLoopMode(LoopMode.one);
  handler.players.addAll([primary, secondary]);
  handler.mediaItem.add(
    const MediaItem(id: 'probe', title: 'Audio capability probe'),
  );
  Future<void> phase(
    String name,
    int seconds, [
    Map<String, Object?> data = const {},
  ]) async {
    report(name, data);
    await Future<void>.delayed(Duration(seconds: seconds));
  }

  await phase('ready', 8);
  await handler.gain(0.5);
  await handler.play();
  await phase('blend', 5);
  await secondary.setPitch(1.5);
  await phase('pitch_1_5', 5);
  await secondary.setPitch(1);
  await secondary.setSpeed(1.5);
  final position = secondary.position;
  final watch = Stopwatch()..start();
  await phase('speed_1_5', 5);
  report('speed_measured', {
    'sourceMs': (secondary.position - position).inMilliseconds,
    'elapsedMs': watch.elapsedMilliseconds,
  });
  await handler.pause();
  await phase('paused', 3, {
    'playing': handler.players.map((p) => p.playing).toList(),
  });
  await secondary.setSpeed(1);
  await handler.play();
  await phase('resumed', 3);
  await handler.gain(0.1);
  await phase('ducked', 3);
  await handler.gain(0.5);
  await secondary.pause();
  await overlay.setVolume(0.25);
  unawaited(overlay.play());
  handler.players.add(overlay);
  await phase('noise', 4);
  await overlay.dispose();
  handler.players.remove(overlay);
  await secondary.setPitch(1.5);
  unawaited(secondary.play());
  final expiry = Completer<void>();
  Timer(const Duration(seconds: 5), () async {
    await secondary.dispose();
    handler.players.remove(secondary);
    report('screen_off_expired', {
      'primaryPlaying': primary.playing,
      'layers': handler.players.length,
    });
    expiry.complete();
  });
  await phase('screen_off_mix', 8);
  await expiry.future;
  final failing = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  var rejected = false;
  try {
    await failing.setFilePath('${directory.path}/missing-probe.wav');
  } catch (_) {
    rejected = true;
  } finally {
    await failing.dispose();
  }
  await phase('failed_source_cleaned', 3, {
    'rejected': rejected,
    'layers': handler.players.length,
    'primaryPlaying': primary.playing,
  });
  await handler.stop();
  await phase('stopped', 3, {'playing': primary.playing});
  await primary.dispose();
  handler.players.clear();
  report('done', {'layers': handler.players.length});
}
