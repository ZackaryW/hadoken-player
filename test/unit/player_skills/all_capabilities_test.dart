import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player/domain/entities/repeat_mode.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/skill_controls.dart';
import 'package:troona/features/profiles/domain/effective_bindings.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/skills/registry.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/loop_player.dart';
import '../../helpers/scripted_skill.dart';
import '../../helpers/skill_fakes.dart';

void main() {
  test(
    'registered manual/listening skill uses every real adapter and restores base at boundaries',
    () async {
      final native = LoopPlayer();
      final layers = <LoopPlayer>[];
      final clock = FakeSkillClock();
      final audio = MixAudioAdapter(
        player: native,
        supportsAudioMix: true,
        schedulePlanTimers: false,
        scheduleMixTimers: false,
        layerFactory: () {
          final p = LoopPlayer();
          layers.add(p);
          return p;
        },
        noiseSource: () async => Uri.parse('file:///noise.wav'),
      )..elapsedNow = clock.now;
      final tracks = [
        for (final id in ['a', 'b', 'c']) testTrack(id, durationMs: 60000),
      ];
      audio.resolveSong = (id) async =>
          tracks.where((t) => t.id == id).firstOrNull;
      audio.searchSongs = (_, limit) async => tracks.take(limit).toList();
      await audio.setQueue(tracks.take(2).toList());
      await audio.pause(fade: Duration.zero);
      await audio.setRepeatMode(RepeatMode.all);
      final store = MemoryProfiles();
      final profiles = await ProfileRepository.open(store);
      await profiles.addProfile();
      const tap = Stroke(InputButton.forward, StrokeKind.tap);
      const hold = Stroke(InputButton.forward, StrokeKind.hold);
      const back = Stroke(InputButton.backward, StrokeKind.tap);
      await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [tap]);
      await profiles.setSkillMacro(ProfileId.p1, 'integration', [
        const Stroke(InputButton.pause, StrokeKind.tap),
      ]);
      final skill = ScriptedSkill(
        'integration',
        react: (event, context) {
          const lifetime = Duration(seconds: 10);
          if (event is SkillManualActivation) {
            return SkillReaction(
              requests: [
                ArmComboListener(
                  '${event.id}:listen',
                  listenerKey: 'watch',
                  combo: SkillCombo([SkillStroke.forwardHold]),
                  players: PlayerSelector(PlayerScope.all),
                  lifetime: lifetime,
                ),
                RestrictActions(
                  '${event.id}:block',
                  players: PlayerSelector(PlayerScope.all),
                  actions: [const PlaybackSkillTarget(SkillAction.nextTrack)],
                  lifetime: lifetime,
                  effort: Effort(60),
                ),
                OverrideCombos(
                  '${event.id}:override',
                  replacements: [
                    ComboReplacement(
                      'p2',
                      SkillAction.nextTrack,
                      SkillCombo([SkillStroke.forwardHold]),
                    ),
                  ],
                  lifetime: lifetime,
                ),
                FindSongs('${event.id}:find', limit: 2),
                EditLoopQueue(
                  '${event.id}:queue',
                  loops: FutureLoop(context.loop + 1),
                  expectedRevision: context.queueRevision,
                  operations: [InsertSong(SongReference('c'), '${event.id}:c')],
                  lifetime: lifetime,
                ),
                StartAudioMix(
                  '${event.id}:mix',
                  layers: [MixLayer(kind: MixLayerKind.noise)],
                  lifetime: lifetime,
                  sourceChange: MixSourceChange.continueUntilDeadline,
                ),
                ExecutePlayerAction(
                  '${event.id}:skip',
                  player: 'p1',
                  action: SkillAction.nextTrack,
                  effort: Effort(80),
                ),
              ],
            );
          }
          if (event is SkillComboObserved) {
            return SkillReaction(
              requests: [
                ExecutePlayerAction(
                  '${event.id}:tie',
                  player: context.actor!,
                  action: SkillAction.nextTrack,
                  effort: Effort(60),
                ),
                StartAudioMix(
                  '${event.id}:compete',
                  layers: [MixLayer(kind: MixLayerKind.noise)],
                  lifetime: lifetime,
                ),
              ],
            );
          }
          return SkillReaction.none;
        },
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
            ..bindAudio(audio)
            ..observeSessions(
              audio.sessionGenerations,
              audio.sessionGeneration,
            );
      final effective = EffectiveBindings(
        profiles: profiles,
        macroEnabled: policy.macroEnabled,
      );
      policy.bindEffectiveBindings(effective);
      final dispatcher = PlayerActionDispatcher(
        playback: PlaybackCommandsAdapter(audio),
        abilities: policy,
        catalog: () => effective.catalog,
      );
      final controls = SkillControls(
        profiles: profiles,
        assignments: assignments,
        policy: policy,
        dispatcher: dispatcher,
      );
      PlayerActionRequest request(String id, ExecutableBinding binding) =>
          PlayerActionRequest(
            requestId: id,
            binding: binding,
            recognizedAt: clock.elapsed,
            catalogRevision: effective.catalog.revision,
            observations: [
              for (final stroke in binding.strokes)
                StrokeObservation(
                  stroke,
                  clock.elapsed,
                  clock.elapsed + const Duration(milliseconds: 600),
                  null,
                ),
            ],
          );
      try {
        final stale = request(
          'stale',
          effective.catalog.bindingFor(ProfileId.p2, PlayerAction.nextTrack)!,
        );
        final manual = await dispatcher.dispatch(
          request('manual', effective.catalog.macros.single),
        );
        expect(
          manual.result.effects.map((e) => e.status),
          List.filled(7, CapabilityStatus.applied),
        );
        expect(audio.currentQueue!.currentIndex, 1);
        expect(layers.single.disposed, isFalse);
        expect(policy.effects.handles.length, 5);
        expect(
          policy.effects.handles.every((h) => h.origin.owner == 'p1'),
          isTrue,
        );
        expect(native.tracks.map((t) => t.id), ['a', 'b', 'a', 'b', 'c']);
        expect(
          effective.catalog
              .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
              .strokes,
          [hold],
        );
        expect(
          (await dispatcher.dispatch(stale)).result.status,
          ActionStatus.denied,
        );
        await expectLater(
          controls.setAssigned(ProfileId.p1, skill.id, false),
          throwsA(isA<SkillCooldown>()),
        );
        final listened = await dispatcher.dispatch(
          request(
            'listened',
            effective.catalog.bindingFor(ProfileId.p2, PlayerAction.nextTrack)!,
          ),
        );
        expect(listened.result.status, ActionStatus.denied);
        expect(listened.result.effects.map((e) => e.status), [
          CapabilityStatus.denied,
          CapabilityStatus.denied,
        ]);
        expect(
          skill.runtime.contexts.where((c) => c.actor == 'p2'),
          isNotEmpty,
        );
        // A saved edit survives while the temporary view remains active.
        await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [back]);
        expect(
          effective.catalog
              .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
              .strokes,
          [hold],
        );
        clock.elapsed = const Duration(seconds: 10);
        // Native navigation expires preloaded future plans before materializing.
        await audio.skipToNext();
        await dispatcher.runOrdered(
          () => policy.effects.retireDue(clock.elapsed),
        );
        expect(audio.currentLoop!.ordinal, 1);
        expect(audio.currentLoop!.occurrences.map((o) => o.song.libraryId), [
          'a',
          'b',
        ]);
        expect(policy.effects.handles, isEmpty);
        expect(layers.single.disposed, isTrue);
        expect(
          effective.catalog
              .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
              .strokes,
          [back],
        );
        final restored = await dispatcher.dispatch(
          request(
            'restored',
            effective.catalog.bindingFor(ProfileId.p2, PlayerAction.nextTrack)!,
          ),
        );
        expect(restored.result.status, ActionStatus.success);
        // Stop/restart clears new transient effects and retains only saved state.
        await dispatcher.dispatch(
          request('again', effective.catalog.macros.single),
        );
        await audio.stop();
        await pumpEventQueue();
        await dispatcher.runOrdered(() async {});
        expect(policy.effects.handles, isEmpty);
        expect(layers.every((p) => p.disposed), isTrue);
        await audio.resume();
        await pumpEventQueue();
        expect(policy.effects.handles, isEmpty);
        final reopened = await ProfileRepository.open(store);
        expect(
          reopened.catalog
              .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
              .strokes,
          [back],
        );
        await reopened.dispose();
        expect(skillDefinitions.map((d) => d.id), [SkillId.skipRecovery]);
      } finally {
        await policy.dispose();
        await effective.dispose();
        await dispatcher.dispose();
        await assignments.dispose();
        await profiles.dispose();
        await audio.dispose();
      }
    },
  );
}
