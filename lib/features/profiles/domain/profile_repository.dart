import 'dart:async';
import 'dart:convert';

import 'profile_catalog.dart';
import 'package:troona/skills/registry.dart';

abstract interface class ProfileDocumentStore {
  Future<String?> read();

  /// Must throw on a failed write. A successful write replaces one document.
  Future<void> write(String document);
}

abstract interface class ProfileMigrationStore {
  Future<String?> readMigrationBackup();
  Future<void> writeMigrationBackup(String document);
}

final class ProfileRepository {
  final ProfileDocumentStore _store;
  ProfileCatalog _catalog;
  final _changes = StreamController<ProfileCatalog>.broadcast(sync: true);
  Future<void> _tail = Future.value();
  final Set<void Function(ProfileCatalog)> validators = {};
  ProfileCatalog? _pending;
  ProfileCatalog? get pendingCatalog => _pending;

  ProfileRepository._(this._store, this._catalog);

  static Future<ProfileRepository> open(ProfileDocumentStore store) async {
    final raw = await store.read();
    final catalog = decode(raw);
    if (_legacyVersion(raw)) {
      if (store is! ProfileMigrationStore) {
        throw StateError('Profile migration requires backup storage.');
      }
      final backups = store as ProfileMigrationStore;
      if (await backups.readMigrationBackup() == null) {
        await backups.writeMigrationBackup(raw!);
      }
      await store.write(encode(catalog));
    }
    return ProfileRepository._(store, catalog);
  }

  static bool _legacyVersion(String? raw) {
    try {
      final version = (jsonDecode(raw!) as Map)['version'];
      return version == 1 || version == 2;
    } catch (_) {
      return false;
    }
  }

  Future<void> restorePreMigrationBackup() {
    final result = _tail.then((_) async {
      final store = _store;
      if (store is! ProfileMigrationStore) {
        throw StateError('Backup storage is unavailable.');
      }
      final backup = await (store as ProfileMigrationStore)
          .readMigrationBackup();
      if (!_legacyVersion(backup)) {
        throw StateError('No valid pre-migration backup.');
      }
      final restored = decode(backup).withRevision(_catalog.revision + 1);
      for (final validate in validators) {
        validate(restored);
      }
      _pending = restored;
      try {
        await _store.write(backup!);
      } finally {
        _pending = null;
      }
      _catalog = restored;
      _changes.add(restored);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  ProfileCatalog get catalog => _catalog;
  Stream<ProfileCatalog> get changes => _changes.stream;

  Future<ProfileId> addProfile() async {
    late ProfileId added;
    await _update((current) {
      final available = ProfileId.values.where(
        (id) => !current.names.containsKey(id),
      );
      if (available.isEmpty) {
        throw const FormatException('Maximum three profiles.');
      }
      added = available.first;
      return ProfileCatalog(
        names: {...current.names, added: added.label},
        bindings: current.bindings,
        macros: current.macros,
        timing: current.timing,
      );
    });
    return added;
  }

  Future<void> rename(ProfileId profile, String name) => _update((current) {
    if (!current.names.containsKey(profile)) {
      throw const FormatException('Add this profile first.');
    }
    return ProfileCatalog(
      names: {...current.names, profile: name.trim()},
      bindings: current.bindings,
      macros: current.macros,
      timing: current.timing,
    );
  });

  Future<void> setBinding(
    ProfileId profile,
    PlayerAction action,
    List<Stroke>? strokes,
  ) {
    // Copy before queuing: caller-owned recorder lists may change meanwhile.
    final binding = strokes == null
        ? null
        : ActionBinding(profile, action, strokes);
    return _update((current) {
      if (!current.names.containsKey(profile)) {
        throw const FormatException('Add this profile first.');
      }
      return ProfileCatalog(
        names: current.names,
        bindings: [
          ...current.bindings.where(
            (b) => b.profile != profile || b.action != action,
          ),
          ?binding,
        ],
        timing: current.timing,
        macros: current.macros,
      );
    });
  }

  Future<void> setTiming(RecognitionTiming timing) => _update(
    (current) => ProfileCatalog(
      names: current.names,
      bindings: current.bindings,
      macros: current.macros,
      timing: timing,
    ),
  );

  Future<void> _update(ProfileCatalog Function(ProfileCatalog) change) {
    final result = _tail.then((_) async {
      final next = change(_catalog).withRevision(_catalog.revision + 1);
      for (final validate in validators) {
        validate(next);
      }
      _pending = next;
      try {
        await _store.write(encode(next));
      } finally {
        _pending = null;
      }
      _catalog = next;
      _changes.add(next);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> setSkillMacro(
    ProfileId profile,
    String skillKey,
    List<Stroke>? strokes,
  ) {
    final macro = strokes == null
        ? null
        : SkillMacroBinding(profile, skillKey, strokes);
    return _update((current) {
      if (!current.names.containsKey(profile)) {
        throw const FormatException('Add this profile first.');
      }
      return ProfileCatalog(
        names: current.names,
        bindings: current.bindings,
        timing: current.timing,
        macros: [
          ...current.macros.where(
            (m) => m.profile != profile || m.skillKey != skillKey,
          ),
          ?macro,
        ],
      );
    });
  }

  Future<void> dispose() async {
    await _tail;
    await _changes.close();
  }

  static String encode(ProfileCatalog catalog) => jsonEncode({
    'version': 3,
    'timing': {'holdMs': catalog.timing.holdMs, 'gapMs': catalog.timing.gapMs},
    'profiles': [
      for (final id in ProfileId.values.where(catalog.names.containsKey))
        {
          'id': id.name,
          'name': catalog.names[id],
          'bindings': {
            for (final binding in catalog.bindings.where(
              (b) => b.profile == id,
            ))
              binding.action.name: binding.strokes
                  .map((s) => s.toJson())
                  .toList(),
          },
          'skillMacros': {
            for (final macro in catalog.macros.where((m) => m.profile == id))
              macro.skillKey: macro.strokes.map((s) => s.toJson()).toList(),
          },
        },
    ],
  });

  static ProfileCatalog decode(String? document) {
    if (document == null) return ProfileCatalog.empty();
    final empty = ProfileCatalog.empty();
    final messages = <String>[];
    final names = {...empty.names};
    final bindings = <ActionBinding>[];
    final macros = <SkillMacroBinding>[];
    var timing = empty.timing;
    try {
      final json = jsonDecode(document) as Map;
      final legacy = json['version'] == 1;
      if (!legacy && json['version'] != 2 && json['version'] != 3) {
        throw const FormatException('Unsupported profile version.');
      }
      try {
        final raw = json['timing'] as Map;
        timing = RecognitionTiming(
          holdMs: raw['holdMs'] as int,
          gapMs: raw['gapMs'] as int,
        );
      } catch (_) {
        messages.add(
          'Invalid timing settings: restored 600 ms hold and 500 ms gap.',
        );
      }
      final seen = <ProfileId>{};
      final duplicateProfiles = <ProfileId>{};
      for (final raw in json['profiles'] as List) {
        try {
          final profile = raw as Map;
          final id = ProfileId.values.byName(profile['id'] as String);
          if (!seen.add(id)) {
            duplicateProfiles.add(id);
            messages.add(
              '${id.label} has duplicate saved entries; its bindings are inactive.',
            );
            continue;
          }
          final name = profile['name'];
          final entries = profile['bindings'] as Map;
          final customName =
              name is String &&
              name.trim().isNotEmpty &&
              name.trim() != id.label;
          // Version 1 always wrote all three slots, including unused defaults.
          if (legacy && id != ProfileId.p1 && !customName && entries.isEmpty) {
            continue;
          }
          names[id] = name is String && name.trim().isNotEmpty
              ? name.trim()
              : id.label;
          for (final entry in entries.entries) {
            try {
              bindings.add(
                ActionBinding(
                  id,
                  PlayerAction.values.byName(entry.key as String),
                  (entry.value as List).map(Stroke.fromJson),
                ),
              );
            } catch (_) {
              messages.add(
                '${id.label}: invalid saved action or combination is inactive.',
              );
            }
          }
          if (json['version'] == 3 && profile['skillMacros'] != null) {
            try {
              for (final entry in (profile['skillMacros'] as Map).entries) {
                try {
                  final macro = SkillMacroBinding(
                    id,
                    entry.key as String,
                    (entry.value as List).map(Stroke.fromJson),
                  );
                  macros.add(macro);
                  if (!skillDefinitions.any(
                    (d) => d.id.key == macro.skillKey,
                  )) {
                    messages.add(
                      '${id.label}: unknown skill ${macro.skillKey} remains saved and inactive.',
                    );
                  }
                } catch (_) {
                  messages.add(
                    '${id.label}: invalid saved skill macro is inactive.',
                  );
                }
              }
            } catch (_) {
              messages.add(
                '${id.label}: invalid saved skill macros are inactive.',
              );
            }
          }
        } catch (_) {
          messages.add('An invalid profile entry was ignored.');
        }
      }
      bindings.removeWhere((b) => duplicateProfiles.contains(b.profile));
      macros.removeWhere((b) => duplicateProfiles.contains(b.profile));
      final counts = <String, int>{};
      for (final binding in <ExecutableBinding>[...bindings, ...macros]) {
        counts.update(binding.comboKey, (n) => n + 1, ifAbsent: () => 1);
      }
      bool conflicts(ExecutableBinding b) {
        if (counts[b.comboKey]! <= 1) return false;
        messages.add(
          '${b.profile.label}: ${b.label} conflicts with another saved combo and is inactive.',
        );
        return true;
      }

      bindings.removeWhere(conflicts);
      macros.removeWhere(conflicts);
    } catch (_) {
      return ProfileCatalog(
        names: empty.names,
        bindings: const [],
        timing: empty.timing,
        recoveryMessages: const [
          'Saved profiles could not be read. Reconfigure bindings to recover.',
        ],
      );
    }
    return ProfileCatalog(
      names: names,
      bindings: bindings,
      macros: macros,
      timing: timing,
      recoveryMessages: messages,
    );
  }
}
