import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/effective_bindings.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/scripted_skill.dart';
import '../../helpers/skill_fakes.dart';

class GatedProfiles extends MemoryProfiles {
  Completer<void>? gate;
  @override
  Future<void> write(String value) async {
    await gate?.future;
    await super.write(value);
  }
}

void main() {
  const forward = Stroke(InputButton.forward, StrokeKind.tap);
  const back = Stroke(InputButton.backward, StrokeKind.tap);
  const hold = Stroke(InputButton.backward, StrokeKind.hold);
  late GatedProfiles store;
  late ProfileRepository profiles;
  late SkillAssignmentRepository assignments;
  late EffectiveBindings effective;
  late SkillPolicy policy;
  late PlayerActionDispatcher dispatcher;
  late FakeSkillClock clock;
  late SkillCommands playback;
  late ScriptedSkill skill;
  var sequence = 0;
  var replacements = <ComboReplacement>[];
  ComboReplacement replacement(
    String player,
    SkillAction action,
    List<SkillStroke> strokes,
  ) => ComboReplacement(player, action, SkillCombo(strokes));
  setUp(() async {
    store = GatedProfiles();
    profiles = await ProfileRepository.open(store);
    await profiles.addProfile();
    await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [forward]);
    await profiles.setSkillMacro(ProfileId.p1, 'twist', [
      const Stroke(InputButton.pause, StrokeKind.tap),
    ]);
    skill = ScriptedSkill(
      'twist',
      react: (event, context) => event is SkillManualActivation
          ? SkillReaction(
              requests: [
                OverrideCombos(
                  '${event.id}:override',
                  replacements: replacements,
                  lifetime: const Duration(seconds: 5),
                ),
              ],
            )
          : SkillReaction.none,
    );
    assignments = await SkillAssignmentRepository.open(
      MemorySkills(),
      profileExists: (p) => profiles.catalog.names.containsKey(p),
      definitions: [skill],
    );
    await assignments.setAssigned(ProfileId.p1, skill.id, true);
    clock = FakeSkillClock();
    policy = SkillPolicy(
      assignments: assignments,
      clock: clock,
      definitions: [skill],
      scheduleTimers: false,
    );
    effective = EffectiveBindings(
      profiles: profiles,
      macroEnabled: policy.macroEnabled,
    );
    policy.bindEffectiveBindings(effective);
    playback = SkillCommands();
    dispatcher = PlayerActionDispatcher(
      playback: playback,
      abilities: policy,
      catalog: () => effective.catalog,
    );
    replacements = [
      replacement('p2', SkillAction.nextTrack, [SkillStroke.backwardTap]),
    ];
  });
  tearDown(() async {
    await policy.dispose();
    await effective.dispose();
    await dispatcher.dispose();
    await assignments.dispose();
    await profiles.dispose();
  });
  Future<CapabilityResult> apply() async {
    final outcome = await policy.coordinator.invoke(
      definition: skill,
      runtime: skill.runtime,
      event: SkillManualActivation('event-${sequence++}', [
        SkillStrokeObservation(
          stroke: SkillStroke.pauseTap,
          downAt: Duration.zero,
          upAt: const Duration(milliseconds: 100),
          gapBefore: Duration.zero,
        ),
      ]),
      origin: SkillOrigin(
        owner: 'p1',
        skillKey: 'twist',
        invocationId: 'invoke-$sequence',
        sessionId: 'playback-0',
      ),
      context: SkillContext(
        sessionId: 'playback-0',
        owner: 'p1',
        actor: 'p1',
        elapsed: clock.elapsed,
        players: ['p1', 'p2'],
        support: policy.coordinator.adapters.keys,
      ),
    );
    return outcome.results.single;
  }

  test(
    'override keeps attribution, base edits persist and exact expiry restores latest save',
    () async {
      final before = store.document;
      expect((await apply()).status, CapabilityStatus.applied);
      expect(store.document, before);
      expect(
        effective.catalog
            .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
            .strokes,
        [back],
      );
      expect(
        profiles.catalog
            .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
            .strokes,
        [forward],
      );
      final controls = ProfileControls(
        profiles: profiles,
        dispatcher: dispatcher,
        effective: effective,
      );
      final input = controls.createInput();
      final outcome = dispatcher.outcomes.first;
      input.semanticPress(InputButton.backward);
      expect((await outcome).request.profile, ProfileId.p2);
      expect(
        skill.runtime.contexts.last.bindings,
        isEmpty,
      ); // Explicit test invocation supplied no snapshot.
      await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [hold]);
      expect(
        effective.catalog
            .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
            .strokes,
        [back],
      );
      clock.elapsed = const Duration(seconds: 5);
      await dispatcher.runOrdered(
        () => policy.effects.retireDue(clock.elapsed),
      );
      expect(
        effective.catalog
            .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
            .strokes,
        [hold],
      );
      expect(
        effective.temporaryFor(ProfileId.p2, PlayerAction.nextTrack),
        isNull,
      );
      expect(
        ProfileRepository.decode(
          store.document,
        ).bindingFor(ProfileId.p2, PlayerAction.nextTrack)!.strokes,
        [hold],
      );
      input.dispose();
    },
  );

  test(
    'whole batch rejects saved, dormant, batch and competing target conflicts',
    () async {
      await profiles.setSkillMacro(ProfileId.p2, 'dormant', [hold]);
      replacements = [
        replacement('p2', SkillAction.nextTrack, [SkillStroke.backwardHold]),
      ];
      expect((await apply()).status, CapabilityStatus.denied);
      replacements = [
        replacement('p1', SkillAction.previousTrack, [SkillStroke.forwardTap]),
      ];
      expect((await apply()).status, CapabilityStatus.denied);
      replacements = [
        replacement('p2', SkillAction.nextTrack, [SkillStroke.backwardTap]),
        replacement('p1', SkillAction.previousTrack, [SkillStroke.backwardTap]),
      ];
      final revision = effective.catalog.revision;
      expect((await apply()).status, CapabilityStatus.denied);
      expect(effective.catalog.revision, revision);
      expect(policy.effects.handles, isEmpty);
      replacements.removeLast();
      expect((await apply()).status, CapabilityStatus.applied);
      expect((await apply()).status, CapabilityStatus.denied);
      await expectLater(
        profiles.setSkillMacro(ProfileId.p2, 'another', [back]),
        throwsA(isA<BindingConflict>()),
      );
      await expectLater(
        profiles.setBinding(ProfileId.p1, PlayerAction.stop, [back]),
        throwsA(isA<BindingConflict>()),
      );
    },
  );

  test('override cannot collide with an in-flight persistent save', () async {
    final gate = Completer<void>();
    store.gate = gate;
    final saving = profiles.setBinding(ProfileId.p1, PlayerAction.stop, [back]);
    await Future<void>.delayed(Duration.zero);
    expect(profiles.pendingCatalog, isNotNull);
    expect((await apply()).status, CapabilityStatus.denied);
    gate.complete();
    await saving;
    expect(
      effective.catalog.bindingFor(ProfileId.p1, PlayerAction.stop)!.strokes,
      [back],
    );
  });

  test(
    'apply cancels pending prefix and expiry denies queued old-revision request',
    () async {
      await profiles.setBinding(ProfileId.p1, PlayerAction.stop, [
        forward,
        hold,
      ]);
      final controls = ProfileControls(
        profiles: profiles,
        dispatcher: dispatcher,
        effective: effective,
      );
      final input = controls.createInput();
      final sub = effective.changes.listen(input.replaceCatalog);
      input.semanticPress(InputButton.forward);
      expect(input.waitingForContinuation, isTrue);
      await apply();
      expect(input.waitingForContinuation, isFalse);
      expect(input.strokes, isEmpty);
      final request = PlayerActionRequest(
        requestId: 'queued',
        binding: effective.catalog.bindingFor(
          ProfileId.p2,
          PlayerAction.nextTrack,
        )!,
        recognizedAt: Duration.zero,
        catalogRevision: effective.catalog.revision,
      );
      final gate = Completer<void>();
      final held = dispatcher.runOrdered(() => gate.future);
      final queued = dispatcher.dispatch(request);
      clock.elapsed = const Duration(seconds: 5);
      gate.complete();
      await held;
      expect((await queued).result.status, ActionStatus.denied);
      expect(playback.calls, isEmpty);
      await sub.cancel();
      input.dispose();
    },
  );

  test(
    'revoke and session stop restore base without deleting saved input',
    () async {
      final first = await apply();
      await dispatcher.runOrdered(
        () => policy.effects.revoke(first.handle!.id),
      );
      expect(
        effective.catalog
            .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
            .strokes,
        [forward],
      );
      await apply();
      final sessions = StreamController<int>.broadcast(sync: true);
      policy.observeSessions(sessions.stream, 0);
      sessions.add(1);
      await dispatcher.runOrdered(() async {});
      expect(
        effective.catalog
            .bindingFor(ProfileId.p2, PlayerAction.nextTrack)!
            .strokes,
        [forward],
      );
      expect(policy.effects.handles, isEmpty);
      await sessions.close();
    },
  );
}
