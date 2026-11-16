import 'dart:async';
import 'profile_catalog.dart';
import 'profile_repository.dart';
import 'package:troona/skills/skill.dart';

final class TemporaryBinding {
  final ActionBinding binding;
  final EffectHandle handle;
  final String source;
  const TemporaryBinding(this.binding, this.handle, this.source);
}

/// Saved reservations stay in the repository; only executable macros enter
/// this revisioned view. Assignment edits invalidate pending recognition too.
final class EffectiveBindings {
  final ProfileRepository profiles;
  final bool Function(SkillMacroBinding) macroEnabled;
  final _changes = StreamController<ProfileCatalog>.broadcast(sync: true);
  late final StreamSubscription<ProfileCatalog> _profiles;
  StreamSubscription<void>? _availability;
  late ProfileCatalog _catalog;
  int _revision = 0;
  final _overrides = <String, TemporaryBinding>{};
  Future<Duration> Function()? elapsedNow;
  Future<Duration> remaining(TemporaryBinding binding) async {
    final now = await elapsedNow?.call() ?? Duration.zero;
    final left = binding.handle.deadline - now;
    return left > Duration.zero ? left : Duration.zero;
  }

  TemporaryBinding? temporaryFor(ProfileId profile, PlayerAction action) =>
      _overrides['${profile.name}.${action.name}'];
  EffectiveBindings({
    required this.profiles,
    required this.macroEnabled,
    Stream<void>? availabilityChanges,
  }) {
    _catalog = _build();
    profiles.validators.add(_validateBase);
    _profiles = profiles.changes.listen((_) => refresh());
    _availability = availabilityChanges?.listen((_) => refresh());
  }
  ProfileCatalog get catalog => _catalog;
  Stream<ProfileCatalog> get changes => _changes.stream;
  ProfileCatalog _build() => ProfileCatalog(
    names: profiles.catalog.names,
    bindings: [
      ...profiles.catalog.bindings.where((b) => !_overrides.containsKey(b.id)),
      ..._overrides.values.map((o) => o.binding),
    ],
    macros: profiles.catalog.macros.where(macroEnabled),
    timing: profiles.catalog.timing,
    revision: _revision,
    recoveryMessages: profiles.catalog.recoveryMessages,
  );

  void _validateBase(ProfileCatalog base) => _validate(base, _overrides.values);

  void _validate(ProfileCatalog base, Iterable<TemporaryBinding> overrides) {
    final reservations = <String, ExecutableBinding>{
      for (final binding in base.executableBindings) binding.comboKey: binding,
    };
    for (final override in overrides) {
      final binding = override.binding;
      if (!base.names.containsKey(binding.profile)) {
        throw const FormatException('Add this profile first.');
      }
      final existing = reservations[binding.comboKey];
      if (existing != null && existing.id != binding.id) {
        throw BindingConflict(existing);
      }
      reservations[binding.comboKey] = binding;
    }
  }

  void applyOverrides(
    Iterable<ActionBinding> bindings,
    EffectHandle handle,
    String source,
  ) {
    final proposed = Map<String, TemporaryBinding>.of(_overrides);
    for (final binding in bindings) {
      if (proposed.containsKey(binding.id)) {
        throw const FormatException(
          'This action already has a temporary combo.',
        );
      }
      proposed[binding.id] = TemporaryBinding(binding, handle, source);
    }
    _validate(profiles.catalog, proposed.values);
    final pending = profiles.pendingCatalog;
    if (pending != null) _validate(pending, proposed.values);
    _overrides
      ..clear()
      ..addAll(proposed);
    refresh();
  }

  void removeOverrides(String handleId) {
    if (!_overrides.values.any((o) => o.handle.id == handleId)) return;
    _overrides.removeWhere((_, o) => o.handle.id == handleId);
    refresh();
  }

  void refresh() {
    _revision++;
    _catalog = _build();
    _changes.add(_catalog);
  }

  Future<void> dispose() async {
    profiles.validators.remove(_validateBase);
    await _profiles.cancel();
    await _availability?.cancel();
    await _changes.close();
  }
}
