import 'dart:convert';
import 'package:troona/skills/skip_recovery/skip_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/registry.dart';
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
  test(
    'concurrent claims have one owner; removal permits persistent reassignment',
    () async {
      final store = SkillStore();
      final repo = await SkillAssignmentRepository.open(
        store,
        profileExists: (_) => true,
      );
      final events = <SkillAssignments>[];
      final sub = repo.changes.listen(events.add);
      final first = repo.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
      final second = expectLater(
        repo.setAssigned(ProfileId.p1, SkillId.skipRecovery, true),
        throwsA(
          isA<SkillAlreadyAssigned>().having(
            (e) => e.owner,
            'owner',
            ProfileId.p2,
          ),
        ),
      );
      await first;
      await second;
      expect(repo.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p2);
      expect(events.length, 1);
      expect(
        SkillAssignmentRepository.decode(
          store.document,
        ).ownerOf(SkillId.skipRecovery),
        ProfileId.p2,
      );
      store.fail = true;
      await expectLater(
        repo.setAssigned(ProfileId.p2, SkillId.skipRecovery, false),
        throwsStateError,
      );
      expect(repo.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p2);
      store.fail = false;
      await repo.setAssigned(ProfileId.p2, SkillId.skipRecovery, false);
      await repo.setAssigned(ProfileId.p1, SkillId.skipRecovery, true);
      final reopened = await SkillAssignmentRepository.open(
        store,
        profileExists: (_) => true,
      );
      expect(reopened.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p1);
      expect(reopened.catalog.has(ProfileId.p2, SkillId.skipRecovery), isFalse);
      await sub.cancel();
      await repo.dispose();
      await reopened.dispose();
    },
  );
  test(
    'legacy duplicates recover in stable added-profile order and preserve unknown IDs',
    () async {
      final store = SkillStore()
        ..document = jsonEncode({
          'version': 1,
          'profiles': {
            'p3': ['skip-recovery'],
            'p2': ['skip-recovery', 'future-skill'],
            'p1': ['skip-recovery', 'future-skill'],
          },
        });
      final decoded = SkillAssignmentRepository.decode(store.document);
      expect(decoded.ownerOf(SkillId.skipRecovery), ProfileId.p1);
      expect(decoded.has(ProfileId.p2, SkillId.skipRecovery), isFalse);
      expect(decoded.has(ProfileId.p3, SkillId.skipRecovery), isFalse);
      expect(decoded.unavailable(ProfileId.p2), ['future-skill']);
      expect(decoded.recoveryMessages.length, 2);
      final repo = await SkillAssignmentRepository.open(
        store,
        profileExists: (p) => p != ProfileId.p1,
      );
      expect(repo.catalog.ownerOf(SkillId.skipRecovery), ProfileId.p2);
      expect(repo.catalog.recoveryMessages, isNotEmpty);
      await repo.setAssigned(ProfileId.p2, SkillId.skipRecovery, true);
      final saved = SkillAssignmentRepository.decode(store.document);
      expect(saved.recoveryMessages, isEmpty);
      expect(saved.unavailable(ProfileId.p2), ['future-skill']);
      await repo.dispose();
    },
  );
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
