import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/skill.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import '../../helpers/skill_fakes.dart';

class ObserveCombos extends SkillDefinition {
  final runtime = ObserveRuntime();
  @override
  SkillId get id => SkillId('observe-combos');
  @override
  String get label => 'Observe';
  @override
  String get summary => 'Test';
  @override
  String get description => 'Test';
  @override
  List<SkillListener> get listeners => [
    SkillListener('any', SkillTrigger.comboObserved, scope: PlayerScope.all),
    SkillListener(
      'others',
      SkillTrigger.comboObserved,
      scope: PlayerScope.others,
    ),
    SkillListener('owner', SkillTrigger.comboObserved),
    SkillListener(
      'filtered',
      SkillTrigger.comboObserved,
      scope: PlayerScope.all,
      combo: SkillCombo([SkillStroke.forwardTap]),
    ),
    SkillListener(
      'disabled',
      SkillTrigger.comboObserved,
      scope: PlayerScope.all,
      initiallyActive: false,
    ),
    SkillListener('playback', SkillTrigger.playbackObserved),
  ];
  @override
  SkillRuntime createRuntime() => runtime;
}

class ObserveRuntime extends SkillRuntime {
  final calls = <String>[];
  @override
  SkillReaction onListener(
    String key,
    SkillRuntimeEvent event,
    SkillContext context,
  ) {
    calls.add('$key:${context.owner}:${context.actor}');
    return SkillReaction.none;
  }
}

void main() {
  test(
    'optional filters preserve player scope, activation and event type',
    () async {
      final skill = ObserveCombos();
      final assignments = await SkillAssignmentRepository.open(
        MemorySkills(),
        profileExists: (_) => true,
        definitions: [skill],
      );
      await assignments.setAssigned(ProfileId.p1, skill.id, true);
      final bindings = [
        for (final profile in [ProfileId.p1, ProfileId.p2])
          ActionBinding(profile, PlayerAction.nextTrack, const [
            Stroke(InputButton.forward, StrokeKind.tap),
          ]),
        ActionBinding(ProfileId.p2, PlayerAction.previousTrack, const [
          Stroke(InputButton.backward, StrokeKind.tap),
        ]),
      ];
      // Each dispatch supplies its own valid catalog; ownership remains explicit.
      var active = bindings.first;
      ProfileCatalog catalog() => ProfileCatalog(
        names: {ProfileId.p1: 'P1', ProfileId.p2: 'P2'},
        bindings: [active],
        timing: RecognitionTiming(),
      );
      final policy = SkillPolicy(
        assignments: assignments,
        clock: FakeSkillClock(),
        definitions: [skill],
        scheduleTimers: false,
      );
      final dispatcher = PlayerActionDispatcher(
        playback: SkillCommands(),
        catalog: catalog,
        abilities: policy,
      );
      addTearDown(() async {
        await dispatcher.dispose();
        await policy.dispose();
        await assignments.dispose();
      });
      Future<void> send(int index) async {
        active = bindings[index];
        skill.runtime.calls.clear();
        await dispatcher.dispatch(
          PlayerActionRequest(
            requestId: '$index',
            binding: active,
            recognizedAt: Duration.zero,
            observations: [
              StrokeObservation(
                active.strokes.single,
                Duration.zero,
                const Duration(milliseconds: 50),
                null,
              ),
            ],
          ),
        );
      }

      await send(1);
      expect(skill.runtime.calls, [
        'any:p1:p2',
        'others:p1:p2',
        'filtered:p1:p2',
      ]);
      await send(0);
      expect(skill.runtime.calls, [
        'any:p1:p1',
        'owner:p1:p1',
        'filtered:p1:p1',
      ]);
      skill.runtime.setListenerActive('any', false);
      await send(2);
      expect(skill.runtime.calls, ['others:p1:p2']);
    },
  );
}
