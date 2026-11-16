import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player/domain/entities/repeat_mode.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';
import '../../helpers/scripted_skill.dart';
import '../../helpers/skill_fakes.dart';

void main() {
  test(
    'manual capability uses real queue snapshots, bounded lookup and owned expiry cleanup',
    () async {
      final native = LoopPlayer();
      final clock = FakeSkillClock();
      final audio = LoopAudioAdapter(player: native, schedulePlanTimers: false)
        ..elapsedNow = clock.now;
      final a = testTrack('a', durationMs: 60000);
      final b = testTrack('b', durationMs: 60000);
      audio.resolveSong = (id) async => id == 'b' ? b : a;
      audio.searchSongs = (query, limit) async => [a, b];
      await audio.setQueue([a]);
      await audio.pause(fade: Duration.zero);
      await audio.setRepeatMode(RepeatMode.all);
      final profiles = await ProfileRepository.open(MemoryProfiles());
      await profiles.setSkillMacro(ProfileId.p1, 'planner', [
        const Stroke(InputButton.pause, StrokeKind.tap),
      ]);
      final skill = ScriptedSkill(
        'planner',
        react: (event, context) => event is SkillManualActivation
            ? SkillReaction(
                requests: [
                  FindSongs('${event.id}:find', limit: 1),
                  EditLoopQueue(
                    '${event.id}:future',
                    loops: FutureLoop(context.loop + 1),
                    expectedRevision: context.queueRevision,
                    operations: [
                      InsertSong(SongReference('b'), '${event.id}:b'),
                    ],
                    lifetime: const Duration(seconds: 10),
                  ),
                  EditLoopQueue(
                    '${event.id}:stale',
                    loops: const CurrentLoop(),
                    expectedRevision: context.queueRevision,
                    operations: [RemoveOccurrence(context.queue.first.id)],
                  ),
                ],
              )
            : SkillReaction.none,
      );
      final assignments = await SkillAssignmentRepository.open(
        MemorySkills(),
        profileExists: (_) => true,
        definitions: [skill],
      );
      await assignments.setAssigned(ProfileId.p1, skill.id, true);
      final policy =
          SkillPolicy(
              assignments: assignments,
              clock: clock,
              definitions: [skill],
              scheduleTimers: false,
            )
            ..bindQueue(audio)
            ..observeSessions(
              audio.sessionGenerations,
              audio.sessionGeneration,
            );
      final dispatcher = PlayerActionDispatcher(
        playback: PlaybackCommandsAdapter(audio),
        abilities: policy,
        catalog: () => profiles.catalog,
      );
      try {
        final outcome = await dispatcher.dispatch(
          PlayerActionRequest(
            requestId: 'manual',
            binding: profiles.catalog.macros.single,
            recognizedAt: Duration.zero,
            observations: [
              const StrokeObservation(
                Stroke(InputButton.pause, StrokeKind.tap),
                Duration.zero,
                Duration(milliseconds: 100),
                null,
              ),
            ],
          ),
        );
        expect(outcome.result.effects.map((r) => r.status), [
          CapabilityStatus.applied,
          CapabilityStatus.applied,
          CapabilityStatus.denied,
        ]);
        expect(skill.runtime.results.first.songs.single.libraryId, 'a');
        expect(skill.runtime.contexts.first.queue.single.song.libraryId, 'a');
        expect(native.tracks.map((t) => t.id), ['a', 'a', 'b']);
        expect((await policy.remaining(ProfileId.p1)).inSeconds, 10);
        clock.elapsed = const Duration(seconds: 10);
        await dispatcher.runOrdered(
          () => policy.effects.retireDue(clock.elapsed),
        );
        expect(native.tracks.map((t) => t.id), ['a', 'a']);
        expect(native.playing, isFalse);
        expect(policy.effects.handles, isEmpty);
      } finally {
        await policy.dispose();
        await dispatcher.dispose();
        await assignments.dispose();
        await profiles.dispose();
        await audio.dispose();
      }
    },
  );
}
