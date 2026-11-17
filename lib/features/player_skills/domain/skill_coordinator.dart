import 'dart:async';
import 'package:troona/skills/skill.dart';
import 'effect_ledger.dart';

final class AppliedCapability {
  final CapabilityResult result;
  final Future<void> Function()? cleanup;
  const AppliedCapability(this.result, {this.cleanup});
}

abstract interface class SkillCapabilityAdapter {
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  );
}

final class SkillExecutionBudget {
  int _remaining;
  SkillExecutionBudget({int limit = 64}) : _remaining = limit {
    if (limit < 1 || limit > 64) throw ArgumentError.value(limit, 'limit');
  }
  bool consume() {
    if (_remaining == 0) return false;
    _remaining--;
    return true;
  }
}

final class SkillInvocationOutcome {
  final List<CapabilityResult> results;
  final bool stateChanged;
  final String? error;
  SkillInvocationOutcome(
    Iterable<CapabilityResult> results, {
    this.stateChanged = false,
    this.error,
  }) : results = List.unmodifiable(results);
}

/// Runs capability reactions within the dispatcher's ordered operation. Public
/// invocation enqueues; policy hooks use invokeWithinOrder to avoid reentrancy.
final class SkillCoordinator {
  final SkillOrder runOrdered;
  final EffectLedger effects;
  final Map<SkillCapability, SkillCapabilityAdapter> adapters;
  final bool Function(SkillOrigin)? originIsActive;
  final _invocations =
      <(String, String, String, String), Future<SkillInvocationOutcome>>{};
  final _completed =
      <(String, String, String, String), SkillInvocationOutcome>{};
  final _results = <(String, String, String, String), CapabilityResult>{};
  static const completedInvocationLimit = 256;
  static const effectResultLimit = 4096;
  int _activeInvocations = 0;
  int get pendingInvocationCount => _invocations.length;
  int get completedInvocationCount => _completed.length;
  int get retainedEffectResultCount => _results.length;
  bool _notifying = false;

  void forgetSession(String sessionId) {
    _completed.removeWhere((key, _) => key.$1 == sessionId);
    _results.removeWhere((key, _) => key.$1 == sessionId);
  }

  SkillCoordinator({
    required this.runOrdered,
    required this.effects,
    this.originIsActive,
    Map<SkillCapability, SkillCapabilityAdapter> adapters = const {},
  }) : adapters = Map.of(adapters);

  (String, String, String, String) _invocationKey(SkillOrigin origin) =>
      (origin.sessionId, origin.owner, origin.skillKey, origin.invocationId);
  (String, String, String, String) _effectKey(
    SkillOrigin origin,
    String effectId,
  ) => (origin.sessionId, origin.owner, origin.skillKey, effectId);

  Future<SkillInvocationOutcome> invoke({
    required SkillDefinition definition,
    required SkillRuntime runtime,
    required SkillRuntimeEvent event,
    required SkillOrigin origin,
    required SkillContext context,
    SkillExecutionBudget? budget,
    bool allowPlayback = true,
  }) {
    if (_notifying) {
      return Future.error(StateError('Result callbacks cannot invoke skills.'));
    }
    return runOrdered(
      () => invokeWithinOrder(
        definition: definition,
        runtime: runtime,
        event: event,
        origin: origin,
        context: context,
        budget: budget,
        allowPlayback: allowPlayback,
      ),
    );
  }

  Future<SkillInvocationOutcome> invokeWithinOrder({
    required SkillDefinition definition,
    required SkillRuntime runtime,
    required SkillRuntimeEvent event,
    required SkillOrigin origin,
    required SkillContext context,
    SkillExecutionBudget? budget,
    bool allowPlayback = true,
    bool transient = false,
  }) {
    if (_notifying) {
      return Future.error(StateError('Result callbacks cannot invoke skills.'));
    }
    if (transient) {
      return _invoke(
        definition,
        runtime,
        event,
        origin,
        context,
        budget ?? SkillExecutionBudget(),
        allowPlayback,
      );
    }
    final key = _invocationKey(origin);
    final pending = _invocations[key];
    if (pending != null) return pending;
    final completed = _completed[key];
    if (completed != null) return Future.value(completed);
    final result =
        _invoke(
          definition,
          runtime,
          event,
          origin,
          context,
          budget ?? SkillExecutionBudget(),
          allowPlayback,
        ).then(
          (outcome) {
            _invocations.remove(key);
            _completed[key] = outcome;
            while (_completed.length > completedInvocationLimit) {
              _completed.remove(_completed.keys.first);
            }
            return outcome;
          },
          onError: (Object error, StackTrace stack) {
            _invocations.remove(key);
            Error.throwWithStackTrace(error, stack);
          },
        );
    _invocations[key] = result;
    return result;
  }

  Future<SkillInvocationOutcome> _invoke(
    SkillDefinition definition,
    SkillRuntime runtime,
    SkillRuntimeEvent event,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
    bool allowPlayback,
  ) async {
    _activeInvocations++;
    try {
      return await _react(
        definition,
        runtime,
        event,
        origin,
        context,
        budget,
        allowPlayback,
      );
    } finally {
      if (--_activeInvocations == 0) {
        while (_results.length > effectResultLimit) {
          _results.remove(_results.keys.first);
        }
      }
    }
  }

  Future<SkillInvocationOutcome> _react(
    SkillDefinition definition,
    SkillRuntime runtime,
    SkillRuntimeEvent event,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
    bool allowPlayback,
  ) async {
    if (origin.owner != context.owner ||
        origin.sessionId != context.sessionId ||
        origin.skillKey != definition.id.key ||
        !context.players.contains(origin.owner)) {
      return SkillInvocationOutcome(
        [],
        error: 'Invalid skill invocation ownership.',
      );
    }
    runtime.configureListeners(definition);
    if (!definition.listeners.any((l) => l.trigger == event.trigger)) {
      return SkillInvocationOutcome(
        [],
        error: 'This skill does not support that trigger.',
      );
    }
    if (!context.support.containsAll(definition.requiredCapabilities)) {
      return SkillInvocationOutcome(
        [],
        error: 'Required skill capabilities are unavailable.',
      );
    }
    await effects.retireDue(context.elapsed);
    final SkillReaction reaction;
    try {
      final matching = runtime.matchingListeners(event, context);
      if (matching.isEmpty && event is SkillManualActivation) {
        return SkillInvocationOutcome(
          [],
          error: 'This activation listener is inactive.',
        );
      }
      final requests = <CapabilityRequest>[];
      var changed = false;
      for (final listener in matching) {
        // A preceding callback may have disabled another listener.
        if (!runtime.matchingListeners(event, context).contains(listener)) {
          continue;
        }
        final result = runtime.onListener(listener.key, event, context);
        requests.addAll(result.requests);
        changed = changed || result.stateChanged;
      }
      reaction = SkillReaction(requests: requests, stateChanged: changed);
    } catch (_) {
      return SkillInvocationOutcome([], error: 'Skill reaction failed.');
    }
    final results = <CapabilityResult>[];
    String? callbackError;
    for (final request in reaction.requests) {
      final key = _effectKey(origin, request.effectId);
      final previous = _results[key];
      if (previous != null) {
        results.add(previous);
        continue;
      }
      final result = !budget.consume()
          ? CapabilityResult(
              effectId: request.effectId,
              status: CapabilityStatus.denied,
              reason: 'Skill reaction budget exhausted.',
            )
          : !allowPlayback && request is ExecutePlayerAction
          ? CapabilityResult(
              effectId: request.effectId,
              status: CapabilityStatus.denied,
              reason: 'Generated success cannot recursively request playback.',
            )
          : await _apply(request, origin, context, budget);
      _results[key] = result;
      results.add(result);
      try {
        _notifying = true;
        runtime.onCapabilityResult(result, context);
      } catch (_) {
        callbackError = 'Skill result notification failed.';
      } finally {
        _notifying = false;
      }
    }
    if (definition.failureCleanup ==
            SkillFailureCleanup.revokeInvocationEffects &&
        (callbackError != null ||
            results.any(
              (r) =>
                  r.status == CapabilityStatus.failed ||
                  r.status == CapabilityStatus.denied ||
                  r.status == CapabilityStatus.unsupported,
            ))) {
      if (!await effects.revokeInvocation(origin)) {
        callbackError = 'Skill effect cleanup is pending.';
      }
    }
    return SkillInvocationOutcome(
      results,
      stateChanged: reaction.stateChanged,
      error: callbackError,
    );
  }

  Future<CapabilityResult> _apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  ) async {
    CapabilityResult result(CapabilityStatus status, String reason) =>
        CapabilityResult(
          effectId: request.effectId,
          status: status,
          reason: reason,
        );
    if (request is RevokeSkillEffect) {
      if (!effects.contains(request.handleId)) {
        return result(CapabilityStatus.noOp, 'Effect already ended.');
      }
      return await effects.revoke(request.handleId, requester: origin)
          ? result(CapabilityStatus.applied, 'Effect revoked.')
          : result(
              CapabilityStatus.denied,
              'Effect is owned by another skill or cleanup is pending.',
            );
    }
    if (!(originIsActive?.call(origin) ?? true)) {
      return result(
        CapabilityStatus.denied,
        'The skill source or session has ended.',
      );
    }
    final adapter = adapters[request.capability];
    if (adapter == null || !context.support.contains(request.capability)) {
      return result(CapabilityStatus.unsupported, 'Capability is unavailable.');
    }
    try {
      final applied = await adapter.apply(request, origin, context, budget);
      final handle = applied.result.handle;
      final valid =
          applied.result.effectId == request.effectId &&
          ((handle == null && applied.cleanup == null) ||
              (handle != null &&
                  applied.cleanup != null &&
                  handle.origin.owner == origin.owner &&
                  handle.origin.skillKey == origin.skillKey &&
                  handle.origin.sessionId == origin.sessionId &&
                  handle.origin.invocationId == origin.invocationId &&
                  handle.deadline > context.elapsed &&
                  !effects.contains(handle.id)));
      if (!valid) {
        await applied.cleanup?.call();
        return result(
          CapabilityStatus.failed,
          'Invalid capability adapter outcome.',
        );
      }
      if (handle != null) {
        effects.register(handle, applied.cleanup!, context.elapsed);
      }
      return applied.result;
    } catch (_) {
      return result(CapabilityStatus.failed, 'Capability execution failed.');
    }
  }
}
