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
  );
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
  final _invocations =
      <(String, String, String, String), Future<SkillInvocationOutcome>>{};
  final _results = <(String, String, String, String), CapabilityResult>{};
  bool _notifying = false;

  SkillCoordinator({
    required this.runOrdered,
    required this.effects,
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
      ),
    );
  }

  Future<SkillInvocationOutcome> invokeWithinOrder({
    required SkillDefinition definition,
    required SkillRuntime runtime,
    required SkillRuntimeEvent event,
    required SkillOrigin origin,
    required SkillContext context,
  }) {
    if (_notifying) {
      return Future.error(StateError('Result callbacks cannot invoke skills.'));
    }
    final key = _invocationKey(origin);
    return _invocations.putIfAbsent(
      key,
      () => _invoke(definition, runtime, event, origin, context),
    );
  }

  Future<SkillInvocationOutcome> _invoke(
    SkillDefinition definition,
    SkillRuntime runtime,
    SkillRuntimeEvent event,
    SkillOrigin origin,
    SkillContext context,
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
    if (!definition.triggers.contains(event.trigger)) {
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
      reaction = runtime.onEvent(event, context);
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
      final result = await _apply(request, origin, context);
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
    final adapter = adapters[request.capability];
    if (adapter == null || !context.support.contains(request.capability)) {
      return result(CapabilityStatus.unsupported, 'Capability is unavailable.');
    }
    try {
      final applied = await adapter.apply(request, origin, context);
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
