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
import '../../helpers/scripted_skill.dart';
import '../../helpers/skill_fakes.dart';

void main() {
  late ProfileRepository profiles;
  late SkillAssignmentRepository assignments;
  late SkillPolicy policy;
  late PlayerActionDispatcher dispatcher;
  late EffectiveBindings effective;
  late FakeSkillClock clock;
  late SkillCommands playback;
  var sequence = 0;
  Future<void> start(List<ScriptedSkill> skills) async {
    profiles = await ProfileRepository.open(MemoryProfiles());
    await profiles.addProfile();
    await profiles.addProfile();
    await profiles.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
      const Stroke(InputButton.forward, StrokeKind.tap),
    ]);
    assignments = await SkillAssignmentRepository.open(
      MemorySkills(),
      profileExists: profiles.catalog.names.containsKey,
      definitions: skills,
    );
    for (var i = 0; i < skills.length; i++) {
      final owner = i == 0 ? ProfileId.p1 : ProfileId.p3;
      await assignments.setAssigned(owner, skills[i].id, true);
      await profiles.setSkillMacro(owner, skills[i].id.key, [
        Stroke(
          i == 0 ? InputButton.pause : InputButton.backward,
          StrokeKind.tap,
        ),
      ]);
    }
    clock = FakeSkillClock();
    playback = SkillCommands();
    policy = SkillPolicy(
      assignments: assignments,
      clock: clock,
      definitions: skills,
      scheduleTimers: false,
    );
    effective = EffectiveBindings(
      profiles: profiles,
      macroEnabled: policy.macroEnabled,
      availabilityChanges: assignments.changes.map((_) {}),
    );
    dispatcher = PlayerActionDispatcher(
      playback: playback,
      catalog: () => effective.catalog,
      abilities: policy,
    );
    addTearDown(() async {
      await effective.dispose();
      await policy.dispose();
      await dispatcher.dispose();
      await assignments.dispose();
      await profiles.dispose();
    });
  }

  PlayerActionRequest request(ExecutableBinding binding) => PlayerActionRequest(
    requestId: 'input-${sequence++}',
    binding: binding,
    recognizedAt: const Duration(milliseconds: 100),
    catalogRevision: effective.catalog.revision,
    effort: dispatcher.effortFor(binding),
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
  Future<PlayerActionOutcome> activate(ProfileId owner, ScriptedSkill skill) =>
      dispatcher.dispatch(
        request(effective.catalog.macroFor(owner, skill.id.key)!),
      );
  PlayerActionRequest skip() => request(
    effective.catalog.bindingFor(ProfileId.p2, PlayerAction.nextTrack)!,
  );
  ArmComboListener listen(
    String id,
    String key, {
    bool once = false,
    List<SkillStroke>? strokes,
  }) => ArmComboListener(
    id,
    listenerKey: key,
    combo: SkillCombo(strokes ?? [SkillStroke.forwardTap]),
    players: PlayerSelector(PlayerScope.others),
    lifetime: const Duration(seconds: 5),
    once: once,
  );

  for (final levels in [
    (80, 60, true),
    (60, 60, false),
    (-1, -1, false),
    (100, 100, false),
    (100, 99, true),
  ]) {
    test(
      'generated skip effort ${levels.$1} against block ${levels.$2}',
      () async {
        final guard = ScriptedSkill(
          'global-block',
          react: (event, context) => event is SkillManualActivation
              ? SkillReaction(
                  requests: [
                    RestrictActions(
                      '${event.id}:block',
                      players: PlayerSelector(PlayerScope.all),
                      actions: [
                        const PlaybackSkillTarget(SkillAction.nextTrack),
                      ],
                      lifetime: const Duration(seconds: 10),
                      effort: Effort(levels.$2),
                    ),
                  ],
                )
              : SkillReaction.none,
        );
        final skipSkill = ScriptedSkill(
          'power-skip',
          react: (event, context) => event is SkillManualActivation
              ? SkillReaction(
                  requests: [
                    ExecutePlayerAction(
                      '${event.id}:skip',
                      player: context.owner,
                      action: SkillAction.nextTrack,
                      effort: Effort(levels.$1),
                    ),
                  ],
                )
              : SkillReaction.none,
        );
        await start([guard, skipSkill]);
        await activate(ProfileId.p1, guard);
        final input = request(
          effective.catalog.macroFor(ProfileId.p3, skipSkill.id.key)!,
        );
        final outcome = await dispatcher.dispatch(input);
        expect(
          outcome.result.effects.single.status,
          levels.$3 ? CapabilityStatus.applied : CapabilityStatus.denied,
        );
        await dispatcher.dispatch(input);
        expect(playback.calls.length, levels.$3 ? 1 : 0);
        expect(
          skipSkill.runtime.events.whereType<SkillComboObserved>(),
          isEmpty,
        );
        expect(
          skipSkill.runtime.events.whereType<SkillActionSucceeded>().length,
          levels.$3 ? 1 : 0,
        );
        if (levels.$3) {
          expect(skipSkill.runtime.contexts.last.actor, 'p3');
          expect(skipSkill.runtime.contexts.last.effort, Effort(levels.$1));
        }
      },
    );
  }

  test(
    'strongest block wins, system transport bypasses, exact expiry restores ordinary skip',
    () async {
      final guard = ScriptedSkill(
        'guard',
        react: (event, context) => event is SkillManualActivation
            ? SkillReaction(
                requests: [
                  for (final level in [40, 60])
                    RestrictActions(
                      '${event.id}:$level',
                      players: PlayerSelector(PlayerScope.all),
                      actions: [
                        const PlaybackSkillTarget(SkillAction.nextTrack),
                      ],
                      lifetime: Duration(seconds: level == 60 ? 10 : 20),
                      effort: Effort(level),
                    ),
                ],
              )
            : SkillReaction.none,
      );
      await start([guard]);
      await activate(ProfileId.p1, guard);
      final denied = await dispatcher.dispatch(skip());
      expect(denied.result.status, ActionStatus.denied);
      expect(denied.result.message, contains('guard · 10s'));
      expect(playback.calls, isEmpty);
      expect(
        (await playback.execute(PlayerAction.nextTrack)).succeeded,
        isTrue,
      );
      clock.elapsed = const Duration(seconds: 10);
      expect((await dispatcher.dispatch(skip())).result.succeeded, isTrue);
      expect(policy.effects.handles.length, 1);
    },
  );

  test('manual activation has an independent effort check', () async {
    final guard = ScriptedSkill(
      'guard',
      react: (event, context) => event is SkillManualActivation
          ? SkillReaction(
              requests: [
                RestrictActions(
                  '${event.id}:activation',
                  players: PlayerSelector(PlayerScope.others),
                  actions: [ActivationSkillTarget('power')],
                  lifetime: const Duration(seconds: 10),
                  effort: Effort(60),
                ),
              ],
            )
          : SkillReaction.none,
    );
    final power = ScriptedSkill(
      'power',
      react: (event, context) => SkillReaction(
        requests: [
          ExecutePlayerAction(
            '${event.id}:skip',
            player: context.owner,
            action: SkillAction.nextTrack,
            effort: Effort.maximum,
          ),
        ],
      ),
    );
    await start([guard, power]);
    await activate(ProfileId.p1, guard);
    expect(
      (await activate(ProfileId.p3, power)).result.status,
      ActionStatus.denied,
    );
    expect(power.runtime.events, isEmpty);
    expect(playback.calls, isEmpty);
  });

  test(
    'generated success cannot recurse and actual non-success never emits success',
    () async {
      final skill = ScriptedSkill(
        'recursive',
        react: (event, context) => SkillReaction(
          requests: [
            ExecutePlayerAction(
              '${event.id}:skip',
              player: context.owner,
              action: SkillAction.nextTrack,
            ),
          ],
        ),
      );
      await start([skill]);
      expect((await activate(ProfileId.p1, skill)).result.succeeded, isTrue);
      expect(playback.calls.length, 1);
      expect(skill.runtime.results.first.status, CapabilityStatus.denied);
      expect(skill.runtime.results.first.reason, contains('recursively'));
      expect(skill.runtime.events.whereType<SkillActionSucceeded>().length, 1);
      for (final status in [
        ActionStatus.noOp,
        ActionStatus.failure,
        ActionStatus.denied,
      ]) {
        playback.result = CommandResult(status, 'Backend $status');
        final outcome = await activate(ProfileId.p1, skill);
        expect(outcome.result.effects.single.status, switch (status) {
          ActionStatus.noOp => CapabilityStatus.noOp,
          ActionStatus.denied => CapabilityStatus.denied,
          _ => CapabilityStatus.failed,
        });
        expect(
          skill.runtime.events.whereType<SkillActionSucceeded>().length,
          1,
        );
      }
    },
  );

  for (final scope in PlayerScope.values) {
    test('listener and restriction resolve $scope at application', () async {
      final skill = ScriptedSkill(
        'scoped',
        react: (event, context) => event is SkillManualActivation
            ? SkillReaction(
                requests: [
                  ArmComboListener(
                    '${event.id}:watch',
                    listenerKey: 'watch',
                    combo: SkillCombo([SkillStroke.forwardTap]),
                    players: PlayerSelector(
                      scope,
                      scope == PlayerScope.explicit ? ['p2'] : [],
                    ),
                    lifetime: const Duration(seconds: 5),
                  ),
                  RestrictActions(
                    '${event.id}:block',
                    players: PlayerSelector(
                      scope,
                      scope == PlayerScope.explicit ? ['p2'] : [],
                    ),
                    actions: [const PlaybackSkillTarget(SkillAction.nextTrack)],
                    lifetime: const Duration(seconds: 5),
                  ),
                ],
              )
            : SkillReaction.none,
      );
      await start([skill]);
      await activate(ProfileId.p1, skill);
      final outcome = await dispatcher.dispatch(skip());
      final matches = scope != PlayerScope.owner;
      expect(
        outcome.result.status,
        matches ? ActionStatus.denied : ActionStatus.success,
      );
      expect(
        skill.runtime.events.whereType<SkillComboObserved>().length,
        matches ? 1 : 0,
      );
    });
  }

  test(
    'listeners snapshot in owner/key order, preserve actor/timing and do not steal input',
    () async {
      final seen = <String>[];
      final first = ScriptedSkill(
        'first',
        react: (event, context) {
          if (event is SkillManualActivation) {
            return SkillReaction(
              requests: [
                listen('${event.id}:z', 'z'),
                listen('${event.id}:a', 'a', once: true),
              ],
            );
          }
          if (event is SkillComboObserved) {
            seen.add('${context.owner}:${event.listenerKey}:${context.actor}');
            expect(
              event.observations.single.upAt,
              const Duration(milliseconds: 100),
            );
            if (event.listenerKey == 'a') {
              return SkillReaction(
                requests: [listen('${event.id}:new', 'new')],
              );
            }
          }
          return SkillReaction.none;
        },
      );
      final other = ScriptedSkill(
        'other',
        react: (event, context) {
          if (event is SkillManualActivation) {
            return SkillReaction(
              requests: [listen('${event.id}:watch', 'watch')],
            );
          }
          if (event is SkillComboObserved) {
            seen.add('${context.owner}:${event.listenerKey}:${context.actor}');
          }
          return SkillReaction.none;
        },
      );
      await start([first, other]);
      await activate(ProfileId.p1, first);
      await activate(ProfileId.p3, other);
      final input = skip();
      final result = await dispatcher.dispatch(input);
      expect(result.result.succeeded, isTrue);
      expect(seen, ['p1:a:p2', 'p1:z:p2', 'p3:watch:p2']);
      await dispatcher.dispatch(input);
      expect(seen.length, 3);
      await dispatcher.dispatch(skip());
      expect(seen.skip(3), ['p1:new:p2', 'p1:z:p2', 'p3:watch:p2']);
      expect(playback.calls, [PlayerAction.nextTrack, PlayerAction.nextTrack]);
    },
  );

  test(
    'listener restriction reconciles before the triggering action',
    () async {
      final skill = ScriptedSkill(
        'trap',
        react: (event, context) {
          if (event is SkillManualActivation) {
            return SkillReaction(
              requests: [listen('${event.id}:watch', 'watch')],
            );
          }
          if (event is SkillComboObserved) {
            return SkillReaction(
              requests: [
                RestrictActions(
                  '${event.id}:block',
                  players: PlayerSelector(PlayerScope.explicit, [
                    context.actor!,
                  ]),
                  actions: [const PlaybackSkillTarget(SkillAction.nextTrack)],
                  lifetime: const Duration(seconds: 10),
                  effort: Effort(60),
                ),
              ],
            );
          }
          return SkillReaction.none;
        },
      );
      await start([skill]);
      await activate(ProfileId.p1, skill);
      final result = await dispatcher.dispatch(skip());
      expect(result.result.status, ActionStatus.denied);
      expect(result.result.effects.single.status, CapabilityStatus.applied);
      expect(playback.calls, isEmpty);
      expect(skill.runtime.events.whereType<SkillActionSucceeded>(), isEmpty);
    },
  );

  test('expired or revoked listeners cannot observe queued input', () async {
    final skill = ScriptedSkill(
      'watcher',
      react: (event, context) => event is SkillManualActivation
          ? SkillReaction(requests: [listen('${event.id}:watch', 'watch')])
          : SkillReaction.none,
    );
    await start([skill]);
    await activate(ProfileId.p1, skill);
    final gate = Completer<void>();
    final held = dispatcher.runOrdered(() => gate.future);
    final pending = dispatcher.dispatch(skip());
    clock.elapsed = const Duration(seconds: 5);
    gate.complete();
    await held;
    expect((await pending).result.succeeded, isTrue);
    expect(skill.runtime.events.whereType<SkillComboObserved>(), isEmpty);
    expect(policy.effects.handles, isEmpty);
    await activate(ProfileId.p1, skill);
    await dispatcher.runOrdered(
      () => policy.effects.revoke(policy.effects.handles.single.id),
    );
    await dispatcher.dispatch(skip());
    expect(skill.runtime.events.whereType<SkillComboObserved>(), isEmpty);
  });

  test(
    'listening patterns neither delay recognition nor execute in practice/recording',
    () async {
      final skill = ScriptedSkill(
        'long-watch',
        react: (event, context) => event is SkillManualActivation
            ? SkillReaction(
                requests: [
                  listen(
                    '${event.id}:watch',
                    'watch',
                    strokes: [SkillStroke.forwardTap, SkillStroke.backwardHold],
                  ),
                ],
              )
            : SkillReaction.none,
      );
      await start([skill]);
      await activate(ProfileId.p1, skill);
      final controls = ProfileControls(
        profiles: profiles,
        dispatcher: dispatcher,
        effective: effective,
      );
      for (final mode in [InputMode.practice, InputMode.recording]) {
        final input = controls.createInput(mode: mode);
        input.semanticPress(InputButton.forward);
        input.dispose();
      }
      final input = controls.createInput();
      final outcome = dispatcher.outcomes.first;
      input.semanticPress(InputButton.forward);
      expect(input.waitingForContinuation, isFalse);
      expect((await outcome).result.succeeded, isTrue);
      expect(skill.runtime.events.whereType<SkillComboObserved>(), isEmpty);
      input.semanticPress(InputButton.backward); // Unbound, no invented actor.
      await dispatcher.runOrdered(() async {});
      expect(playback.calls.length, 1);
      input.dispose();
    },
  );
}
