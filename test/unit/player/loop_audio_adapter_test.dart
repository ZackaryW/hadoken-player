import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:just_audio/just_audio.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player/domain/entities/repeat_mode.dart';
import 'package:troona/features/player/domain/entities/playback_state.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';

void main() {
  late LoopPlayer player;
  late LoopAudioAdapter adapter;
  var elapsed = Duration.zero;
  final a = testTrack('a', durationMs: 60000);
  final b = testTrack('b', durationMs: 60000);
  final c = testTrack('c', durationMs: 60000);
  var sequence = 0;
  setUp(() async {
    elapsed = Duration.zero;
    player = LoopPlayer();
    adapter = LoopAudioAdapter(player: player, schedulePlanTimers: false)
      ..elapsedNow = (() async => elapsed)
      ..resolveSong = ((id) async =>
          [a, b, c].where((t) => t.id == id).firstOrNull);
    expect((await adapter.setQueue([a, b])).isRight(), isTrue);
    await adapter.pause(fade: Duration.zero);
  });
  tearDown(() async {
    await adapter.dispose();
  });
  Future<void> settle() async {
    await pumpEventQueue(times: 10);
  }

  Future<CapabilityStatus> edit(
    LoopSelector target,
    List<QueueOperation> operations, {
    String? plan,
  }) async {
    final snapshot = adapter.currentLoop!;
    return (await adapter.editLoopQueue(
      EditLoopQueue(
        'effect-${sequence++}',
        loops: target,
        expectedRevision: snapshot.revision,
        operations: operations,
        lifetime: target is CurrentLoop ? null : const Duration(seconds: 10),
      ),
      sessionId: snapshot.sessionId,
      expectedLoop: snapshot.ordinal,
      planId: plan ?? 'plan-$sequence',
      elapsed: elapsed,
    )).status;
  }

  List<String> native() => player.tracks.map((t) => t.id).toList();
  List<String> visible() =>
      adapter.currentQueue!.playbackTracks.map((t) => t.id).toList();

  test(
    'repeat-all preloads future edits and forward entry freezes the next loop',
    () async {
      await adapter.setRepeatMode(RepeatMode.all);
      expect(native(), ['a', 'b', 'a', 'b']);
      expect(player.mode, LoopMode.off);
      final sourceLoads = player.loads.length;
      expect(
        await edit(FutureLoop(1), [InsertSong(SongReference('c'), 'added')]),
        CapabilityStatus.applied,
      );
      expect(visible(), ['a', 'b']);
      expect(
        player.loads.length,
        sourceLoads,
        reason: 'Future changes preserve the active decoder.',
      );
      expect(native(), ['a', 'b', 'a', 'b', 'c']);
      player.advance(2);
      await settle();
      expect(adapter.currentLoop!.ordinal, 1);
      expect(visible(), ['a', 'b', 'c']);
      expect(native(), ['a', 'b', 'c', 'a', 'b']);
      expect(player.index, 0);
    },
  );

  test(
    'repeat-off plans dormant, repeat-one does not advance, previous wrap stays local',
    () async {
      await edit(FutureLoop(1), [InsertSong(SongReference('c'), 'added')]);
      expect(native(), ['a', 'b']);
      await adapter.setRepeatMode(RepeatMode.one);
      expect(player.mode, LoopMode.one);
      await adapter.skipToNext();
      expect(adapter.currentQueue!.currentIndex, 1);
      expect(adapter.currentLoop!.ordinal, 0);
      await adapter.setRepeatMode(RepeatMode.all);
      await adapter.skipToNext();
      expect(adapter.currentLoop!.ordinal, 1);
      expect(visible(), ['a', 'b', 'c']);
      expect(player.playing, isFalse);
      await adapter.skipToPrevious();
      expect(adapter.currentQueue!.currentIndex, 2);
      expect(adapter.currentLoop!.ordinal, 1);
    },
  );

  test(
    'current duplicate removal does not alter baseline or another occurrence',
    () async {
      await adapter.setQueue([a, a, b]);
      await adapter.pause(fade: Duration.zero);
      final before = adapter.currentLoop!.occurrences;
      await edit(const CurrentLoop(), [RemoveOccurrence(before[1].id)]);
      expect(visible(), ['a', 'b']);
      expect(adapter.currentLoop!.occurrences.first.id, before.first.id);
      expect(adapter.previewLoop(1, elapsed)!.occurrences.length, 3);
      expect(player.playing, isFalse);
    },
  );

  test(
    'expiry and revoke rebuild a preloaded loop at unchanged current position',
    () async {
      player.position = const Duration(seconds: 12);
      await adapter.setRepeatMode(RepeatMode.all);
      await edit(FutureLoopRange(1), [
        RemoveOccurrence(adapter.currentLoop!.occurrences.first.id),
      ], plan: 'remove');
      expect(native(), ['a', 'b', 'b']);
      await adapter.revokeLoopPlan(
        adapter.currentLoop!.sessionId,
        'remove',
        elapsed,
      );
      expect(native(), ['a', 'b', 'a', 'b']);
      expect(player.position, const Duration(seconds: 12));
      await edit(FutureLoopRange(1), [
        RemoveOccurrence(adapter.currentLoop!.occurrences.first.id),
      ], plan: 'expire');
      elapsed = const Duration(seconds: 10);
      await adapter.revokeLoopPlan(
        adapter.currentLoop!.sessionId,
        'expire',
        elapsed,
      );
      expect(native(), ['a', 'b', 'a', 'b']);
      expect(player.playing, isFalse);
    },
  );

  test(
    'ordinary edits update future baseline while current-only insertions stay local',
    () async {
      await edit(const CurrentLoop(), [
        InsertSong(SongReference('c'), 'local'),
      ]);
      await adapter.removeFromQueue(0);
      await adapter.addToQueue(a);
      expect(visible(), ['b', 'c', 'a']);
      expect(
        adapter
            .previewLoop(1, elapsed)!
            .occurrences
            .map((o) => o.song.libraryId),
        ['b', 'a'],
      );
      await adapter.setShuffleEnabled(true);
      final ids = adapter.currentLoop!.occurrences.map((o) => o.id).toSet();
      await adapter.setShuffleEnabled(false);
      expect(adapter.currentLoop!.occurrences.map((o) => o.id).toSet(), ids);
    },
  );

  test(
    'failed source/load and stale session preserve committed model',
    () async {
      final saved = adapter.currentLoop!;
      expect(
        await edit(const CurrentLoop(), [
          InsertSong(SongReference('missing'), 'missing'),
        ]),
        CapabilityStatus.failed,
      );
      player.failNextLoad = true;
      expect(
        await edit(const CurrentLoop(), [
          RemoveOccurrence(saved.occurrences.first.id),
        ]),
        CapabilityStatus.failed,
      );
      expect(visible(), ['a', 'b']);
      expect(native(), ['a', 'b']);
      expect(adapter.currentLoop!.revision, saved.revision);
      await adapter.setQueue([c]);
      final result = await adapter.editLoopQueue(
        EditLoopQueue(
          'stale',
          loops: const CurrentLoop(),
          expectedRevision: saved.revision,
          operations: [RemoveOccurrence(saved.occurrences.first.id)],
        ),
        sessionId: saved.sessionId,
        expectedLoop: saved.ordinal,
        planId: 'old',
        elapsed: elapsed,
      );
      expect(result.status, CapabilityStatus.denied);
      expect(visible(), ['c']);
    },
  );

  test(
    'empty next loop stops once and final current removal releases playback',
    () async {
      await adapter.setRepeatMode(RepeatMode.all);
      await edit(FutureLoop(1), [
        for (final o in adapter.currentLoop!.occurrences)
          RemoveOccurrence(o.id),
      ]);
      await adapter.skipToNext();
      await adapter.skipToNext();
      expect(adapter.currentLoop!.ordinal, 1);
      expect(visible(), isEmpty);
      expect(player.playing, isFalse);
      expect(player.stops, greaterThan(0));
      await adapter.setQueue([a]);
      await edit(const CurrentLoop(), [
        RemoveOccurrence(adapter.currentLoop!.occurrences.single.id),
      ]);
      expect(player.playing, isFalse);
      expect(native(), isEmpty);
    },
  );

  test(
    'bounded song lookup and source replacement cancel future plans',
    () async {
      expect((await adapter.findSkillSongs('Title', limit: 1)).length, 1);
      await expectLater(
        adapter.findSkillSongs('', limit: 201),
        throwsArgumentError,
      );
      await edit(FutureLoopRange(1), [InsertSong(SongReference('c'), 'extra')]);
      final old = adapter.currentLoop!.sessionId;
      await adapter.setQueue([b]);
      await adapter.revokeLoopPlan(old, 'irrelevant', elapsed);
      expect(
        adapter
            .previewLoop(1, elapsed)!
            .occurrences
            .map((o) => o.song.libraryId),
        ['b'],
      );
      await adapter.stop();
      expect(adapter.currentLoop, isNull);
    },
  );

  test(
    'native boundary during source lookup rejects the old loop instead of retargeting',
    () async {
      await adapter.setRepeatMode(RepeatMode.all);
      final gate = Completer<void>();
      adapter.resolveSong = (id) async {
        await gate.future;
        return c;
      };
      final editing = edit(const CurrentLoop(), [
        InsertSong(SongReference('c'), 'racing'),
      ]);
      await settle();
      player.advance(2);
      gate.complete();
      expect(await editing, CapabilityStatus.denied);
      await settle();
      expect(adapter.currentLoop!.ordinal, 1);
      expect(visible(), ['a', 'b']);
      expect(native(), ['a', 'b', 'a', 'b']);
    },
  );

  test(
    'removing playing last occurrence stops without replaying a previous song',
    () async {
      await adapter.skipToNext();
      await adapter.resume();
      final before = player.stops;
      await edit(const CurrentLoop(), [
        RemoveOccurrence(adapter.currentLoop!.occurrences.last.id),
      ]);
      expect(visible(), ['a']);
      expect(player.stops, greaterThan(before));
      expect(player.playing, isFalse);
      expect(adapter.currentStatus, PlaybackStatus.stopped);
      expect(adapter.currentTrack, isNull);
    },
  );

  test('permission denial rejects even a distant future insertion', () async {
    adapter.canReadSong = (_) async => false;
    expect(
      await edit(FutureLoop(20), [InsertSong(SongReference('c'), 'denied')]),
      CapabilityStatus.failed,
    );
    expect(adapter.previewLoop(20, elapsed)!.occurrences.length, 2);
  });

  test(
    'service timer rebuilds an expired provisional window without UI activity',
    () {
      fakeAsync((time) {
        final native = LoopPlayer();
        final service = LoopAudioAdapter(player: native)
          ..elapsedNow = (() async => time.elapsed);
        unawaited(service.setQueue([a, b]));
        time.flushMicrotasks();
        unawaited(service.pause(fade: Duration.zero));
        time.flushMicrotasks();
        unawaited(service.setRepeatMode(RepeatMode.all));
        time.flushMicrotasks();
        final snapshot = service.currentLoop!;
        unawaited(
          service.editLoopQueue(
            EditLoopQueue(
              'deadline',
              loops: FutureLoop(1),
              expectedRevision: snapshot.revision,
              operations: [RemoveOccurrence(snapshot.occurrences.first.id)],
              lifetime: const Duration(seconds: 10),
            ),
            sessionId: snapshot.sessionId,
            expectedLoop: 0,
            planId: 'deadline',
            elapsed: time.elapsed,
          ),
        );
        time.flushMicrotasks();
        expect(native.tracks.map((t) => t.id), ['a', 'b', 'b']);
        time.elapse(const Duration(seconds: 10));
        time.flushMicrotasks();
        expect(native.tracks.map((t) => t.id), ['a', 'b', 'a', 'b']);
        expect(service.currentLoop!.ordinal, 0);
        expect(native.playing, isFalse);
        unawaited(service.dispose());
        time.flushMicrotasks();
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    },
  );
}
