import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/player_skills/domain/effect_ledger.dart';
import 'package:troona/skills/skill.dart';
import '../../helpers/skill_fakes.dart';

void main() {
  late PlayerActionDispatcher dispatcher;
  late EffectLedger ledger;
  var elapsed = Duration.zero;
  SkillOrigin origin(String owner, [String session = 's']) => SkillOrigin(
    owner: owner,
    skillKey: 'test',
    invocationId: 'invoke',
    sessionId: session,
  );
  EffectHandle handle(
    String id,
    int seconds, {
    String owner = 'p1',
    String session = 's',
  }) => EffectHandle(
    id: id,
    origin: origin(owner, session),
    deadline: Duration(seconds: seconds),
  );
  setUp(() {
    elapsed = Duration.zero;
    dispatcher = PlayerActionDispatcher(
      playback: SkillCommands(),
      catalog: ProfileCatalog.empty,
    );
    ledger = EffectLedger(
      now: () async => elapsed,
      runOrdered: dispatcher.runOrdered,
      scheduleTimers: false,
    );
  });
  tearDown(() async {
    await ledger.dispose();
    await dispatcher.dispose();
  });

  test('overlap, elapsed background jump and idempotent cleanup', () async {
    final cleaned = <String>[];
    final expired = <String>[];
    ledger.onExpired = (handles, now) async {
      expired.addAll(handles.map((h) => h.id));
    };
    ledger.register(handle('a', 5), () async {
      cleaned.add('a');
    }, elapsed);
    ledger.register(handle('b', 10), () async {
      cleaned.add('b');
    }, elapsed);
    elapsed = const Duration(seconds: 6);
    expect(ledger.isEffective('a', elapsed), isFalse);
    expect(ledger.isEffective('b', elapsed), isTrue);
    await dispatcher.runOrdered(() => ledger.retireDue(elapsed));
    expect(cleaned, ['a']);
    expect(expired, ['a']);
    expect(ledger.remaining('p1', 'test', elapsed), const Duration(seconds: 4));
    elapsed = const Duration(hours: 1);
    await dispatcher.runOrdered(() => ledger.retireDue(elapsed));
    await ledger.revoke('b');
    expect(cleaned, ['a', 'b']);
    expect(ledger.handles, isEmpty);
  });

  test(
    'revocation checks owner and session; replacement cleans only old session',
    () async {
      var count = 0;
      ledger.register(handle('old', 10), () async {
        count++;
      }, elapsed);
      ledger.register(handle('new', 10, session: 'next'), () async {
        count++;
      }, elapsed);
      expect(await ledger.revoke('old', requester: origin('p2')), isFalse);
      expect(
        await ledger.revoke('old', requester: origin('p1', 'wrong')),
        isFalse,
      );
      expect(await ledger.endSession('s'), isTrue);
      expect(ledger.handles.map((h) => h.id), ['new']);
      expect(count, 1);
    },
  );

  test(
    'failed cleanup remains owned and locked, then retries without reactivation',
    () async {
      var fail = true;
      final failures = <EffectCleanupFailure>[];
      final subscription = ledger.failures.listen(failures.add);
      ledger.register(handle('resource', 5), () async {
        if (fail) throw StateError('busy');
      }, elapsed);
      elapsed = const Duration(seconds: 8);
      await ledger.retireDue(elapsed);
      expect(ledger.isEffective('resource', elapsed), isFalse);
      expect(
        ledger.remaining('p1', 'test', elapsed),
        greaterThan(Duration.zero),
      );
      expect(failures.single.handle.id, 'resource');
      fail = false;
      await ledger.retireDue(elapsed);
      expect(ledger.remaining('p1', 'test', elapsed), Duration.zero);
      await subscription.cancel();
    },
  );

  test('timer cleanup uses the ordered queue and fresh elapsed clock', () {
    fakeAsync((async) {
      final timerDispatcher = PlayerActionDispatcher(
        playback: SkillCommands(),
        catalog: ProfileCatalog.empty,
      );
      final timerLedger = EffectLedger(
        now: () async => async.elapsed,
        runOrdered: timerDispatcher.runOrdered,
      );
      var cleaned = 0;
      timerLedger.register(handle('timer', 5), () async {
        cleaned++;
      }, Duration.zero);
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(cleaned, 1);
      expect(timerLedger.handles, isEmpty);
      timerLedger.dispose();
      async.flushMicrotasks();
      timerDispatcher.dispose();
      async.flushMicrotasks();
    });
  });
}
