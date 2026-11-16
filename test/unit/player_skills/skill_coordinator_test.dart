import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/player_skills/domain/effect_ledger.dart';
import 'package:troona/features/player_skills/domain/skill_coordinator.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/probe_skill.dart';
import '../../helpers/skill_fakes.dart';

final class ReactionSkill extends SkillDefinition {
  final ReactionRuntime runtime;
  final SkillFailureCleanup cleanup;
  ReactionSkill(
    this.runtime, {
    this.cleanup = SkillFailureCleanup.retainApplied,
  });
  @override
  SkillId get id => SkillId.skipRecovery;
  @override
  String get label => 'Test';
  @override
  String get summary => 'Test';
  @override
  String get description => 'Test';
  @override
  SkillRuntime createRuntime() => runtime;
  @override
  SkillFailureCleanup get failureCleanup => cleanup;
}

final class ReactionRuntime extends SkillRuntime {
  final List<CapabilityRequest> Function(String) requests;
  final results = <CapabilityResult>[];
  int events = 0;
  bool failCallback = false;
  ReactionRuntime(this.requests);
  @override
  String? denialFor(SkillEvent event) => null;
  @override
  bool recordSuccess(SkillEvent event) => false;
  @override
  Duration remaining(String playerId, Duration elapsed) => Duration.zero;
  @override
  SkillReaction onEvent(SkillRuntimeEvent event, SkillContext context) {
    events++;
    return SkillReaction(requests: requests(event.id));
  }

  @override
  void onCapabilityResult(CapabilityResult result, SkillContext context) {
    results.add(result);
    if (failCallback) throw StateError('callback');
  }
}

final class TestAdapter implements SkillCapabilityAdapter {
  final Future<AppliedCapability> Function(
    CapabilityRequest,
    SkillOrigin,
    SkillContext,
  )
  body;
  TestAdapter(this.body);
  @override
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
  ) => body(request, origin, context);
}

void main() {
  late PlayerActionDispatcher dispatcher;
  late EffectLedger ledger;
  late SkillCoordinator coordinator;
  var elapsed = Duration.zero;
  SkillContext context() => SkillContext(
    sessionId: 's',
    owner: 'p1',
    actor: 'p1',
    elapsed: elapsed,
    players: ['p1', 'p2'],
    support: SkillCapability.values,
  );
  SkillOrigin origin(String id) => SkillOrigin(
    owner: 'p1',
    skillKey: 'skip-recovery',
    invocationId: id,
    sessionId: 's',
  );
  Future<SkillInvocationOutcome> invoke(ReactionSkill skill, String id) =>
      coordinator.invoke(
        definition: skill,
        runtime: skill.runtime,
        origin: origin(id),
        context: context(),
        event: SkillActionSucceeded(
          id,
          const PlaybackSkillTarget(SkillAction.nextTrack),
        ),
      );
  EditLoopQueue edit(String id) => EditLoopQueue(
    id,
    loops: const CurrentLoop(),
    expectedRevision: 0,
    operations: [InsertSong(SongReference('song'), 'occurrence-$id')],
  );
  StartAudioMix mix(String id) => StartAudioMix(
    id,
    lifetime: const Duration(seconds: 5),
    layers: [MixLayer(kind: MixLayerKind.noise)],
  );

  setUp(() {
    elapsed = Duration.zero;
    dispatcher = PlayerActionDispatcher(
      playback: SkillCommands(),
      catalog: () => ProfileCatalog.empty(),
    );
    ledger = EffectLedger(
      now: () async => elapsed,
      runOrdered: dispatcher.runOrdered,
      scheduleTimers: false,
    );
    coordinator = SkillCoordinator(
      runOrdered: dispatcher.runOrdered,
      effects: ledger,
    );
  });
  tearDown(() async {
    await ledger.dispose();
    await dispatcher.dispose();
  });

  test(
    'same ordered queue, duplicate invocations and effects, exactly one notification',
    () async {
      final order = <String>[];
      final gate = Completer<void>();
      coordinator.adapters[SkillCapability.queueEdit] = TestAdapter((
        request,
        origin,
        context,
      ) async {
        order.add(request.effectId);
        if (request.effectId == 'first') await gate.future;
        return AppliedCapability(
          CapabilityResult(
            effectId: request.effectId,
            status: CapabilityStatus.applied,
          ),
        );
      });
      final skill = ReactionSkill(
        ReactionRuntime((id) => [edit(id == 'repeat-effect' ? 'first' : id)]),
      );
      final first = invoke(skill, 'first');
      final duplicate = invoke(skill, 'first');
      final other = dispatcher.runOrdered(() async {
        order.add('assignment');
      });
      final next = invoke(skill, 'second');
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first']);
      gate.complete();
      expect(await duplicate, same(await first));
      await other;
      await next;
      await invoke(skill, 'repeat-effect');
      expect(order, ['first', 'assignment', 'second']);
      expect(skill.runtime.results.length, 2);
      expect(skill.runtime.events, 3);
    },
  );

  test(
    'queue success stays applied when later mix fails, callback cannot create input',
    () async {
      coordinator.adapters[SkillCapability.queueEdit] = TestAdapter(
        (request, origin, context) async => AppliedCapability(
          CapabilityResult(
            effectId: request.effectId,
            status: CapabilityStatus.applied,
            appliedRevision: 1,
          ),
        ),
      );
      coordinator.adapters[SkillCapability.audioMix] = TestAdapter((
        request,
        origin,
        context,
      ) async {
        throw StateError('source unavailable');
      });
      final runtime = ReactionRuntime((_) => [edit('insert'), mix('mix')])
        ..failCallback = true;
      final result = await invoke(ReactionSkill(runtime), 'call');
      expect(result.results.map((r) => r.status), [
        CapabilityStatus.applied,
        CapabilityStatus.failed,
      ]);
      expect(result.error, contains('notification'));
      expect(runtime.events, 1);
      expect(runtime.results.length, 2);
    },
  );

  test(
    'unsupported adapters never claim success and wrong ownership cannot invoke',
    () async {
      final skill = ReactionSkill(ReactionRuntime((_) => [mix('mix')]));
      expect(
        (await invoke(skill, 'one')).results.single.status,
        CapabilityStatus.unsupported,
      );
      final denied = await coordinator.invoke(
        definition: skill,
        runtime: skill.runtime,
        origin: SkillOrigin(
          owner: 'p2',
          skillKey: 'skip-recovery',
          invocationId: 'two',
          sessionId: 's',
        ),
        context: context(),
        event: SkillActionSucceeded(
          'two',
          const PlaybackSkillTarget(SkillAction.nextTrack),
        ),
      );
      expect(denied.error, contains('ownership'));
      expect(skill.runtime.events, 1);
    },
  );

  test(
    'fixed failure cleanup releases prior resources but preserves completed results',
    () async {
      var cleaned = 0;
      coordinator.adapters[SkillCapability.audioMix] = TestAdapter(
        (request, origin, context) async => AppliedCapability(
          CapabilityResult(
            effectId: request.effectId,
            status: CapabilityStatus.applied,
            handle: EffectHandle(
              id: 'handle',
              origin: origin,
              deadline: const Duration(seconds: 5),
            ),
          ),
          cleanup: () async {
            cleaned++;
          },
        ),
      );
      final skill = ReactionSkill(
        ReactionRuntime((_) => [mix('mix'), edit('insert')]),
        cleanup: SkillFailureCleanup.revokeInvocationEffects,
      );
      final result = await invoke(skill, 'one');
      expect(result.results.map((r) => r.status), [
        CapabilityStatus.applied,
        CapabilityStatus.unsupported,
      ]);
      expect(cleaned, 1);
      expect(ledger.handles, isEmpty);
    },
  );

  test('invalid adapter ownership is cleaned and reported failed', () async {
    var cleaned = false;
    coordinator.adapters[SkillCapability.audioMix] = TestAdapter(
      (request, call, context) async => AppliedCapability(
        CapabilityResult(
          effectId: request.effectId,
          status: CapabilityStatus.applied,
          handle: EffectHandle(
            id: 'handle',
            origin: origin('wrong-invocation'),
            deadline: const Duration(seconds: 5),
          ),
        ),
        cleanup: () async {
          cleaned = true;
        },
      ),
    );
    final result = await invoke(
      ReactionSkill(ReactionRuntime((_) => [mix('mix')])),
      'one',
    );
    expect(result.results.single.status, CapabilityStatus.failed);
    expect(cleaned, isTrue);
    expect(ledger.handles, isEmpty);
  });

  test('extended default runtime still delegates successful legacy hooks', () {
    final runtime = ProbeSkillRuntime();
    final reaction = runtime.onEvent(
      SkillActionSucceeded(
        'ok',
        const PlaybackSkillTarget(SkillAction.previousTrack),
      ),
      context(),
    );
    expect(reaction.stateChanged, isTrue);
    expect(runtime.successes.single.playerId, 'p1');
  });
}
