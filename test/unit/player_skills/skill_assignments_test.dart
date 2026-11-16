import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_skills/domain/skill_catalog.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';

class SkillStore implements SkillAssignmentStore {
  String? document;
  bool fail = false;
  @override
  Future<String?> read() async => document;
  @override
  Future<void> write(String document) async {
    if (fail) throw StateError('Disk unavailable');
    this.document = document;
  }
}

void main() {
  test('empty default, assignment persistence and fixed catalog', () async {
    final store = SkillStore();
    final repo = await SkillAssignmentRepository.open(
      store,
      profileExists: (_) => true,
    );
    expect(repo.catalog.values, isEmpty);
    expect(SkillId.values.length, 1);
    expect(skipRecoveryDuration, const Duration(seconds: 10));
    expect(SkillId.skipRecovery.description, contains('10 seconds'));
    await repo.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
    final reopened = await SkillAssignmentRepository.open(
      store,
      profileExists: (_) => true,
    );
    expect(reopened.catalog.has(ProfileId.p2, SkillId.skipRecovery), isTrue);
    expect(reopened.catalog.has(ProfileId.p1, SkillId.skipRecovery), isFalse);
    await repo.dispose();
    await reopened.dispose();
  });
  test('unknown IDs stay visible and inactive through a valid edit', () async {
    final store = SkillStore()
      ..document = jsonEncode({
        'version': 1,
        'profiles': {
          'p1': ['future-skill'],
        },
      });
    final repo = await SkillAssignmentRepository.open(
      store,
      profileExists: (_) => true,
    );
    expect(repo.catalog.has(ProfileId.p1, SkillId.skipRecovery), isFalse);
    expect(repo.catalog.unavailable(ProfileId.p1), ['future-skill']);
    await repo.setAssigned(ProfileId.p1, SkillId.skipRecovery, true);
    expect(
      SkillAssignmentRepository.decode(
        store.document,
      ).unavailable(ProfileId.p1),
      ['future-skill'],
    );
    await repo.dispose();
  });
  test(
    'failed writes roll back and unadded profiles cannot receive skills',
    () async {
      final store = SkillStore();
      final repo = await SkillAssignmentRepository.open(
        store,
        profileExists: (p) => p == ProfileId.p1,
      );
      final events = <SkillAssignments>[];
      final sub = repo.changes.listen(events.add);
      store.fail = true;
      await expectLater(
        repo.setAssigned(ProfileId.p1, SkillId.skipRecovery, true),
        throwsStateError,
      );
      expect(repo.catalog.values, isEmpty);
      expect(store.document, isNull);
      expect(events, isEmpty);
      store.fail = false;
      await expectLater(
        repo.setAssigned(ProfileId.p2, SkillId.skipRecovery, true),
        throwsFormatException,
      );
      await repo.setAssigned(ProfileId.p1, SkillId.skipRecovery, true);
      expect(events.length, 1);
      await sub.cancel();
      await repo.dispose();
    },
  );
  test('malformed data recovers visibly', () {
    for (final document in [
      '{',
      '{"version":9}',
      '{"version":1,"profiles":{"unknown":[],"p1":[3]}}',
    ]) {
      final result = SkillAssignmentRepository.decode(document);
      expect(result.values, isEmpty);
      expect(result.recoveryMessages, isNotEmpty);
    }
  });
}
