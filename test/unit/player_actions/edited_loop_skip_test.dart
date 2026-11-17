import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/core/error/failures.dart';
import 'package:troona/skills/skill.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player/domain/entities/playback_state.dart';
import 'package:troona/features/player/domain/entities/repeat_mode.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';

class ReplacingAudio extends LoopAudioAdapter {
  ReplacingAudio() : super(player: LoopPlayer(), schedulePlanTimers: false);
  @override
  Future<Either<Failure, Unit>> skipToNext() =>
      setQueue([testTrack('other', durationMs: 60000)]);
}

void main() {
  for (final playing in [false, true]) {
    for (final single in [false, true]) {
      test(
        'edited next loop succeeds; playing=$playing single=$single',
        () async {
          final adapter =
              LoopAudioAdapter(player: LoopPlayer(), schedulePlanTimers: false)
                ..elapsedNow = (() async => Duration.zero)
                ..resolveSong = ((_) async =>
                    testTrack('c', durationMs: 60000));
          addTearDown(adapter.dispose);
          await adapter.setQueue([
            testTrack('a', durationMs: 60000),
            if (!single) testTrack('b', durationMs: 60000),
          ]);
          await adapter.pause(fade: Duration.zero);
          await adapter.setRepeatMode(RepeatMode.all);
          final loop = adapter.currentLoop!;
          final result = await adapter.editLoopQueue(
            EditLoopQueue(
              'edit',
              loops: FutureLoop(1),
              expectedRevision: loop.revision,
              operations: [
                InsertSong(
                  SongReference('c'),
                  'added',
                  beforeOccurrenceId: loop.occurrences.first.id,
                ),
              ],
              lifetime: const Duration(seconds: 30),
            ),
            sessionId: loop.sessionId,
            expectedLoop: loop.ordinal,
            planId: 'plan',
            elapsed: Duration.zero,
          );
          expect(result.status, CapabilityStatus.applied);
          if (!single) await adapter.skipToNext();
          if (playing) await adapter.resume();
          final outcome = await PlaybackCommandsAdapter(
            adapter,
          ).execute(PlayerAction.nextTrack);
          expect(adapter.currentLoop!.ordinal, 1);
          expect(adapter.currentTrack!.id, 'c');
          expect(outcome.status, ActionStatus.success);
          expect(
            adapter.currentStatus,
            playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          );
        },
      );
    }
  }
  test('empty future loop never reports a successful track skip', () async {
    final adapter = LoopAudioAdapter(
      player: LoopPlayer(),
      schedulePlanTimers: false,
    )..elapsedNow = (() async => Duration.zero);
    addTearDown(adapter.dispose);
    await adapter.setQueue([
      testTrack('a', durationMs: 60000),
      testTrack('b', durationMs: 60000),
    ]);
    await adapter.pause(fade: Duration.zero);
    await adapter.setRepeatMode(RepeatMode.all);
    final loop = adapter.currentLoop!;
    await adapter.editLoopQueue(
      EditLoopQueue(
        'empty',
        loops: FutureLoop(1),
        expectedRevision: loop.revision,
        operations: [
          for (final occurrence in loop.occurrences)
            RemoveOccurrence(occurrence.id),
        ],
        lifetime: const Duration(seconds: 30),
      ),
      sessionId: loop.sessionId,
      expectedLoop: loop.ordinal,
      planId: 'empty',
      elapsed: Duration.zero,
    );
    await adapter.skipToNext();
    final outcome = await PlaybackCommandsAdapter(
      adapter,
    ).execute(PlayerAction.nextTrack);
    expect(outcome.status, ActionStatus.noOp);
    expect(adapter.currentTrack, isNull);
  });
  test('unrelated replacement is not credited as a loop skip', () async {
    final adapter = ReplacingAudio();
    addTearDown(adapter.dispose);
    await adapter.setQueue([
      testTrack('a', durationMs: 60000),
      testTrack('b', durationMs: 60000),
    ], startIndex: 1);
    await adapter.setRepeatMode(RepeatMode.all);
    final outcome = await PlaybackCommandsAdapter(
      adapter,
    ).execute(PlayerAction.nextTrack);
    expect(adapter.currentTrack!.id, 'other');
    expect(outcome.status, ActionStatus.noOp);
  });
}
