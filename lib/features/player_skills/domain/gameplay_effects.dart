import 'dart:convert';
import 'package:troona/skills/skill.dart';
import 'effect_ledger.dart';
import 'skill_coordinator.dart';

final class ArmedSkillListener {
  final EffectHandle handle;
  final ArmComboListener declaration;
  final Set<String> players;
  const ArmedSkillListener(this.handle, this.declaration, this.players);
}

final class SkillRestriction {
  final EffectHandle handle;
  final RestrictActions declaration;
  final Set<String> players;
  const SkillRestriction(this.handle, this.declaration, this.players);
}

final class GameplayEffects implements SkillCapabilityAdapter {
  final EffectLedger ledger;
  final SkillDefinition? Function(String) definitionFor;
  final _listeners = <String, ArmedSkillListener>{};
  final _restrictions = <String, SkillRestriction>{};
  GameplayEffects({required this.ledger, required this.definitionFor});

  List<ArmedSkillListener> matching(
    String actor,
    SkillCombo combo,
    Duration elapsed,
  ) {
    final matches = _listeners.values
        .where(
          (listener) =>
              listener.players.contains(actor) &&
              listener.declaration.combo == combo &&
              ledger.isEffective(listener.handle.id, elapsed),
        )
        .toList();
    matches.sort((a, b) {
      final owner = a.handle.origin.owner.compareTo(b.handle.origin.owner);
      if (owner != 0) return owner;
      final skill = a.handle.origin.skillKey.compareTo(
        b.handle.origin.skillKey,
      );
      return skill != 0
          ? skill
          : a.declaration.listenerKey.compareTo(b.declaration.listenerKey);
    });
    return List.unmodifiable(matches);
  }

  SkillActionBlock? restrictionFor(
    String player,
    SkillTarget target,
    Effort effort,
    Duration elapsed,
  ) {
    final matches = _restrictions.values
        .where(
          (restriction) =>
              restriction.players.contains(player) &&
              restriction.declaration.actions.contains(target) &&
              !effort.overcomes(restriction.declaration.effort) &&
              ledger.isEffective(restriction.handle.id, elapsed),
        )
        .toList();
    matches.sort((a, b) {
      final rank = b.declaration.effort.compareTo(a.declaration.effort);
      return rank != 0 ? rank : a.handle.id.compareTo(b.handle.id);
    });
    if (matches.isEmpty) return null;
    final block = matches.first;
    final label =
        definitionFor(block.handle.origin.skillKey)?.label ??
        block.handle.origin.skillKey;
    return SkillActionBlock(
      '$label · ${remainingSeconds(block.handle.deadline - elapsed)}s remaining',
      effort: block.declaration.effort,
    );
  }

  @override
  Future<AppliedCapability> apply(
    CapabilityRequest request,
    SkillOrigin origin,
    SkillContext context,
    SkillExecutionBudget budget,
  ) async {
    AppliedCapability reject(String reason) => AppliedCapability(
      CapabilityResult(
        effectId: request.effectId,
        status: CapabilityStatus.denied,
        reason: reason,
      ),
    );
    if (ledger.handles.length >= 128) {
      return reject('Too many active skill effects.');
    }
    final id = jsonEncode([
      origin.sessionId,
      origin.owner,
      origin.skillKey,
      origin.invocationId,
      request.effectId,
    ]);
    if (request is ArmComboListener) {
      if (!(definitionFor(
            origin.skillKey,
          )?.triggers.contains(SkillTrigger.comboObserved) ??
          false)) {
        return reject('This skill does not declare a listening hook.');
      }
      if (_listeners.values.any(
        (l) =>
            l.handle.origin.owner == origin.owner &&
            l.handle.origin.skillKey == origin.skillKey &&
            l.declaration.listenerKey == request.listenerKey,
      )) {
        return reject('This listener is already armed.');
      }
      final players = request.players.resolve(origin.owner, context.players);
      if (players.isEmpty) {
        return reject('No added players match the listener.');
      }
      final handle = EffectHandle(
        id: id,
        origin: origin,
        deadline: context.elapsed + request.lifetime,
      );
      _listeners[id] = ArmedSkillListener(handle, request, players);
      return AppliedCapability(
        CapabilityResult(
          effectId: request.effectId,
          status: CapabilityStatus.applied,
          handle: handle,
        ),
        cleanup: () async {
          _listeners.remove(id);
        },
      );
    }
    if (request is RestrictActions) {
      final players = request.players.resolve(origin.owner, context.players);
      if (players.isEmpty) {
        return reject('No added players match the restriction.');
      }
      final handle = EffectHandle(
        id: id,
        origin: origin,
        deadline: context.elapsed + request.lifetime,
      );
      _restrictions[id] = SkillRestriction(handle, request, players);
      return AppliedCapability(
        CapabilityResult(
          effectId: request.effectId,
          status: CapabilityStatus.applied,
          handle: handle,
        ),
        cleanup: () async {
          _restrictions.remove(id);
        },
      );
    }
    return AppliedCapability(
      CapabilityResult(
        effectId: request.effectId,
        status: CapabilityStatus.unsupported,
        reason: 'This is not a gameplay capability.',
      ),
    );
  }
}
