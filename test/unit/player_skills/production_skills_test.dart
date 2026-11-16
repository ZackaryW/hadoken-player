import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/player_skills/domain/skill_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/registry.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/skill_controls.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/features/profiles/domain/effective_bindings.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import '../../helpers/skill_fakes.dart';

void main() {
  late ProfileRepository profiles;
  late SkillAssignmentRepository assignments;
  late SkillPolicy policy;
  late PlayerActionDispatcher dispatcher;
  late EffectiveBindings effective;
  late SkillControls controls;
  late SkillCommands commands;
  var snapshot = const SkillPlaybackSnapshot();
  var sequence = 0;
  setUp(() async {
    snapshot = const SkillPlaybackSnapshot(playId: 'first', playing: true);
    profiles = await ProfileRepository.open(MemoryProfiles());
    await profiles.addProfile();
    await profiles.addProfile();
    for (final player in ProfileId.values) {
      for (final action in PlayerAction.values) {
        await profiles.setBinding(player, action, [
          Stroke(InputButton.values[player.index], StrokeKind.tap),
          Stroke(
            InputButton.values[action.index ~/ 2],
            StrokeKind.values[action.index % 2],
          ),
        ]);
      }
    }
    assignments = await SkillAssignmentRepository.open(
      MemorySkills(),
      profileExists: (_) => true,
    );
    await assignments.setAssigned(ProfileId.p1, SkillId.songCommitment, true);
    await assignments.setAssigned(ProfileId.p2, SkillId.forceSkip, true);
    await profiles.setSkillMacro(ProfileId.p2, 'force-skip', const [
      Stroke(InputButton.pause, StrokeKind.hold),
    ]);
    policy = SkillPolicy(
      assignments: assignments,
      clock: FakeSkillClock(),
      scheduleTimers: false,
    )..playbackSnapshot = (() async => snapshot);
    effective = EffectiveBindings(
      profiles: profiles,
      macroEnabled: policy.macroEnabled,
    );
    commands = SkillCommands();
    dispatcher = PlayerActionDispatcher(
      playback: commands,
      catalog: () => effective.catalog,
      abilities: policy,
    );
    controls = SkillControls(
      profiles: profiles,
      assignments: assignments,
      policy: policy,
      dispatcher: dispatcher,
    );
  });
  tearDown(() async {
    await dispatcher.dispose();
    await policy.dispose();
    await effective.dispose();
    await assignments.dispose();
    await profiles.dispose();
  });
  PlayerActionRequest input(ExecutableBinding binding, {Effort? effort}) =>
      PlayerActionRequest(
        requestId: 'test-${sequence++}',
        binding: binding,
        recognizedAt: Duration.zero,
        effort: effort ?? dispatcher.effortFor(binding),
        observations: [
          for (final stroke in binding.strokes)
            StrokeObservation(
              stroke,
              Duration.zero,
              const Duration(milliseconds: 100),
              null,
            ),
        ],
      );
  Future<PlayerActionOutcome> action(
    ProfileId player,
    PlayerAction action, {
    Effort? effort,
  }) => dispatcher.dispatch(
    input(effective.catalog.bindingFor(player, action)!, effort: effort),
  );
  PlayerActionRequest force() =>
      input(effective.catalog.macroFor(ProfileId.p2, 'force-skip')!);
  void lock() => snapshot = const SkillPlaybackSnapshot(
    playId: 'first',
    listened: Duration(seconds: 20),
    playing: true,
  );

  test(
    'exact listening threshold blocks four actions for every player, ties block',
    () async {
      snapshot = const SkillPlaybackSnapshot(
        playId: 'first',
        listened: Duration(milliseconds: 19999),
      );
      expect(
        (await action(ProfileId.p1, PlayerAction.nextTrack)).result.succeeded,
        isTrue,
      );
      lock();
      for (final player in ProfileId.values) {
        for (final command in [
          PlayerAction.nextTrack,
          PlayerAction.previousTrack,
          PlayerAction.seekForward,
          PlayerAction.seekBackward,
        ]) {
          final outcome = await action(player, command);
          expect(outcome.result.status, ActionStatus.denied);
          expect(outcome.result.message, contains('Song Commitment (90)'));
          expect(
            (await action(player, command, effort: Effort(90))).result.status,
            ActionStatus.denied,
          );
        }
      }
      expect(
        (await action(
          ProfileId.p3,
          PlayerAction.togglePlayback,
        )).result.succeeded,
        isTrue,
      );
      expect(
        (await action(ProfileId.p3, PlayerAction.stop)).result.succeeded,
        isTrue,
      );
      expect(
        (await action(
          ProfileId.p3,
          PlayerAction.nextTrack,
          effort: Effort(91),
        )).result.succeeded,
        isTrue,
      );
    },
  );

  test(
    'manual force uses 100, deduplicates, respects 100 blocks and reports no-op/failure',
    () async {
      lock();
      final request = force();
      expect(request.effort, Effort.maximum);
      final outcome = await dispatcher.dispatch(request);
      expect(outcome.result.succeeded, isTrue);
      await dispatcher.dispatch(request);
      expect(commands.calls, [PlayerAction.nextTrack]);
      for (final status in [ActionStatus.noOp, ActionStatus.failure]) {
        commands.result = CommandResult(status, 'Backend result');
        expect((await dispatcher.dispatch(force())).result.status, status);
        expect(
          (await action(ProfileId.p1, PlayerAction.nextTrack)).result.status,
          ActionStatus.denied,
        );
      }
      commands.result = const CommandResult(ActionStatus.success, 'Skipped');
      final context = SkillContext(
        sessionId: 'playback-0',
        owner: 'p1',
        elapsed: Duration.zero,
        players: ['p1', 'p2', 'p3'],
      );
      final origin = SkillOrigin(
        owner: 'p1',
        skillKey: 'song-commitment',
        invocationId: 'strong-block',
        sessionId: 'playback-0',
      );
      final applied = await policy.gameplay.apply(
        RestrictActions(
          'block',
          players: PlayerSelector(PlayerScope.all),
          actions: [const PlaybackSkillTarget(SkillAction.nextTrack)],
          lifetime: const Duration(seconds: 10),
          effort: Effort.maximum,
        ),
        origin,
        context,
        SkillExecutionBudget(),
      );
      policy.effects.register(
        applied.result.handle!,
        applied.cleanup!,
        Duration.zero,
      );
      expect(
        (await dispatcher.dispatch(force())).result.status,
        ActionStatus.denied,
      );
    },
  );

  test(
    'song lock survives pause/rebinding and denies unequip, resets on next play',
    () async {
      lock();
      await policy.statuses(ProfileId.p1);
      expect(
        (await policy.statuses(ProfileId.p1))[SkillId.songCommitment],
        'Song locked',
      );
      snapshot = const SkillPlaybackSnapshot(
        playId: 'first',
        listened: Duration(seconds: 20),
        playing: false,
      );
      await expectLater(
        controls.setAssigned(ProfileId.p1, SkillId.songCommitment, false),
        throwsA(isA<SkillAssignmentLocked>()),
      );
      await profiles.rename(ProfileId.p1, 'Owner');
      expect(
        (await action(ProfileId.p2, PlayerAction.previousTrack)).result.status,
        ActionStatus.denied,
      );
      snapshot = const SkillPlaybackSnapshot(playId: 'second');
      expect(
        (await action(ProfileId.p2, PlayerAction.nextTrack)).result.succeeded,
        isTrue,
      );
      await controls.setAssigned(ProfileId.p1, SkillId.songCommitment, false);
      await controls.setAssigned(ProfileId.p3, SkillId.songCommitment, true);
      expect(
        (await policy.statuses(ProfileId.p3))[SkillId.songCommitment],
        'Listening',
      );
      final oldMacro = force();
      await controls.setAssigned(ProfileId.p2, SkillId.forceSkip, false);
      expect(
        (await dispatcher.dispatch(oldMacro)).result.status,
        ActionStatus.denied,
      );
    },
  );

  test(
    'late equip observes existing listening and retired mock does not auto-equip',
    () async {
      await controls.setAssigned(ProfileId.p1, SkillId.songCommitment, false);
      lock();
      await controls.setAssigned(ProfileId.p3, SkillId.songCommitment, true);
      expect(
        (await action(ProfileId.p1, PlayerAction.nextTrack)).result.status,
        ActionStatus.denied,
      );
      final decoded = SkillAssignmentRepository.decode(
        '{"version":1,"profiles":{"p1":["skip-recovery","future"]}}',
      );
      expect(decoded.values[ProfileId.p1], {'future'});
      expect(decoded.recoveryMessages.single, contains('retired'));
      final store = MemorySkills()
        ..document =
            '{"version":1,"profiles":{"p1":["skip-recovery","future"]}}';
      final migrated = await SkillAssignmentRepository.open(
        store,
        profileExists: (_) => true,
      );
      expect(store.document, isNot(contains('skip-recovery')));
      expect(migrated.catalog.unavailable(ProfileId.p1), ['future']);
      await migrated.dispose();
      expect(skillDefinitions.map((s) => s.id), [
        SkillId.songCommitment,
        SkillId.forceSkip,
      ]);
    },
  );
}
