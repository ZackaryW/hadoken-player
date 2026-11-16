import 'package:troona/skills/skill.dart';

/// An occurrence survives materialization; duplicate songs have different IDs.
final class LoopOccurrence {
  final String id;
  final SongReference song;
  LoopOccurrence(String id, this.song) : id = requireIdentity(id);
}

final class LoopSnapshot {
  final String sessionId;
  final int ordinal;
  final int revision;
  final List<LoopOccurrence> occurrences;
  final List<String> skippedOperations;
  LoopSnapshot(
    this.sessionId,
    this.ordinal,
    this.revision,
    Iterable<LoopOccurrence> occurrences, [
    Iterable<String> skipped = const [],
  ]) : occurrences = List.unmodifiable(occurrences),
       skippedOperations = List.unmodifiable(skipped);
}

final class LoopEditResult {
  final CapabilityStatus status;
  final String reason;
  final int revision;
  const LoopEditResult(this.status, this.reason, this.revision);
}

final class _LoopPlan {
  final String id;
  final LoopSelector selector;
  final List<QueueOperation> operations;
  final Duration deadline;
  _LoopPlan(this.id, this.selector, this.operations, this.deadline);
  bool includes(int loop) => switch (selector) {
    FutureLoop(:final ordinal) => loop == ordinal,
    FutureLoopRange(:final first, :final last) =>
      loop >= first && (last == null || loop <= last),
    _ => false,
  };
}

/// Session-owned state, copied before a native transaction and committed only
/// after it succeeds. Future snapshots are provisional; entering a loop freezes
/// its contents. Revision checks conservatively invalidate on any queue edit.
final class LoopQueue {
  final String sessionId;
  int ordinal;
  int revision;
  List<LoopOccurrence> _baseline;
  List<LoopOccurrence> _current;
  final List<_LoopPlan> _plans;
  final Set<String> _usedIds;
  LoopQueue(String sessionId, Iterable<LoopOccurrence> baseline)
    : sessionId = requireIdentity(sessionId),
      ordinal = 0,
      revision = 0,
      _baseline = List.of(baseline),
      _current = List.of(baseline),
      _plans = [],
      _usedIds = baseline.map((o) => o.id).toSet() {
    _validateOccurrences(_baseline);
  }
  LoopQueue._(
    this.sessionId,
    this.ordinal,
    this.revision,
    this._baseline,
    this._current,
    this._plans,
    this._usedIds,
  );
  LoopQueue copy() => LoopQueue._(
    sessionId,
    ordinal,
    revision,
    List.of(_baseline),
    List.of(_current),
    List.of(_plans),
    Set.of(_usedIds),
  );

  List<LoopOccurrence> get baseline => List.unmodifiable(_baseline);
  LoopSnapshot get current =>
      LoopSnapshot(sessionId, ordinal, revision, _current);
  int get planCount => _plans.length;
  bool containsPlan(String id) => _plans.any((p) => p.id == id);

  static void _validateOccurrences(List<LoopOccurrence> items) {
    if (items.length > 10000 ||
        items.map((o) => o.id).toSet().length != items.length) {
      throw ArgumentError('Queue occurrences must be distinct and bounded.');
    }
  }

  LoopSnapshot preview(int target, Duration elapsed) {
    if (target <= ordinal) {
      if (target == ordinal) return current;
      throw ArgumentError('Past loops are not editable.');
    }
    final items = List<LoopOccurrence>.of(_baseline);
    final skipped = <String>[];
    for (final plan in _plans) {
      if (plan.deadline > elapsed && plan.includes(target)) {
        _apply(items, plan.operations, skipped: skipped);
      }
    }
    return LoopSnapshot(sessionId, target, revision, items, skipped);
  }

  /// Only forward entry changes the ordinal. Previous navigation is a local
  /// index movement and never calls this method. Empty loops remain empty.
  LoopSnapshot enterNext(Duration elapsed) {
    retireDue(elapsed);
    final next = preview(ordinal + 1, elapsed);
    ordinal++;
    revision++;
    _current = List.of(next.occurrences);
    return current;
  }

  bool retireDue(Duration elapsed) {
    final count = _plans.length;
    _plans.removeWhere((p) => p.deadline <= elapsed);
    if (_plans.length == count) return false;
    revision++;
    return true;
  }

  bool revoke(String planId) {
    final count = _plans.length;
    _plans.removeWhere((p) => p.id == planId);
    if (_plans.length == count) return false;
    revision++;
    return true;
  }

  LoopEditResult edit({
    required String session,
    required int expectedLoop,
    required String planId,
    required EditLoopQueue request,
    required Duration elapsed,
  }) {
    LoopEditResult result(CapabilityStatus status, String reason) =>
        LoopEditResult(status, reason, revision);
    retireDue(elapsed);
    if (session != sessionId ||
        expectedLoop != ordinal ||
        request.expectedRevision != revision) {
      return result(
        CapabilityStatus.denied,
        'The queue session, loop or revision changed.',
      );
    }
    final selector = request.loops;
    final target = switch (selector) {
      CurrentLoop() => ordinal,
      FutureLoop(:final ordinal) => ordinal,
      FutureLoopRange(:final first) => first,
    };
    if (selector is! CurrentLoop && target <= ordinal) {
      return result(
        CapabilityStatus.denied,
        'A future loop must not have started.',
      );
    }
    if (_plans.any((p) => p.id == planId) || _plans.length >= 128) {
      return result(
        CapabilityStatus.denied,
        'Duplicate plan or too many future plans.',
      );
    }
    final inserted = request.operations
        .whereType<InsertSong>()
        .map((o) => o.occurrenceId)
        .toList();
    final futureInsertions = _plans.fold<int>(
      0,
      (count, plan) => count + plan.operations.whereType<InsertSong>().length,
    );
    if (selector is! CurrentLoop &&
        _baseline.length + futureInsertions + inserted.length > 10000) {
      return result(
        CapabilityStatus.denied,
        'The future queue limit was reached.',
      );
    }
    if (inserted.toSet().length != inserted.length ||
        inserted.any(_usedIds.contains)) {
      return result(
        CapabilityStatus.denied,
        'An occurrence identity is already used in this session.',
      );
    }
    final items = List<LoopOccurrence>.of(
      target == ordinal ? _current : preview(target, elapsed).occurrences,
    );
    final skipped = <String>[];
    final changed = _apply(items, request.operations, skipped: skipped);
    if (items.length > 10000) {
      return result(CapabilityStatus.denied, 'The queue limit was reached.');
    }
    // A missing anchor is a conflict, never silently an append elsewhere.
    if (skipped.any((s) => s.startsWith('anchor:'))) {
      return result(
        CapabilityStatus.denied,
        'An insertion anchor is no longer available.',
      );
    }
    if (!changed && selector is CurrentLoop) {
      return result(CapabilityStatus.noOp, 'No matching occurrences remain.');
    }
    if (selector is CurrentLoop) {
      _current = items;
    } else {
      _plans.add(
        _LoopPlan(
          planId,
          selector,
          List.unmodifiable(request.operations),
          elapsed + request.lifetime!,
        ),
      );
    }
    _usedIds.addAll(inserted);
    revision++;
    return result(
      CapabilityStatus.applied,
      skipped.isEmpty
          ? 'Queue edit applied.'
          : 'Queue edit applied; ${skipped.length} missing occurrences skipped.',
    );
  }

  static bool _apply(
    List<LoopOccurrence> items,
    List<QueueOperation> operations, {
    required List<String> skipped,
  }) {
    var changed = false;
    for (final operation in operations) {
      switch (operation) {
        case InsertSong(
          :final song,
          :final occurrenceId,
          :final beforeOccurrenceId,
        ):
          final at = beforeOccurrenceId == null
              ? items.length
              : items.indexWhere((o) => o.id == beforeOccurrenceId);
          if (at < 0 || items.any((o) => o.id == occurrenceId)) {
            skipped.add('anchor:$occurrenceId');
          } else {
            items.insert(at, LoopOccurrence(occurrenceId, song));
            changed = true;
          }
        case RemoveOccurrence(:final occurrenceId):
          final at = items.indexWhere((o) => o.id == occurrenceId);
          if (at < 0) {
            skipped.add(occurrenceId);
          } else {
            items.removeAt(at);
            changed = true;
          }
      }
    }
    return changed;
  }

  /// Ordinary edits update the baseline and the current materialized loop;
  /// callers supply stable IDs for surviving occurrences in both orders.
  void replaceBaseline(
    Iterable<LoopOccurrence> baseline,
    Iterable<LoopOccurrence> current,
  ) {
    final base = List<LoopOccurrence>.of(baseline);
    final live = List<LoopOccurrence>.of(current);
    _validateOccurrences(base);
    _validateOccurrences(live);
    if (base.length +
            _plans.fold<int>(
              0,
              (count, p) => count + p.operations.whereType<InsertSong>().length,
            ) >
        10000) {
      throw ArgumentError('The future queue limit was reached.');
    }
    _baseline = base;
    _current = live;
    _usedIds.addAll([...base, ...live].map((o) => o.id));
    revision++;
  }
}
