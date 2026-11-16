import 'dart:async';
import 'dart:convert';
import '../../profiles/domain/profile_catalog.dart';
import 'skill_catalog.dart';

abstract interface class SkillAssignmentStore {
  Future<String?> read();
  Future<void> write(String document);
}

final class SkillAssignments {
  final Map<ProfileId, Set<String>> values;
  final List<String> recoveryMessages;
  SkillAssignments(
    Map<ProfileId, Set<String>> values, [
    Iterable<String> messages = const [],
  ]) : values = Map.unmodifiable(
         values.map(
           (id, skills) => MapEntry(id, Set<String>.unmodifiable(skills)),
         ),
       ),
       recoveryMessages = List.unmodifiable(messages);
  bool has(ProfileId profile, SkillId skill) =>
      values[profile]?.contains(skill.key) ?? false;
  Iterable<String> unavailable(ProfileId profile) =>
      (values[profile] ?? <String>{}).where(
        (key) => !SkillId.values.any((id) => id.key == key),
      );
}

final class SkillAssignmentRepository {
  final SkillAssignmentStore _store;
  final bool Function(ProfileId) profileExists;
  SkillAssignments _catalog;
  final _changes = StreamController<SkillAssignments>.broadcast(sync: true);
  Future<void> _tail = Future.value();
  SkillAssignmentRepository._(this._store, this.profileExists, this._catalog);
  static Future<SkillAssignmentRepository> open(
    SkillAssignmentStore store, {
    required bool Function(ProfileId) profileExists,
  }) async => SkillAssignmentRepository._(
    store,
    profileExists,
    decode(await store.read()),
  );
  SkillAssignments get catalog => _catalog;
  Stream<SkillAssignments> get changes => _changes.stream;

  /// UI mutations must enter the dispatcher queue through SkillControls.
  Future<void> setAssigned(ProfileId profile, SkillId skill, bool assigned) {
    final result = _tail.then((_) async {
      if (!profileExists(profile))
        throw const FormatException('Add this profile first.');
      final values = {..._catalog.values};
      final selected = {...?values[profile]};
      assigned ? selected.add(skill.key) : selected.remove(skill.key);
      values[profile] = selected;
      final next = SkillAssignments(values);
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
  static SkillAssignments decode(String? document) {
    if (document == null) return SkillAssignments({});
    try {
      final raw = jsonDecode(document) as Map;
      if (raw['version'] != 1) throw const FormatException('Unknown version');
      final values = <ProfileId, Set<String>>{};
      final messages = <String>[];
      for (final entry in (raw['profiles'] as Map).entries) {
        try {
          final id = ProfileId.values.byName(entry.key as String);
          values[id] = (entry.value as List).cast<String>().toSet();
        } catch (_) {
          messages.add('An invalid skill assignment was ignored.');
        }
      }
      return SkillAssignments(values, messages);
    } catch (_) {
      return SkillAssignments({}, ['Saved skills could not be read.']);
    }
  }

  Future<void> dispose() async {
    await _tail;
    await _changes.close();
  }
}
