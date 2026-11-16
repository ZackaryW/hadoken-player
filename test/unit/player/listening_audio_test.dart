import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player/domain/entities/repeat_mode.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';

void main() {
  late LoopPlayer player;
  late LoopAudioAdapter adapter;
  var time = Duration.zero;
  final a = testTrack('a', durationMs: 60000);
  final b = testTrack('b', durationMs: 60000);
  Future<void> settle() => pumpEventQueue(times: 10);
  setUp(() async {
    time = Duration.zero;
    player = LoopPlayer();
    adapter = LoopAudioAdapter(player: player, schedulePlanTimers: false)
      ..listeningNow = (() => time)
      ..elapsedNow = (() async => time);
    expect(adapter.skillPlayback.playId, isNull);
    await adapter.setQueue([a, a, b]);
    await settle();
  });
  tearDown(() => adapter.dispose());

  test(
    'actual listening excludes pause/buffering and ignores seeking/speed',
    () async {
      time = const Duration(seconds: 10);
      expect(adapter.skillPlayback.listened, time);
      final id = adapter.skillPlayback.playId;
      await adapter.pause(fade: Duration.zero);
      await settle();
      time = const Duration(seconds: 40);
      await adapter.seekTo(const Duration(seconds: 50));
      expect(adapter.skillPlayback.listened, const Duration(seconds: 10));
      await adapter.resume();
      await settle();
      time = const Duration(seconds: 45);
      player.setProcessing(ProcessingState.buffering);
      await settle();
      time = const Duration(seconds: 60);
      expect(adapter.skillPlayback.listened, const Duration(seconds: 15));
      player.setProcessing(ProcessingState.ready);
      await adapter.setSpeed(2);
      await settle();
      // No intermediate timer samples, as when UI callbacks are suspended.
      time = const Duration(seconds: 65);
      expect(adapter.skillPlayback.listened, const Duration(seconds: 20));
      await adapter.seekTo(Duration.zero);
      expect(adapter.skillPlayback.playId, id);
      expect(adapter.skillPlayback.listened, const Duration(seconds: 20));
    },
  );

  test(
    'duplicate occurrences, natural repeat and completion start fresh plays',
    () async {
      time = const Duration(seconds: 25);
      final first = adapter.skillPlayback;
      expect(first.listened, time);
      player.advance(1);
      await settle();
      final second = adapter.skillPlayback;
      expect(second.playId, isNot(first.playId));
      expect(second.listened, Duration.zero);
      await adapter.setRepeatMode(RepeatMode.one);
      time = const Duration(seconds: 50);
      expect(adapter.skillPlayback.listened, const Duration(seconds: 25));
      player.repeatNaturally();
      final repeat = adapter.skillPlayback;
      expect(repeat.playId, isNot(second.playId));
      expect(repeat.listened, Duration.zero);
      player.complete();
      await settle();
      expect(adapter.skillPlayback.playId, isNull);
      expect(adapter.skillPlayback.listened, Duration.zero);
    },
  );

  test(
    'queue edits preserve current occurrence; stop and replacement reset',
    () async {
      time = const Duration(seconds: 21);
      final before = adapter.skillPlayback;
      final snapshot = adapter.currentLoop!;
      await adapter.editLoopQueue(
        EditLoopQueue(
          'remove-other',
          loops: const CurrentLoop(),
          expectedRevision: snapshot.revision,
          operations: [RemoveOccurrence(snapshot.occurrences.last.id)],
        ),
        sessionId: snapshot.sessionId,
        expectedLoop: snapshot.ordinal,
        planId: 'remove',
        elapsed: time,
      );
      await settle();
      expect(adapter.skillPlayback.playId, before.playId);
      expect(adapter.skillPlayback.listened, before.listened);
      await adapter.stop();
      expect(adapter.skillPlayback.playId, isNull);
      await adapter.setQueue([a]);
      await settle();
      expect(adapter.skillPlayback.playId, isNot(before.playId));
      expect(adapter.skillPlayback.listened, Duration.zero);
    },
  );
}
