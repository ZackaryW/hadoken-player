import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';

class FakeCommands implements PlaybackCommands {
  final List<String> events;
  Completer<void>? gate;
  CommandResult result = const CommandResult(ActionStatus.success, 'Done');
  FakeCommands(this.events);
  @override
  Future<CommandResult> execute(PlayerAction action) async {
    events.add('play:${action.name}');
    await gate?.future;
    return result;
  }
}

class FakePolicy implements PlayerAbilityPolicy {
  final List<String> events;
  String? denial;
  Completer<void>? gate;
  bool failPost = false;
  FakePolicy(this.events);
  @override
  Future<String?> denialFor(PlayerActionRequest request) async {
    events.add('check:${request.profile.name}');
    return denial;
  }

  @override
  Future<void> recordSuccess(
    PlayerActionRequest request,
    CommandResult result,
  ) async {
    events.add('success:${request.profile.name}');
    await gate?.future;
    if (failPost) throw StateError('Skill store failed');
  }
}

void main() {
  final a = ActionBinding(ProfileId.p1, PlayerAction.nextTrack, [
    const Stroke(InputButton.forward, StrokeKind.tap),
  ]);
  final b = ActionBinding(ProfileId.p2, PlayerAction.stop, [
    const Stroke(InputButton.pause, StrokeKind.hold),
  ]);
  PlayerActionRequest request(String id, ActionBinding binding) =>
      PlayerActionRequest(
        requestId: id,
        binding: binding,
        recognizedAt: const Duration(seconds: 1),
      );
  late List<String> events;
  late FakeCommands player;
  late FakePolicy policy;
  late ProfileCatalog catalog;
  late PlayerActionDispatcher dispatcher;
  setUp(() {
    events = [];
    player = FakeCommands(events);
    policy = FakePolicy(events);
    catalog = ProfileCatalog(
      names: {for (final id in ProfileId.values) id: id.label},
      bindings: [a, b],
      timing: RecognitionTiming(),
    );
    dispatcher = PlayerActionDispatcher(
      playback: player,
      abilities: policy,
      catalog: () => catalog,
    );
  });
  tearDown(() => dispatcher.dispose());

  test(
    'completed retention is bounded without evicting pending requests',
    () async {
      player.gate = Completer<void>();
      final first = dispatcher.dispatch(request('oldest', a));
      final pending = [
        for (var i = 0; i < 300; i++) dispatcher.dispatch(request('r$i', a)),
      ];
      expect(dispatcher.pendingRequestCount, 301);
      expect(dispatcher.dispatch(request('oldest', a)), same(first));
      player.gate!.complete();
      await first;
      final outcomes = await Future.wait(pending);
      expect(dispatcher.pendingRequestCount, 0);
      expect(
        dispatcher.completedRequestCount,
        PlayerActionDispatcher.completedRequestLimit,
      );
      final calls = events.length;
      expect(
        await dispatcher.dispatch(request('r299', a)),
        same(outcomes.last),
      );
      expect(events.length, calls);
      await dispatcher.dispatch(request('oldest', a));
      expect(events.length, calls + 3);
      expect(
        dispatcher.completedRequestCount,
        PlayerActionDispatcher.completedRequestLimit,
      );
    },
  );

  test(
    'deduplicates in-flight and completed delivery, publishing only once',
    () async {
      final outcomes = <PlayerActionOutcome>[];
      final sub = dispatcher.outcomes.listen(outcomes.add);
      addTearDown(sub.cancel);
      player.gate = Completer();
      final first = dispatcher.dispatch(request('one', a));
      final duplicate = dispatcher.dispatch(request('one', a));
      expect(identical(first, duplicate), isTrue);
      player.gate!.complete();
      final result = await first;
      expect(await dispatcher.dispatch(request('one', a)), same(result));
      expect(events, ['check:p1', 'play:nextTrack', 'success:p1']);
      expect(outcomes.length, 1);
    },
  );

  test(
    'serializes through post-success before evaluating the next owner',
    () async {
      policy.gate = Completer();
      final first = dispatcher.dispatch(request('one', a));
      final second = dispatcher.dispatch(request('two', b));
      await pumpEventQueue();
      expect(events, ['check:p1', 'play:nextTrack', 'success:p1']);
      policy.gate!.complete();
      await Future.wait([first, second]);
      expect(events, [
        'check:p1',
        'play:nextTrack',
        'success:p1',
        'check:p2',
        'play:stop',
        'success:p2',
      ]);
    },
  );

  test(
    'denial, no-op and failure do not create skill successes and are deduped',
    () async {
      policy.denial = 'Recovering';
      expect(
        (await dispatcher.dispatch(request('deny', a))).result.status,
        ActionStatus.denied,
      );
      policy.denial = null;
      for (final status in [ActionStatus.noOp, ActionStatus.failure]) {
        player.result = CommandResult(status, 'No effect');
        await dispatcher.dispatch(request(status.name, a));
        await dispatcher.dispatch(request(status.name, a));
      }
      expect(events.where((e) => e.startsWith('success')), isEmpty);
      expect(events.where((e) => e.startsWith('play')).length, 2);
    },
  );

  test(
    'ownership is committed at arrival; edits cannot reattribute queued requests',
    () async {
      player.gate = Completer();
      final first = dispatcher.dispatch(request('one', a));
      final second = dispatcher.dispatch(request('two', b));
      catalog = ProfileCatalog.empty();
      player.gate!.complete();
      expect((await second).request.profile, ProfileId.p2);
      await first;
      final stale = await dispatcher.dispatch(request('stale', a));
      expect(stale.result.status, ActionStatus.denied);
    },
  );

  test(
    'post-success failure preserves actual success and blocks further skill actions',
    () async {
      policy.failPost = true;
      final first = await dispatcher.dispatch(request('one', a));
      final second = await dispatcher.dispatch(request('two', b));
      expect(first.result.status, ActionStatus.success);
      expect(first.result.message, contains('Skill update failed'));
      expect(second.result.status, ActionStatus.failure);
      expect(events.where((e) => e.startsWith('play')).length, 1);
    },
  );
}
