import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_catalog.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/features/player/domain/entities/queue.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/skill_fakes.dart';
import '../player_actions/playback_commands_adapter_test.dart'
    show CommandAudio;

class ManualInputClock implements InputClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  CancelInputTimer schedule(Duration delay, void Function() callback) => () {};
}

void main() {
  test(
    'saved combos and real adapter enforce P2/P1 recovery and ignore unattributed activity',
    () async {
      final profiles = await ProfileRepository.open(MemoryProfiles());
      await profiles.addProfile();
      await profiles.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
        const Stroke(InputButton.backward, StrokeKind.tap),
      ]);
      await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
        const Stroke(InputButton.forward, StrokeKind.tap),
      ]);
      final assignments = await SkillAssignmentRepository.open(
        MemorySkills(),
        profileExists: (_) => true,
      );
      await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
      final clock = FakeSkillClock();
      final policy = SkillPolicy(assignments: assignments, clock: clock);
      final audio = CommandAudio()
        ..queue = Queue.fromTracks([
          for (var i = 0; i < 4; i++) testTrack('$i', durationMs: 30000),
        ], startIndex: 0);
      final adapter = PlaybackCommandsAdapter(audio);
      final dispatcher = PlayerActionDispatcher(
        playback: adapter,
        catalog: () => profiles.catalog,
        abilities: policy,
      );
      final controls = ProfileControls(
        profiles: profiles,
        dispatcher: dispatcher,
        clock: ManualInputClock(),
      );
      final outcomes = <PlayerActionOutcome>[];
      final sub = dispatcher.outcomes.listen(outcomes.add);
      final sessions = <ComboInput>[];
      Future<void> enter(ComboInput input, InputButton button) async {
        input.down(button, 1);
        input.up(1);
        await dispatcher.runOrdered(() async {});
      }

      for (final mode in [InputMode.recording, InputMode.practice]) {
        final input = controls.createInput(mode: mode);
        sessions.add(input);
        await enter(input, InputButton.forward);
        expect(outcomes, isEmpty);
        expect(await policy.remaining(ProfileId.p2), Duration.zero);
      }
      // Conventional/system controls reach the adapter without profile attribution.
      await adapter.execute(PlayerAction.nextTrack);
      expect(outcomes, isEmpty);
      expect(await policy.remaining(ProfileId.p2), Duration.zero);
      audio.queue = audio.queue!.copyWith(
        currentIndex: 0,
      ); // Simulated unowned queue transition.
      final input = controls.createInput();
      sessions.add(input);
      await enter(input, InputButton.forward);
      expect(audio.currentQueue!.currentIndex, 1);
      await enter(input, InputButton.forward);
      expect(outcomes.last.result.status, ActionStatus.denied);
      expect(audio.currentQueue!.currentIndex, 1);
      clock.elapsed = const Duration(seconds: 3);
      await enter(input, InputButton.backward);
      expect(audio.currentQueue!.currentIndex, 2);
      expect(await policy.remaining(ProfileId.p2), const Duration(seconds: 7));
      clock.elapsed = const Duration(seconds: 10);
      await enter(input, InputButton.forward);
      expect(audio.currentQueue!.currentIndex, 3);
      clock.elapsed = const Duration(seconds: 20);
      await enter(input, InputButton.forward);
      expect(outcomes.last.result.status, ActionStatus.noOp);
      expect(await policy.remaining(ProfileId.p2), Duration.zero);
      audio.queue = audio.queue!.copyWith(currentIndex: 0);
      audio.fail = true;
      await enter(input, InputButton.forward);
      expect(outcomes.last.result.status, ActionStatus.failure);
      expect(await policy.remaining(ProfileId.p2), Duration.zero);
      for (final session in sessions) {
        session.dispose();
      }
      await sub.cancel();
      await dispatcher.dispose();
      await policy.dispose();
      await assignments.dispose();
      await profiles.dispose();
    },
  );
}
