import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_catalog.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/skill_controls.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import '../../helpers/skill_fakes.dart';

void main() {
  late ProfileRepository profiles;
  late SkillAssignmentRepository assignments;
  late SkillPolicy policy;
  late PlayerActionDispatcher dispatcher;
  late SkillControls controls;
  late FakeSkillClock clock;
  late SkillCommands commands;
  late MemorySkills store;
  var sequence = 0;
  PlayerActionRequest request(
    ProfileId profile, [
    PlayerAction action = PlayerAction.nextTrack,
  ]) => PlayerActionRequest(
    requestId: '${sequence++}',
    binding: profiles.catalog.bindingFor(profile, action)!,
    recognizedAt: Duration.zero,
  );
  setUp(() async {
    profiles = await ProfileRepository.open(MemoryProfiles());
    await profiles.addProfile();
    await profiles.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
      const Stroke(InputButton.forward, StrokeKind.tap),
    ]);
    await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
      const Stroke(InputButton.backward, StrokeKind.hold),
    ]);
    await profiles.setBinding(ProfileId.p2, PlayerAction.togglePlayback, [
      const Stroke(InputButton.pause, StrokeKind.tap),
    ]);
    store = MemorySkills();
    assignments = await SkillAssignmentRepository.open(
      store,
      profileExists: profiles.catalog.names.containsKey,
    );
    await assignments.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
    clock = FakeSkillClock();
    commands = SkillCommands();
    policy = SkillPolicy(assignments: assignments, clock: clock);
    dispatcher = PlayerActionDispatcher(
      playback: commands,
      catalog: () => profiles.catalog,
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
    await assignments.dispose();
    await profiles.dispose();
  });

  test('owner cooldown, other players/actions and exact deadline', () async {
    expect(
      (await dispatcher.dispatch(request(ProfileId.p2))).result.status,
      ActionStatus.success,
    );
    clock.elapsed = const Duration(seconds: 5);
    final denied = await dispatcher.dispatch(request(ProfileId.p2));
    expect(denied.result.status, ActionStatus.denied);
    expect(denied.result.message, contains('P2 · Skip Recovery · 5s'));
    expect(
      (await dispatcher.dispatch(request(ProfileId.p1))).result.succeeded,
      isTrue,
    );
    expect(
      (await dispatcher.dispatch(
        request(ProfileId.p2, PlayerAction.togglePlayback),
      )).result.succeeded,
      isTrue,
    );
    clock.elapsed = const Duration(milliseconds: 9999);
    expect(
      (await dispatcher.dispatch(request(ProfileId.p2))).result.status,
      ActionStatus.denied,
    );
    clock.elapsed = const Duration(seconds: 10);
    expect(
      (await dispatcher.dispatch(request(ProfileId.p2))).result.succeeded,
      isTrue,
    );
    expect(commands.calls.length, 4);
  });
  test(
    'queued request and assignment observe success completion, not recognition time',
    () async {
      commands.gate = Completer<void>();
      final first = dispatcher.dispatch(request(ProfileId.p2));
      final second = dispatcher.dispatch(request(ProfileId.p2));
      final edit = expectLater(
        controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false),
        throwsA(isA<SkillCooldown>()),
      );
      await pumpEventQueue();
      expect(commands.calls.length, 1);
      clock.elapsed = const Duration(seconds: 20);
      commands.gate!.complete();
      expect((await first).result.succeeded, isTrue);
      expect((await second).result.status, ActionStatus.denied);
      await edit;
      expect(await policy.remaining(ProfileId.p2), const Duration(seconds: 10));
      expect(
        assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
        isTrue,
      );
    },
  );
  test(
    'duplicate request and duplicate success do not move the deadline',
    () async {
      final event = request(ProfileId.p2);
      await dispatcher.dispatch(event);
      clock.elapsed = const Duration(seconds: 3);
      await dispatcher.dispatch(event);
      await policy.recordSuccess(event, commands.result);
      expect(await policy.remaining(ProfileId.p2), const Duration(seconds: 7));
      expect(commands.calls.length, 1);
    },
  );
  test(
    'failure and no-op do not start recovery; assignments can then change',
    () async {
      for (final status in [ActionStatus.failure, ActionStatus.noOp]) {
        commands.result = CommandResult(status, 'No change');
        await dispatcher.dispatch(request(ProfileId.p2));
        expect(await policy.remaining(ProfileId.p2), Duration.zero);
      }
      await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      expect(
        assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
        isFalse,
      );
    },
  );
  test(
    'renaming, rebinding and background time preserve identity; new policy starts fresh',
    () async {
      await dispatcher.dispatch(request(ProfileId.p2));
      await profiles.rename(ProfileId.p2, 'Ken');
      await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
        const Stroke(InputButton.pause, StrokeKind.hold),
      ]);
      expect(
        (await dispatcher.dispatch(request(ProfileId.p2))).result.status,
        ActionStatus.denied,
      );
      clock.elapsed = const Duration(seconds: 12);
      expect(await policy.remaining(ProfileId.p2), Duration.zero);
      expect(commands.calls.length, 1); // Expiration never replays.
      await dispatcher.dispatch(request(ProfileId.p2));
      final fresh = SkillPolicy(assignments: assignments, clock: clock);
      expect(await fresh.remaining(ProfileId.p2), Duration.zero);
      expect(
        assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
        isTrue,
      );
      await fresh.dispose();
    },
  );
  test(
    'independent deadlines and another player assignment remain editable',
    () async {
      await dispatcher.dispatch(request(ProfileId.p2));
      clock.elapsed = const Duration(seconds: 3);
      await controls.setAssigned(ProfileId.p1, SkillId.skipRecovery, true);
      await dispatcher.dispatch(request(ProfileId.p1));
      expect(await policy.remaining(ProfileId.p2), const Duration(seconds: 7));
      expect(await policy.remaining(ProfileId.p1), const Duration(seconds: 10));
      clock.elapsed = const Duration(seconds: 10);
      await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      expect(await policy.remaining(ProfileId.p1), const Duration(seconds: 3));
    },
  );
  test('failed assignment does not poison ordered action processing', () async {
    store.fail = true;
    await expectLater(
      controls.setAssigned(ProfileId.p1, SkillId.skipRecovery, true),
      throwsStateError,
    );
    expect(
      assignments.catalog.has(ProfileId.p1, SkillId.skipRecovery),
      isFalse,
    );
    expect(
      (await dispatcher.dispatch(request(ProfileId.p1))).result.succeeded,
      isTrue,
    );
  });
}
