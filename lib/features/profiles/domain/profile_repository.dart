import 'dart:async';
import 'dart:convert';

import 'profile_catalog.dart';

abstract interface class ProfileDocumentStore {
  Future<String?> read();

  /// Must throw on a failed write. A successful write replaces one document.
  Future<void> write(String document);
}

final class ProfileRepository {
  final ProfileDocumentStore _store;
  ProfileCatalog _catalog;
  final _changes = StreamController<ProfileCatalog>.broadcast(sync: true);
  Future<void> _tail = Future.value();

  ProfileRepository._(this._store, this._catalog);

  static Future<ProfileRepository> open(ProfileDocumentStore store) async =>
      ProfileRepository._(store, decode(await store.read()));

  ProfileCatalog get catalog => _catalog;
  Stream<ProfileCatalog> get changes => _changes.stream;

  Future<void> rename(ProfileId profile, String name) => _update(
    (current) => ProfileCatalog(
      names: {...current.names, profile: name.trim()},
      bindings: current.bindings,
      timing: current.timing,
    ),
  );

  Future<void> setBinding(
    ProfileId profile,
    PlayerAction action,
    List<Stroke>? strokes,
  ) {
    // Copy before queuing: caller-owned recorder lists may change meanwhile.
    final binding = strokes == null
        ? null
        : ActionBinding(profile, action, strokes);
    return _update(
      (current) => ProfileCatalog(
        names: current.names,
        bindings: [
          ...current.bindings.where(
            (b) => b.profile != profile || b.action != action,
          ),
          ?binding,
        ],
        timing: current.timing,
      ),
    );
  }

  Future<void> setTiming(RecognitionTiming timing) => _update(
    (current) => ProfileCatalog(
      names: current.names,
      bindings: current.bindings,
      timing: timing,
    ),
  );

  Future<void> _update(ProfileCatalog Function(ProfileCatalog) change) {
    final result = _tail.then((_) async {
      final next = change(
        _catalog,
      ); // Validate against the latest committed catalog.
      await _store.write(encode(next));
      _catalog = next;
      _changes.add(next);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> dispose() async {
    await _tail;
    await _changes.close();
  }

  static String encode(ProfileCatalog catalog) => jsonEncode({
    'version': 1,
    'timing': {'holdMs': catalog.timing.holdMs, 'gapMs': catalog.timing.gapMs},
    'profiles': [
      for (final id in ProfileId.values)
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
        },
    ],
  });

  static ProfileCatalog decode(String? document) {
    if (document == null) return ProfileCatalog.empty();
    final empty = ProfileCatalog.empty();
    final messages = <String>[];
    final names = {...empty.names};
    final bindings = <ActionBinding>[];
    var timing = empty.timing;
    try {
      final json = jsonDecode(document) as Map;
      if (json['version'] != 1) {
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
          if (name is String && name.trim().isNotEmpty) names[id] = name.trim();
          final entries = profile['bindings'] as Map;
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
        } catch (_) {
          messages.add('An invalid profile entry was ignored.');
        }
      }
      bindings.removeWhere((b) => duplicateProfiles.contains(b.profile));
      final counts = <String, int>{};
      for (final binding in bindings) {
        counts.update(binding.comboKey, (n) => n + 1, ifAbsent: () => 1);
      }
      bindings.removeWhere((b) {
        if (counts[b.comboKey]! <= 1) return false;
        messages.add(
          '${b.profile.label}: ${b.action.label} conflicts with another saved combo and is inactive.',
        );
        return true;
      });
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
      timing: timing,
      recoveryMessages: messages,
    );
  }
}
