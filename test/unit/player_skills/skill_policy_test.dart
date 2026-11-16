import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/skills/registry.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/skill_controls.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import '../../helpers/skill_fakes.dart';
import '../../helpers/probe_skill.dart';
import 'package:troona/skills/skill.dart';

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

  test('live effects lock assignment; expired cleanup permits edits', () async {
    var cleaned = 0;
    final handle = EffectHandle(
      id: 'effect',
      deadline: const Duration(seconds: 5),
      origin: SkillOrigin(
        owner: 'p2',
        skillKey: 'skip-recovery',
        invocationId: 'call',
        sessionId: 'playback-0',
      ),
    );
    policy.effects.register(handle, () async {
      cleaned++;
    }, Duration.zero);
    await expectLater(
      controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false),
      throwsA(isA<SkillCooldown>()),
    );
    clock.elapsed = const Duration(seconds: 5);
    await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
    expect(cleaned, 1);
    expect(
      assignments.catalog.has(ProfileId.p2, SkillId.skipRecovery),
      isFalse,
    );
  });

  test(
    'session replacement revokes effects and old success cannot affect new session',
    () async {
      final generations = StreamController<int>.broadcast(sync: true);
      policy.observeSessions(generations.stream, 0);
      var cleaned = 0;
      policy.effects.register(
        EffectHandle(
          id: 'effect',
          deadline: const Duration(seconds: 5),
          origin: SkillOrigin(
            owner: 'p2',
            skillKey: 'skip-recovery',
            invocationId: 'call',
            sessionId: 'playback-0',
          ),
        ),
        () async {
          cleaned++;
        },
        Duration.zero,
      );
      commands.gate = Completer<void>();
      final pending = dispatcher.dispatch(request(ProfileId.p2));
      await Future<void>.delayed(Duration.zero);
      generations.add(1);
      commands.gate!.complete();
      final result = await pending;
      await dispatcher.runOrdered(() async {});
      expect(result.result.succeeded, isTrue);
      expect(cleaned, 1);
      expect(await policy.remaining(ProfileId.p2), Duration.zero);
      await generations.close();
    },
  );

  test(
    'code-defined effort overcomes weaker blocks, never ties or invalid bindings',
    () async {
      final definition = ProbeSkill();
      definition.runtime.denial = 'Blocked';
      definition.runtime.blockEffort = Effort(60);
      final effortPolicy = SkillPolicy(
        assignments: assignments,
        clock: clock,
        definitions: [definition],
      );
      final effortDispatcher = PlayerActionDispatcher(
        playback: commands,
        catalog: () => profiles.catalog,
        abilities: effortPolicy,
      );
      Future<PlayerActionOutcome> attempt(
        Effort effort, {
        ActionBinding? binding,
      }) => effortDispatcher.dispatch(
        PlayerActionRequest(
          requestId: '${sequence++}',
          binding:
              binding ??
              profiles.catalog.bindingFor(
                ProfileId.p2,
                PlayerAction.nextTrack,
              )!,
          recognizedAt: Duration.zero,
          effort: effort,
        ),
      );
      expect((await attempt(Effort.normal)).result.status, ActionStatus.denied);
      expect((await attempt(Effort(60))).result.status, ActionStatus.denied);
      expect((await attempt(Effort(80))).result.status, ActionStatus.success);
      definition.runtime.blockEffort = Effort.maximum;
      expect(
        (await attempt(Effort.maximum)).result.status,
        ActionStatus.denied,
      );
      definition.runtime.blockEffort = Effort.minimum;
      expect(
        (await attempt(Effort.minimum)).result.status,
        ActionStatus.denied,
      );
      expect((await attempt(Effort(0))).result.status, ActionStatus.success);
      definition.runtime.denial = null;
      expect(
        (await attempt(Effort.minimum)).result.status,
        ActionStatus.success,
      );
      expect(
        (await attempt(
          Effort.maximum,
          binding: ActionBinding(ProfileId.p2, PlayerAction.nextTrack, [
            const Stroke(InputButton.forward, StrokeKind.hold),
          ]),
        )).result.status,
        ActionStatus.denied,
      );
      expect(commands.calls.length, 3);
      await effortPolicy.dispose();
      await effortDispatcher.dispose();
    },
  );

  test('owner cooldown, other players/actions and exact deadline', () async {
    expect(
      (await dispatcher.dispatch(request(ProfileId.p2))).result.status,
      ActionStatus.success,
    );
    clock.elapsed = const Duration(seconds: 5);
    final denied = await dispatcher.dispatch(request(ProfileId.p2));
    expect(denied.result.status, ActionStatus.denied);
    expect(denied.result.message, contains('Skip Recovery · 5s'));
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
    'policy delegates every action to the registered runtime and filters assignments and failures',
    () async {
      final definition = ProbeSkill();
      final adapter = SkillPolicy(
        assignments: assignments,
        clock: clock,
        definitions: [definition],
      );
      addTearDown(adapter.dispose);
      clock.elapsed = const Duration(seconds: 7);
      for (final action in PlayerAction.values) {
        final event = PlayerActionRequest(
          requestId: action.name,
          binding: ActionBinding(ProfileId.p2, action, const [
            Stroke(InputButton.forward, StrokeKind.tap),
          ]),
          recognizedAt: Duration.zero,
        );
        await adapter.denialFor(event);
        await adapter.recordSuccess(
          event,
          const CommandResult(ActionStatus.noOp, 'No change'),
        );
        await adapter.recordSuccess(
          event,
          const CommandResult(ActionStatus.failure, 'Failed'),
        );
        expect(
          definition.runtime.successes.length,
          definition.runtime.checks.length - 1,
        );
        await adapter.recordSuccess(
          event,
          const CommandResult(ActionStatus.success, 'Done'),
        );
        final received = definition.runtime.successes.last;
        expect(received.action.name, action.name);
        expect(received.playerId, 'p2');
        expect(received.requestId, action.name);
        expect(received.elapsed, const Duration(seconds: 7));
      }
      definition.runtime.denial = 'Probe denial';
      expect(await adapter.denialFor(request(ProfileId.p2)), 'Probe denial');
      final count = definition.runtime.checks.length;
      expect(await adapter.denialFor(request(ProfileId.p1)), isNull);
      expect(definition.runtime.checks.length, count);
      definition.runtime.recovery = const Duration(seconds: 4);
      expect(
        (await adapter.recoveryFor(ProfileId.p2))!.definition.label,
        'Probe skill',
      );
      expect(await adapter.remaining(ProfileId.p1), Duration.zero);
    },
  );
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
    'exclusive ownership cannot be transferred until owner recovery ends',
    () async {
      await dispatcher.dispatch(request(ProfileId.p2));
      clock.elapsed = const Duration(seconds: 3);
      await expectLater(
        controls.setAssigned(ProfileId.p1, SkillId.skipRecovery, true),
        throwsA(isA<SkillAlreadyAssigned>()),
      );
      await expectLater(
        controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false),
        throwsA(isA<SkillCooldown>()),
      );
      await dispatcher.dispatch(request(ProfileId.p1));
      expect(await policy.remaining(ProfileId.p2), const Duration(seconds: 7));
      expect(await policy.remaining(ProfileId.p1), Duration.zero);
      clock.elapsed = const Duration(seconds: 10);
      await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      await controls.setAssigned(ProfileId.p1, SkillId.skipRecovery, true);
      await dispatcher.dispatch(request(ProfileId.p1));
      expect(await policy.remaining(ProfileId.p1), const Duration(seconds: 10));
      expect(assignments.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p1);
    },
  );
  test('failed assignment does not poison ordered action processing', () async {
    await controls.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
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
