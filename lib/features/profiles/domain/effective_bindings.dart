import 'dart:async';
import 'profile_catalog.dart';
import 'profile_repository.dart';

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
  EffectiveBindings({
    required this.profiles,
    required this.macroEnabled,
    Stream<void>? availabilityChanges,
  }) {
    _catalog = _build();
    _profiles = profiles.changes.listen((_) => refresh());
    _availability = availabilityChanges?.listen((_) => refresh());
  }
  ProfileCatalog get catalog => _catalog;
  Stream<ProfileCatalog> get changes => _changes.stream;
  ProfileCatalog _build() => ProfileCatalog(
    names: profiles.catalog.names,
    bindings: profiles.catalog.bindings,
    macros: profiles.catalog.macros.where(macroEnabled),
    timing: profiles.catalog.timing,
    revision: _revision,
    recoveryMessages: profiles.catalog.recoveryMessages,
  );
  void refresh() {
    _revision++;
    _catalog = _build();
    _changes.add(_catalog);
  }

  Future<void> dispose() async {
    await _profiles.cancel();
    await _availability?.cancel();
    await _changes.close();
  }
}
