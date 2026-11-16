import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player/domain/entities/loop_queue.dart';
import 'package:troona/skills/skill.dart';

void main() {
  LoopOccurrence item(String id, [String song = 'same-song']) =>
      LoopOccurrence(id, SongReference(song));
  late LoopQueue queue;
  var sequence = 0;
  LoopEditResult edit(
    LoopSelector selector,
    List<QueueOperation> operations, {
    Duration now = Duration.zero,
    String? session,
    int? loop,
    int? revision,
  }) => queue.edit(
    session: session ?? queue.sessionId,
    expectedLoop: loop ?? queue.ordinal,
    planId: 'plan-${sequence++}',
    elapsed: now,
    request: EditLoopQueue(
      'effect-$sequence',
      loops: selector,
      expectedRevision: revision ?? queue.revision,
      operations: operations,
      lifetime: selector is CurrentLoop ? null : const Duration(seconds: 10),
    ),
  );
  List<String> ids(LoopSnapshot snapshot) =>
      snapshot.occurrences.map((o) => o.id).toList();
  setUp(() {
    queue = LoopQueue('session-1', [item('a'), item('b')]);
  });

  test(
    'current-only edits distinguish duplicate tracks and leave baseline untouched',
    () {
      expect(
        edit(const CurrentLoop(), [RemoveOccurrence('a')]).status,
        CapabilityStatus.applied,
      );
      expect(ids(queue.current), ['b']);
      expect(ids(queue.preview(1, Duration.zero)), ['a', 'b']);
      expect(
        edit(const CurrentLoop(), [RemoveOccurrence('a')]).status,
        CapabilityStatus.noOp,
      );
      expect(
        edit(const CurrentLoop(), [RemoveOccurrence('b')]).status,
        CapabilityStatus.applied,
      );
      expect(queue.current.occurrences, isEmpty);
    },
  );

  test(
    'selected future loop and finite range materialize only matching ordinals',
    () {
      edit(FutureLoop(2), [
        InsertSong(SongReference('extra'), 'c', beforeOccurrenceId: 'b'),
      ]);
      edit(FutureLoopRange(1, 3), [RemoveOccurrence('a')]);
      expect(ids(queue.current), ['a', 'b']);
      expect(ids(queue.enterNext(Duration.zero)), ['b']);
      expect(ids(queue.enterNext(Duration.zero)), ['c', 'b']);
      expect(ids(queue.enterNext(Duration.zero)), ['b']);
      expect(ids(queue.enterNext(Duration.zero)), ['a', 'b']);
    },
  );

  test(
    'preload is provisional, deadline/revocation rebuild future but preserve entered loop',
    () {
      final plan = 'plan-$sequence';
      edit(FutureLoopRange(1), [RemoveOccurrence('a')]);
      final loaded = queue.preview(1, Duration.zero);
      expect(ids(loaded), ['b']);
      queue.revoke(plan);
      expect(ids(queue.preview(1, Duration.zero)), ['a', 'b']);
      expect(queue.revision, greaterThan(loaded.revision));
      edit(FutureLoopRange(1), [RemoveOccurrence('a')]);
      queue.enterNext(const Duration(seconds: 9));
      expect(ids(queue.current), ['b']);
      expect(queue.retireDue(const Duration(seconds: 10)), isTrue);
      expect(ids(queue.current), ['b']);
      expect(ids(queue.preview(2, const Duration(seconds: 10))), ['a', 'b']);
      expect(queue.planCount, 0);
    },
  );

  test(
    'stale session, loop, revision, past targets and identity reuse never retarget',
    () {
      for (final result in [
        edit(const CurrentLoop(), [RemoveOccurrence('a')], session: 'old'),
        edit(const CurrentLoop(), [RemoveOccurrence('a')], loop: 1),
        edit(const CurrentLoop(), [RemoveOccurrence('a')], revision: 99),
        edit(const CurrentLoop(), [
          InsertSong(SongReference('different'), 'a'),
        ]),
      ]) {
        expect(result.status, CapabilityStatus.denied);
      }
      expect(ids(queue.current), ['a', 'b']);
      queue.enterNext(Duration.zero);
      expect(
        edit(FutureLoop(1), [RemoveOccurrence('a')]).status,
        CapabilityStatus.denied,
      );
    },
  );

  test(
    'baseline edits preserve stable ranges and report vanished operations',
    () {
      edit(FutureLoopRange(1), [RemoveOccurrence('a'), RemoveOccurrence('b')]);
      queue.replaceBaseline([item('a'), item('d')], [item('a'), item('d')]);
      final next = queue.preview(1, Duration.zero);
      expect(ids(next), ['d']);
      expect(next.skippedOperations, ['b']);
      expect(queue.current.occurrences.map((o) => o.id), ['a', 'd']);
    },
  );

  test(
    'transaction copies isolate failed native work and preserve committed plan order',
    () {
      final draft = queue.copy();
      final saved = queue;
      queue = draft;
      edit(FutureLoop(1), [InsertSong(SongReference('c'), 'c')]);
      edit(FutureLoop(1), [
        InsertSong(SongReference('d'), 'd', beforeOccurrenceId: 'c'),
      ]);
      expect(ids(draft.preview(1, Duration.zero)), ['a', 'b', 'd', 'c']);
      expect(ids(saved.preview(1, Duration.zero)), ['a', 'b']);
      expect(saved.planCount, 0);
      final revision = draft.revision;
      expect(
        edit(const CurrentLoop(), [
          InsertSong(SongReference('e'), 'e'),
          InsertSong(SongReference('f'), 'f', beforeOccurrenceId: 'missing'),
        ]).status,
        CapabilityStatus.denied,
      );
      expect(draft.revision, revision);
      expect(ids(draft.current), ['a', 'b']);
    },
  );

  test('future plans never skip over empty loops', () {
    edit(FutureLoop(1), [RemoveOccurrence('a'), RemoveOccurrence('b')]);
    expect(queue.enterNext(Duration.zero).occurrences, isEmpty);
    expect(queue.ordinal, 1);
    expect(ids(queue.preview(2, Duration.zero)), ['a', 'b']);
  });
}
