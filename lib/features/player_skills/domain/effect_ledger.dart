import 'dart:async';
import 'package:troona/skills/skill.dart';

typedef SkillOrder = Future<T> Function<T>(Future<T> Function() operation);

final class EffectCleanupFailure {
  final EffectHandle handle;
  final Object error;
  const EffectCleanupFailure(this.handle, this.error);
}

final class _OwnedEffect {
  final EffectHandle handle;
  final Future<void> Function() cleanup;
  bool retiring = false;
  _OwnedEffect(this.handle, this.cleanup);
}

/// All mutations run on the action dispatcher's queue. Failed resource cleanup
/// remains owned and retryable; expiry never makes a live resource ownerless.
final class EffectLedger {
  final Future<Duration> Function() now;
  final SkillOrder runOrdered;
  final bool scheduleTimers;
  final _entries = <String, _OwnedEffect>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  final _failures = StreamController<EffectCleanupFailure>.broadcast(
    sync: true,
  );
  Timer? _timer;
  bool _disposed = false;
  Future<void> Function(List<EffectHandle>, Duration)? onExpired;

  EffectLedger({
    required this.now,
    required this.runOrdered,
    this.scheduleTimers = true,
  });
  Stream<void> get changes => _changes.stream;
  Stream<EffectCleanupFailure> get failures => _failures.stream;
  Iterable<EffectHandle> get handles =>
      List.unmodifiable(_entries.values.map((e) => e.handle));
  bool contains(String id) => _entries.containsKey(id);
  bool isEffective(String id, Duration elapsed) {
    final entry = _entries[id];
    return entry != null && !entry.retiring && entry.handle.deadline > elapsed;
  }

  void register(
    EffectHandle handle,
    Future<void> Function() cleanup,
    Duration elapsed,
  ) {
    if (_disposed ||
        _entries.containsKey(handle.id) ||
        handle.deadline <= elapsed) {
      throw StateError('Cannot register this effect handle.');
    }
    _entries[handle.id] = _OwnedEffect(handle, cleanup);
    _changes.add(null);
    _schedule(elapsed);
  }

  Duration remaining(String owner, String skillKey, Duration elapsed) {
    var remaining = Duration.zero;
    for (final entry in _entries.values) {
      final handle = entry.handle;
      if (handle.origin.owner != owner || handle.origin.skillKey != skillKey) {
        continue;
      }
      // A pending/failed cleanup still locks assignment even after its deadline.
      final left = handle.deadline > elapsed
          ? handle.deadline - elapsed
          : const Duration(seconds: 1);
      if (left > remaining) remaining = left;
    }
    return remaining;
  }

  Future<bool> revoke(String id, {SkillOrigin? requester}) async {
    final entry = _entries[id];
    if (entry == null) return true;
    if (requester != null &&
        (entry.handle.origin.owner != requester.owner ||
            entry.handle.origin.skillKey != requester.skillKey ||
            entry.handle.origin.sessionId != requester.sessionId)) {
      return false;
    }
    entry.retiring = true;
    try {
      await entry.cleanup();
      _entries.remove(id);
      _changes.add(null);
      return true;
    } catch (error) {
      _failures.add(EffectCleanupFailure(entry.handle, error));
      return false;
    }
  }

  Future<List<EffectHandle>> retireDue(Duration elapsed) async {
    final expired = <EffectHandle>[];
    for (final entry in _entries.values.toList()) {
      if (entry.retiring || entry.handle.deadline <= elapsed) {
        if (await revoke(entry.handle.id)) expired.add(entry.handle);
      }
    }
    if (expired.isNotEmpty) {
      await onExpired?.call(List.unmodifiable(expired), elapsed);
    }
    _schedule(elapsed);
    return expired;
  }

  Future<bool> revokeInvocation(SkillOrigin origin) async {
    var clean = true;
    for (final handle in handles.where(
      (h) =>
          h.origin.owner == origin.owner &&
          h.origin.skillKey == origin.skillKey &&
          h.origin.sessionId == origin.sessionId &&
          h.origin.invocationId == origin.invocationId,
    )) {
      if (!await revoke(handle.id, requester: origin)) clean = false;
    }
    return clean;
  }

  Future<bool> endSession(String sessionId) async {
    var clean = true;
    for (final handle in handles.where(
      (h) => h.origin.sessionId == sessionId,
    )) {
      if (!await revoke(handle.id)) clean = false;
    }
    _schedule(await now());
    return clean;
  }

  void _schedule(Duration elapsed) {
    _timer?.cancel();
    if (_disposed || !scheduleTimers || _entries.isEmpty) return;
    final deadline = _entries.values
        .map((e) => e.handle.deadline)
        .reduce((a, b) => a < b ? a : b);
    final delay = deadline > elapsed
        ? deadline - elapsed
        : const Duration(seconds: 1);
    _timer = Timer(delay, () {
      unawaited(
        runOrdered(() async {
          if (!_disposed) await retireDue(await now());
        }).catchError((Object error) {
          // Keep ownership and retry after a clock/scheduling failure.
          if (!_disposed) _schedule(deadline);
        }),
      );
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await runOrdered(() async {
      for (final handle in handles) {
        await revoke(handle.id);
      }
    });
    await _changes.close();
    await _failures.close();
  }
}
