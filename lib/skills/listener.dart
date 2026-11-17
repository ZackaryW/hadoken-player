import 'skill.dart';

/// Code-owned subscription metadata, separate from its runtime activation.
final class SkillListener {
  final String key;
  final SkillTrigger trigger;
  final PlayerScope scope;
  final bool initiallyActive;
  final SkillCombo? combo;

  /// Capability callbacks require an armed listener; declarations do not.
  final bool armedOnly;
  SkillListener(
    String key,
    this.trigger, {
    this.scope = PlayerScope.owner,
    this.initiallyActive = true,
    this.combo,
    this.armedOnly = false,
  }) : key = requireIdentity(key) {
    if (scope == PlayerScope.explicit) {
      throw ArgumentError('Use a dynamic listener for explicit player sets.');
    }
    if (combo != null && trigger != SkillTrigger.comboObserved) {
      throw ArgumentError('Only combo listeners accept a pattern.');
    }
  }

  bool matches(SkillRuntimeEvent event, SkillContext context) {
    if (event.trigger != trigger) return false;
    if (event is SkillComboObserved && armedOnly != event.armed) {
      return false;
    }
    final actor = context.actor;
    if (actor != null &&
        !PlayerSelector(
          scope,
        ).resolve(context.owner, context.players).contains(actor)) {
      return false;
    }
    return combo == null ||
        (event is SkillComboObserved &&
            combo == SkillCombo(event.observations.map((o) => o.stroke)));
  }
}

/// Keys have object identity: unrelated declarations cannot alias by name.
final class SkillStateKey<T extends Object> {
  final String name;
  const SkillStateKey(this.name);
}

final class SkillStateStore {
  final _values = <Object, Object>{};
  T? read<T extends Object>(SkillStateKey<T> key) => _values[key] as T?;
  void write<T extends Object>(SkillStateKey<T> key, T value) =>
      _values[key] = value;
  void remove<T extends Object>(SkillStateKey<T> key) => _values.remove(key);
  void clear() => _values.clear();
}
