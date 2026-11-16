import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/skill.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import '../../helpers/skill_fakes.dart';

final class DeclaredSkill extends SkillDefinition {
  final instances = <DeclaredRuntime>[];
  @override
  SkillId get id => SkillId('declared');
  @override
  String get label => 'Declared';
  @override
  String get summary => 'Test';
  @override
  String get description => 'Test';
  @override
  PlayerScope get decisionScope => PlayerScope.all;
  @override
  List<SkillListener> get listeners => [
    SkillListener('equip', SkillTrigger.equipped),
    SkillListener('release', SkillTrigger.unequipped),
    SkillListener('watch', SkillTrigger.playbackObserved),
    SkillListener(
      'others',
      SkillTrigger.actionSucceeded,
      scope: PlayerScope.others,
    ),
    SkillListener(
      'disabled',
      SkillTrigger.actionSucceeded,
      initiallyActive: false,
    ),
  ];
  @override
  SkillRuntime createRuntime() {
    final runtime = DeclaredRuntime();
    instances.add(runtime);
    return runtime;
  }
}

final class DeclaredRuntime extends SkillRuntime {
  static const count = SkillStateKey<int>('count');
  final calls = <String>[];
  @override
  SkillReaction onListener(
    String key,
    SkillRuntimeEvent event,
    SkillContext context,
  ) {
    calls.add('$key:${context.owner}:${context.actor}');
    state.write(count, (state.read(count) ?? 0) + 1);
    return SkillReaction.none;
  }

  @override
  SkillActionBlock? decide(
    SkillTarget target,
    SkillContext context,
    String requestId,
  ) => SkillActionBlock('Global test', effort: Effort(90));
}

void main() {
  test(
    'named activation, global scope, lifecycle and typed state isolation',
    () async {
      final definition = DeclaredSkill();
      final assignments = await SkillAssignmentRepository.open(
        MemorySkills(),
        profileExists: (_) => true,
        definitions: [definition],
      );
      final policy = SkillPolicy(
        assignments: assignments,
        clock: FakeSkillClock(),
        definitions: [definition],
        scheduleTimers: false,
      );
      final generations = StreamController<int>.broadcast(sync: true);
      policy.observeSessions(generations.stream, 0);
      addTearDown(() async {
        await policy.dispose();
        await assignments.dispose();
        await generations.close();
      });
      await assignments.setAssigned(ProfileId.p1, definition.id, true);
      await policy.synchronize();
      final first = definition.instances.last;
      expect(first.calls, ['equip:p1:null']);
      expect(first.state.read(DeclaredRuntime.count), 1);
      expect(
        () => first.setListenerActive('unknown', true),
        throwsArgumentError,
      );
      final request = PlayerActionRequest(
        requestId: 'p2',
        binding: ActionBinding(ProfileId.p2, PlayerAction.nextTrack, const [
          Stroke(InputButton.forward, StrokeKind.tap),
        ]),
        recognizedAt: Duration.zero,
      );
      expect(await policy.denialFor(request), 'Global test');
      await policy.recordSuccess(
        request,
        const CommandResult(ActionStatus.success, 'Done'),
      );
      expect(first.calls.last, 'others:p1:p2');
      first.setListenerActive('others', false);
      await policy.recordSuccess(
        PlayerActionRequest(
          requestId: 'p2-again',
          binding: request.binding,
          recognizedAt: Duration.zero,
        ),
        const CommandResult(ActionStatus.success, 'Done'),
      );
      expect(first.calls.length, 2);
      await assignments.setAssigned(ProfileId.p1, definition.id, false);
      await policy.synchronize();
      expect(first.calls.last, 'release:p1:null');
      expect(first.state.read(DeclaredRuntime.count), isNull);
      await assignments.setAssigned(ProfileId.p2, definition.id, true);
      await policy.synchronize();
      final second = definition.instances.last;
      expect(second, isNot(same(first)));
      expect(second.calls, ['equip:p2:null']);
      generations.add(1);
      await pumpEventQueue();
      await policy.synchronize();
      expect(second.state.read(DeclaredRuntime.count), isNull);
      expect(definition.instances.last.calls, ['equip:p2:null']);
    },
  );

  test('typed keys cannot leak between stores or same-name declarations', () {
    final a = SkillStateStore();
    final b = SkillStateStore();
    final first = SkillStateKey<int>('same');
    final second = SkillStateKey<String>('same');
    a.write(first, 90);
    a.write(second, 'locked');
    expect(a.read(first), 90);
    expect(a.read(second), 'locked');
    expect(b.read(first), isNull);
    a.clear();
    expect(a.read(first), isNull);
  });
}
