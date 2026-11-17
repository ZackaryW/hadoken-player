import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import '../../helpers/probe_skill.dart';
import '../../helpers/skill_fakes.dart';

class BookkeepingCommands extends SkillCommands {
  bool throws = false;
  @override
  Future<CommandResult> execute(PlayerAction action) async {
    if (throws) throw StateError('Playback failed');
    return super.execute(action);
  }
}

void main() {
  test(
    'all terminal outcomes release execution budgets and session captures',
    () async {
      final definition = ProbeSkill();
      final assignments = await SkillAssignmentRepository.open(
        MemorySkills(),
        profileExists: (_) => true,
        definitions: [definition],
      );
      await assignments.setAssigned(ProfileId.p1, definition.id, true);
      final binding = ActionBinding(
        ProfileId.p1,
        PlayerAction.nextTrack,
        const [Stroke(InputButton.forward, StrokeKind.tap)],
      );
      final catalog = ProfileCatalog(
        names: {ProfileId.p1: 'P1'},
        bindings: [binding],
        timing: RecognitionTiming(),
      );
      final policy = SkillPolicy(
        assignments: assignments,
        clock: FakeSkillClock(),
        definitions: [definition],
        scheduleTimers: false,
      );
      final playback = BookkeepingCommands();
      final dispatcher = PlayerActionDispatcher(
        playback: playback,
        catalog: () => catalog,
        abilities: policy,
      );
      addTearDown(() async {
        await dispatcher.dispose();
        await policy.dispose();
        await assignments.dispose();
      });
      for (var i = 0; i < 300; i++) {
        final status = ActionStatus.values[i % ActionStatus.values.length];
        playback.result = CommandResult(status, status.name);
        definition.runtime.denial = status == ActionStatus.denied
            ? 'Blocked'
            : null;
        playback.throws = status == ActionStatus.failure;
        final result = await dispatcher.dispatch(
          PlayerActionRequest(
            requestId: '$i',
            binding: binding,
            recognizedAt: Duration.zero,
            observations: [
              StrokeObservation(
                binding.strokes.single,
                Duration.zero,
                const Duration(milliseconds: 50),
                null,
              ),
            ],
          ),
        );
        expect(result.result.status, status);
        expect(
          policy.pendingExecutionCount,
          0,
          reason: 'terminal $status must release state',
        );
      }
      expect(dispatcher.completedRequestCount, 256);
      expect(dispatcher.pendingRequestCount, 0);
    },
  );
}
