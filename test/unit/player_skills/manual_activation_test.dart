import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/effective_bindings.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/manual_skill.dart';
import '../../helpers/skill_fakes.dart';

class _InputClock implements InputClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  CancelInputTimer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback).cancel;
}

void main() {
  const tap = Stroke(InputButton.forward, StrokeKind.tap);
  const hold = Stroke(InputButton.backward, StrokeKind.hold);
  late ProfileRepository profiles;
  late SkillAssignmentRepository assignments;
  late SkillPolicy policy;
  late EffectiveBindings effective;
  late PlayerActionDispatcher dispatcher;
  late ProfileControls controls;
  late ManualTestSkill skill;
  late SkillCommands playback;
  late _InputClock inputClock;
  setUp(() async {
    profiles = await ProfileRepository.open(MemoryProfiles());
    await profiles.addProfile();
    await profiles.setBinding(ProfileId.p1, PlayerAction.nextTrack, [tap]);
    await profiles.setSkillMacro(ProfileId.p2, 'skip-recovery', [tap, hold]);
    assignments = await SkillAssignmentRepository.open(
      MemorySkills(),
      profileExists: profiles.catalog.names.containsKey,
    );
    await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
    skill = ManualTestSkill();
    policy = SkillPolicy(
      assignments: assignments,
      clock: FakeSkillClock(),
      definitions: [skill],
    );
    effective = EffectiveBindings(
      profiles: profiles,
      macroEnabled: policy.macroEnabled,
      availabilityChanges: assignments.changes.map((_) {}),
    );
    playback = SkillCommands();
    dispatcher = PlayerActionDispatcher(
      playback: playback,
      catalog: () => effective.catalog,
      abilities: policy,
    );
    inputClock = _InputClock();
    controls = ProfileControls(
      profiles: profiles,
      dispatcher: dispatcher,
      effective: effective,
      clock: inputClock,
    );
  });
  tearDown(() async {
    await effective.dispose();
    await policy.dispose();
    await dispatcher.dispose();
    await assignments.dispose();
    await profiles.dispose();
  });

  void enter(ComboInput input) {
    input.down(InputButton.forward, 1);
    inputClock.elapsed += const Duration(milliseconds: 40);
    input.up(1);
    inputClock.elapsed += const Duration(milliseconds: 70);
    input.down(InputButton.backward, 2);
    inputClock.elapsed += const Duration(milliseconds: 650);
    input.up(2);
  }

  test(
    'longer manual macro wins, retains timing/owner/effort, and never reports playback success',
    () async {
      final outcome = dispatcher.outcomes.first;
      final input = controls.createInput();
      enter(input);
      final result = await outcome;
      expect(result.result.status, ActionStatus.success);
      expect(result.request.profile, ProfileId.p2);
      expect(result.request.catalogRevision, effective.catalog.revision);
      expect(result.request.observations.length, 2);
      expect(
        result.request.observations.last.gapBefore,
        const Duration(milliseconds: 70),
      );
      expect(result.request.effort, Effort(80));
      final event = skill.runtime.events.single as SkillManualActivation;
      expect(event.observations.last.stroke, SkillStroke.backwardHold);
      expect(event.observations.last.upAt, const Duration(milliseconds: 760));
      expect(skill.runtime.contexts.single.actor, 'p2');
      expect(playback.calls, isEmpty);
      await dispatcher.dispatch(result.request);
      expect(skill.runtime.events.length, 1);
      input.dispose();
    },
  );

  test(
    'recording and practice cannot activate; unequipping removes executable reservation only',
    () async {
      for (final mode in [InputMode.recording, InputMode.practice]) {
        final input = controls.createInput(mode: mode);
        enter(input);
        await dispatcher.runOrdered(() async {});
        expect(skill.runtime.events, isEmpty);
        input.dispose();
      }
      await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      expect(effective.catalog.macros, isEmpty);
      expect(profiles.catalog.macros, hasLength(1));
      await expectLater(
        profiles.setBinding(ProfileId.p1, PlayerAction.stop, [tap, hold]),
        throwsA(isA<BindingConflict>()),
      );
      await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
      expect(effective.catalog.macros, hasLength(1));
    },
  );

  test(
    'reassignment denies queued old-owner activation and publishes a new revision',
    () async {
      final gate = Completer<void>();
      final waiting = dispatcher.runOrdered(() => gate.future);
      final outcome = dispatcher.outcomes.first;
      final input = controls.createInput();
      enter(input);
      final oldRevision = effective.catalog.revision;
      await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      await assignments.setAssigned(ProfileId.p1, SkillId.skipRecovery, true);
      expect(effective.catalog.revision, greaterThan(oldRevision));
      gate.complete();
      await waiting;
      expect((await outcome).result.status, ActionStatus.denied);
      expect(skill.runtime.events, isEmpty);
      expect(playback.calls, isEmpty);
      input.dispose();
    },
  );

  test(
    'catalog replacement cancels pending prefix without replaying stale release',
    () async {
      final input = controls.createInput();
      final subscription = controls.changes.listen(input.replaceCatalog);
      input.down(InputButton.forward, 1);
      input.up(1);
      expect(input.waitingForContinuation, isTrue);
      await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      expect(input.waitingForContinuation, isFalse);
      input.up(1);
      await dispatcher.runOrdered(() async {});
      expect(playback.calls, isEmpty);
      expect(skill.runtime.events, isEmpty);
      await subscription.cancel();
      input.dispose();
    },
  );
}
