import 'dart:async';
import 'dart:convert';
import '../../profiles/domain/profile_catalog.dart';
import 'package:troona/skills/registry.dart';

abstract interface class SkillAssignmentStore {
  Future<String?> read();
  Future<void> write(String document);
}

final class SkillAlreadyAssigned implements Exception {
  final SkillId skill;
  final ProfileId owner;
  const SkillAlreadyAssigned(this.skill, this.owner);
  @override
  String toString() => '${skill.label} belongs to ${owner.label}.';
}

final class SkillAssignments {
  final Map<ProfileId, Set<String>> values;
  final List<String> recoveryMessages;
  final Set<String> knownKeys;
  SkillAssignments(
    Map<ProfileId, Set<String>> values, [
    Iterable<String> messages = const [],
    Iterable<String>? knownKeys,
  ]) : values = Map.unmodifiable(
         values.map(
           (id, skills) => MapEntry(id, Set<String>.unmodifiable(skills)),
         ),
       ),
       recoveryMessages = List.unmodifiable(messages),
       knownKeys = Set.unmodifiable(
         knownKeys ?? skillDefinitions.map((d) => d.id.key),
       );
  bool has(ProfileId profile, SkillId skill) =>
      values[profile]?.contains(skill.key) ?? false;
  ProfileId? ownerOf(SkillId skill) {
    for (final profile in ProfileId.values) {
      if (has(profile, skill)) return profile;
    }
    return null;
  }

  Iterable<String> unavailable(ProfileId profile) =>
      (values[profile] ?? <String>{}).where((key) => !knownKeys.contains(key));
}

final class SkillAssignmentRepository {
  final SkillAssignmentStore _store;
  final bool Function(ProfileId) profileExists;
  final List<SkillDefinition> definitions;
  SkillAssignments _catalog;
  final _changes = StreamController<SkillAssignments>.broadcast(sync: true);
  Future<void> _tail = Future.value();
  SkillAssignmentRepository._(
    this._store,
    this.profileExists,
    this._catalog,
    this.definitions,
  );
  static Future<SkillAssignmentRepository> open(
    SkillAssignmentStore store, {
    required bool Function(ProfileId) profileExists,
    Iterable<SkillDefinition> definitions = skillDefinitions,
  }) async {
    final registered = List<SkillDefinition>.unmodifiable(definitions);
    if (registered.map((d) => d.id).toSet().length != registered.length) {
      throw ArgumentError('Duplicate skill identity.');
    }
    return SkillAssignmentRepository._(
      store,
      profileExists,
      decode(
        await store.read(),
        profileExists: profileExists,
        definitions: registered,
      ),
      registered,
    );
  }

  SkillAssignments get catalog => _catalog;
  Stream<SkillAssignments> get changes => _changes.stream;

  /// UI mutations must enter the dispatcher queue through SkillControls.
  Future<void> setAssigned(ProfileId profile, SkillId skill, bool assigned) {
    final result = _tail.then((_) async {
      if (!profileExists(profile)) {
        throw const FormatException('Add this profile first.');
      }
      if (assigned && !definitions.any((d) => d.id == skill)) {
        throw const FormatException('This skill is unavailable.');
      }
      final owner = _catalog.ownerOf(skill);
      if (assigned && owner != null && owner != profile) {
        throw SkillAlreadyAssigned(skill, owner);
      }
      final values = {..._catalog.values};
      final selected = {...?values[profile]};
      assigned ? selected.add(skill.key) : selected.remove(skill.key);
      values[profile] = selected;
      final next = SkillAssignments(
        values,
        const [],
        definitions.map((d) => d.id.key),
      );
      await _store.write(encode(next));
      _catalog = next;
      _changes.add(next);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static String encode(SkillAssignments catalog) => jsonEncode({
    'version': 1,
    'profiles': {
      for (final entry in catalog.values.entries)
        entry.key.name: entry.value.toList(),
    },
  });
  static SkillAssignments decode(
    String? document, {
    bool Function(ProfileId)? profileExists,
    Iterable<SkillDefinition> definitions = skillDefinitions,
  }) {
    final registered = definitions.toList();
    final known = registered.map((d) => d.id.key).toList();
    if (document == null) return SkillAssignments({}, const [], known);
    try {
      final raw = jsonDecode(document) as Map;
      if (raw['version'] != 1) throw const FormatException('Unknown version');
      final values = <ProfileId, Set<String>>{};
      final messages = <String>[];
      for (final entry in (raw['profiles'] as Map).entries) {
        try {
          final id = ProfileId.values.byName(entry.key as String);
          if (profileExists != null && !profileExists(id)) {
            messages.add('Skills for an unadded profile were ignored.');
            continue;
          }
          values[id] = (entry.value as List).cast<String>().toSet();
        } catch (_) {
          messages.add('An invalid skill assignment was ignored.');
        }
      }
      for (final definition in registered) {
        final skill = definition.id;
        ProfileId? owner;
        for (final profile in ProfileId.values) {
          if (!(values[profile]?.contains(skill.key) ?? false)) continue;
          if (owner == null) {
            owner = profile;
          } else {
            values[profile]!.remove(skill.key);
            messages.add(
              '${definition.label} kept on ${owner.label}; duplicate on ${profile.label} removed.',
            );
          }
        }
      }
      return SkillAssignments(values, messages, known);
    } catch (_) {
      return SkillAssignments({}, ['Saved skills could not be read.'], known);
    }
  }

  Future<void> dispose() async {
    await _tail;
    await _changes.close();
  }
}
