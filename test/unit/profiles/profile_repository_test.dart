import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';

class MemoryProfileStore
    implements ProfileDocumentStore, ProfileMigrationStore {
  String? document;
  String? backup;
  bool failBackup = false;
  bool fail = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<String?> read() async => document;
  @override
  Future<String?> readMigrationBackup() async => backup;
  @override
  Future<void> writeMigrationBackup(String value) async {
    if (failBackup) throw StateError('Backup unavailable');
    backup = value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    await gate?.future;
    if (fail) throw StateError('Disk unavailable');
    document = value;
  }
}

const forward = Stroke(InputButton.forward, StrokeKind.tap);
const backHold = Stroke(InputButton.backward, StrokeKind.hold);
const pause = Stroke(InputButton.pause, StrokeKind.tap);

void main() {
  late MemoryProfileStore store;
  late ProfileRepository repository;
  setUp(() async {
    store = MemoryProfileStore();
    repository = await ProfileRepository.open(store);
  });
  tearDown(() => repository.dispose());

  test(
    'manual macros share complete-combo reservations and survive ordinary edits',
    () async {
      await repository.setSkillMacro(ProfileId.p1, 'manual-test', [
        forward,
        backHold,
      ]);
      await repository.addProfile();
      await repository.rename(ProfileId.p1, 'Ryu');
      await repository.setTiming(RecognitionTiming(holdMs: 700, gapMs: 450));
      await repository.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
        forward,
      ]);
      await expectLater(
        repository.setBinding(ProfileId.p2, PlayerAction.stop, [
          forward,
          backHold,
        ]),
        throwsA(isA<BindingConflict>()),
      );
      await expectLater(
        repository.setSkillMacro(ProfileId.p2, 'another', [forward, backHold]),
        throwsA(isA<BindingConflict>()),
      );
      final reopened = await ProfileRepository.open(store);
      addTearDown(reopened.dispose);
      expect(reopened.catalog.macros.single.strokes, [forward, backHold]);
      expect(reopened.catalog.macros.single.skillKey, 'manual-test');
      expect(reopened.catalog.names[ProfileId.p1], 'Ryu');
      expect(reopened.catalog.timing.holdMs, 700);
      expect(
        reopened.catalog.recoveryMessages.join(),
        contains('unknown skill'),
      );
      await reopened.setSkillMacro(ProfileId.p1, 'manual-test', null);
      await reopened.setBinding(ProfileId.p2, PlayerAction.stop, [
        forward,
        backHold,
      ]);
      expect(reopened.catalog.macros, isEmpty);
    },
  );

  test(
    'legacy migration backs up before writing v3 and supports exact rollback',
    () async {
      for (final version in [1, 2]) {
        final legacy =
            jsonDecode(
                  ProfileRepository.encode(
                    ProfileCatalog(
                      names: {ProfileId.p1: 'Ryu', ProfileId.p2: 'Ken'},
                      bindings: [
                        ActionBinding(ProfileId.p2, PlayerAction.nextTrack, [
                          forward,
                        ]),
                      ],
                      timing: RecognitionTiming(holdMs: 750, gapMs: 420),
                    ),
                  ),
                )
                as Map;
        legacy['version'] = version;
        final original = jsonEncode(legacy);
        final legacyStore = MemoryProfileStore()..document = original;
        final migrated = await ProfileRepository.open(legacyStore);
        expect(legacyStore.backup, original);
        expect(jsonDecode(legacyStore.document!)['version'], 3);
        expect(migrated.catalog.names[ProfileId.p2], 'Ken');
        expect(migrated.catalog.bindings.single.profile, ProfileId.p2);
        expect(migrated.catalog.timing.gapMs, 420);
        expect(migrated.catalog.macros, isEmpty);
        await migrated.setSkillMacro(ProfileId.p1, 'manual', [backHold]);
        await migrated.restorePreMigrationBackup();
        expect(legacyStore.document, original);
        expect(migrated.catalog.macros, isEmpty);
        expect(legacyStore.backup, original);
        await migrated.dispose();
      }
    },
  );

  test(
    'backup or migration write failure cannot destroy the original',
    () async {
      final raw =
          jsonDecode(ProfileRepository.encode(ProfileCatalog.empty())) as Map;
      raw['version'] = 2;
      final original = jsonEncode(raw);
      final legacyStore = MemoryProfileStore()
        ..document = original
        ..failBackup = true;
      await expectLater(ProfileRepository.open(legacyStore), throwsStateError);
      expect(legacyStore.document, original);
      expect(legacyStore.backup, isNull);
      legacyStore.failBackup = false;
      legacyStore.fail = true;
      await expectLater(ProfileRepository.open(legacyStore), throwsStateError);
      expect(legacyStore.document, original);
      expect(legacyStore.backup, original);
      legacyStore.fail = false;
      final migrated = await ProfileRepository.open(legacyStore);
      await migrated.dispose();
      expect(legacyStore.backup, original);
    },
  );

  test(
    'corrupt and duplicate macros are inactive; unknown valid macros survive',
    () {
      final raw =
          jsonDecode(ProfileRepository.encode(ProfileCatalog.empty())) as Map;
      raw['profiles'][0]['bindings'] = {
        'nextTrack': [forward.toJson()],
      };
      raw['profiles'][0]['skillMacros'] = {
        'skip-recovery': [forward.toJson()],
        'unknown': [backHold.toJson()],
        'corrupt': [],
        '': [pause.toJson()],
      };
      final recovered = ProfileRepository.decode(jsonEncode(raw));
      expect(recovered.bindings, isEmpty);
      expect(recovered.macros.single.skillKey, 'unknown');
      expect(recovered.recoveryMessages.join(), contains('inactive'));
      expect(
        ProfileRepository.decode(
          ProfileRepository.encode(recovered),
        ).macros.single.skillKey,
        'unknown',
      );
    },
  );

  test('starts with P1, three buttons, two durations and six actions', () {
    expect(repository.catalog.names, {ProfileId.p1: 'P1'});
    expect(InputButton.values.length, 3);
    expect(StrokeKind.values.length, 2);
    expect(PlayerAction.values.length, 6);
    expect(repository.catalog.bindings, isEmpty);
  });

  test(
    'rename and bindings survive restart without changing identity',
    () async {
      await repository.addProfile();
      await repository.rename(ProfileId.p2, '  Ken  ');
      await repository.setBinding(ProfileId.p2, PlayerAction.nextTrack, [
        forward,
        backHold,
      ]);
      final reopened = await ProfileRepository.open(store);
      addTearDown(reopened.dispose);
      expect(reopened.catalog.names[ProfileId.p2], 'Ken');
      final binding = reopened.catalog.bindings.single;
      expect(binding.profile, ProfileId.p2);
      expect(binding.action, PlayerAction.nextTrack);
      expect(binding.strokes, [forward, backHold]);
      expect(jsonDecode(store.document!)['version'], 3);
    },
  );

  test(
    'failed write leaves memory, persisted data and observers unchanged',
    () async {
      await repository.rename(ProfileId.p1, 'Ryu');
      final before = store.document;
      final events = <ProfileCatalog>[];
      final sub = repository.changes.listen(events.add);
      addTearDown(sub.cancel);
      store.fail = true;
      await expectLater(
        repository.rename(ProfileId.p1, 'Lost'),
        throwsStateError,
      );
      expect(repository.catalog.names[ProfileId.p1], 'Ryu');
      expect(store.document, before);
      expect(events, isEmpty);
      store.fail = false;
      await repository.rename(ProfileId.p1, 'Ryu');
      expect(repository.catalog.names[ProfileId.p1], 'Ryu');
      expect(events.length, 1);
    },
  );

  test(
    'rejects identical complete combos across profiles and actions',
    () async {
      await repository.addProfile();
      await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
        forward,
      ]);
      for (final profile in [ProfileId.p1, ProfileId.p2]) {
        await expectLater(
          repository.setBinding(profile, PlayerAction.stop, [forward]),
          throwsA(
            isA<BindingConflict>().having(
              (e) => e.owner.profile,
              'owner',
              ProfileId.p1,
            ),
          ),
        );
      }
      expect(repository.catalog.bindings.length, 1);
    },
  );

  test(
    'prefixes and tap versus hold are distinct, replacing frees old combo',
    () async {
      await repository.addProfile();
      await repository.addProfile();
      await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
        forward,
      ]);
      await repository.setBinding(ProfileId.p2, PlayerAction.stop, [
        forward,
        backHold,
      ]);
      expect(
        repository.catalog
            .sharedPrefixes(repository.catalog.bindings.first)
            .length,
        1,
      );
      await repository.setBinding(ProfileId.p1, PlayerAction.nextTrack, [
        backHold,
      ]);
      await repository.setBinding(ProfileId.p3, PlayerAction.togglePlayback, [
        forward,
      ]);
      await repository.setBinding(ProfileId.p2, PlayerAction.stop, null);
      expect(
        repository.catalog.bindingFor(ProfileId.p2, PlayerAction.stop),
        isNull,
      );
      expect(repository.catalog.bindings.length, 2);
    },
  );

  test(
    'competing claims validate serially after the first write commits',
    () async {
      await repository.addProfile();
      store.writes = 0;
      store.gate = Completer<void>();
      final first = repository.setBinding(
        ProfileId.p1,
        PlayerAction.nextTrack,
        [forward],
      );
      final second = repository.setBinding(ProfileId.p2, PlayerAction.stop, [
        forward,
      ]);
      final rejection = expectLater(second, throwsA(isA<BindingConflict>()));
      await pumpEventQueue();
      expect(repository.catalog.bindings, isEmpty);
      expect(store.writes, 1);
      store.gate!.complete();
      await first;
      await rejection;
      expect(store.writes, 1);
      expect(repository.catalog.bindings.single.profile, ProfileId.p1);
    },
  );

  test(
    'competing adds persist two unique slots and enforce the limit',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          repository.addProfile().then<Object>(
            (id) => id,
            onError: (Object e) => e,
          ),
      ]);
      expect(results.take(2), [ProfileId.p2, ProfileId.p3]);
      expect(results.last, isA<FormatException>());
      expect(store.writes, 2);
      final reopened = await ProfileRepository.open(store);
      addTearDown(reopened.dispose);
      expect(reopened.catalog.names.keys, ProfileId.values);
    },
  );

  test('failed add does not publish or consume a slot', () async {
    final events = <ProfileCatalog>[];
    final sub = repository.changes.listen(events.add);
    addTearDown(sub.cancel);
    store.fail = true;
    await expectLater(repository.addProfile(), throwsStateError);
    expect(repository.catalog.names.keys, [ProfileId.p1]);
    expect(store.document, isNull);
    expect(events, isEmpty);
    store.fail = false;
    expect(await repository.addProfile(), ProfileId.p2);
    expect(events.length, 1);
  });

  test('unadded profiles cannot be renamed, bound or cleared', () async {
    await expectLater(
      repository.rename(ProfileId.p2, 'Ken'),
      throwsFormatException,
    );
    await expectLater(
      repository.setBinding(ProfileId.p2, PlayerAction.stop, [forward]),
      throwsFormatException,
    );
    await expectLater(
      repository.setBinding(ProfileId.p2, PlayerAction.stop, null),
      throwsFormatException,
    );
    expect(store.writes, 0);
  });

  test(
    'legacy defaults disappear while configured players survive migration',
    () {
      final raw =
          jsonDecode(
                ProfileRepository.encode(
                  ProfileCatalog(
                    names: {for (final id in ProfileId.values) id: id.label},
                    bindings: [],
                    timing: RecognitionTiming(),
                  ),
                ),
              )
              as Map;
      raw['version'] = 1;
      expect(ProfileRepository.decode(jsonEncode(raw)).names.keys, [
        ProfileId.p1,
      ]);
      raw['profiles'][1]['bindings'] = {
        'nextTrack': [forward.toJson()],
      };
      raw['profiles'][2]['name'] = 'Chun-Li';
      final migrated = ProfileRepository.decode(jsonEncode(raw));
      expect(migrated.names.keys, ProfileId.values);
      expect(migrated.bindings.single.profile, ProfileId.p2);
      expect(migrated.names[ProfileId.p3], 'Chun-Li');
      expect(
        ProfileRepository.decode(ProfileRepository.encode(migrated)).names,
        migrated.names,
      );
    },
  );

  test('caller cannot mutate a queued binding', () async {
    final strokes = [forward];
    final save = repository.setBinding(
      ProfileId.p1,
      PlayerAction.stop,
      strokes,
    );
    strokes.add(backHold);
    await save;
    expect(repository.catalog.bindings.single.strokes, [forward]);
    expect(
      () => repository.catalog.bindings.single.strokes.add(pause),
      throwsUnsupportedError,
    );
  });

  test('one through five strokes only, names cannot be empty', () async {
    for (final size in [0, 6]) {
      expect(
        () => repository.setBinding(
          ProfileId.p1,
          PlayerAction.stop,
          List.filled(size, forward),
        ),
        throwsFormatException,
      );
    }
    await repository.setBinding(
      ProfileId.p1,
      PlayerAction.stop,
      List.filled(5, forward),
    );
    await expectLater(
      repository.rename(ProfileId.p1, ' '),
      throwsFormatException,
    );
    expect(repository.catalog.names[ProfileId.p1], 'P1');
  });

  test(
    'timing is shared, persisted, positive and absent from combo identity',
    () async {
      expect(repository.catalog.timing.holdMs, 600);
      expect(repository.catalog.timing.gapMs, 500);
      await repository.setBinding(ProfileId.p1, PlayerAction.stop, [forward]);
      final identity = repository.catalog.bindings.single.comboKey;
      await repository.setTiming(RecognitionTiming(holdMs: 850, gapMs: 750));
      final recovered = ProfileRepository.decode(store.document);
      expect(recovered.timing.holdMs, 850);
      expect(recovered.timing.gapMs, 750);
      expect(recovered.bindings.single.comboKey, identity);
      expect(() => RecognitionTiming(holdMs: 0), throwsFormatException);
      expect(() => RecognitionTiming(gapMs: -1), throwsFormatException);
    },
  );

  test(
    'all duplicate members and invalid bindings disabled, valid data survives',
    () {
      final raw =
          jsonDecode(
                ProfileRepository.encode(
                  ProfileCatalog(
                    names: {for (final id in ProfileId.values) id: id.label},
                    bindings: [],
                    timing: RecognitionTiming(),
                  ),
                ),
              )
              as Map;
      final profiles = raw['profiles'] as List;
      profiles[0]['bindings'] = {
        'nextTrack': [forward.toJson()],
      };
      profiles[1]['bindings'] = {
        'stop': [forward.toJson()],
      };
      profiles[2]['bindings'] = {
        'togglePlayback': [pause.toJson()],
        'nextTrack': List.filled(6, backHold.toJson()),
        'seekForward': [
          {'button': 'unknown', 'kind': 'tap'},
        ],
      };
      final restored = ProfileRepository.decode(jsonEncode(raw));
      expect(restored.bindings.single.action, PlayerAction.togglePlayback);
      expect(restored.bindings.single.profile, ProfileId.p3);
      expect(restored.recoveryMessages.length, 4);
    },
  );

  test(
    'malformed document and timing recover visibly without active ambiguity',
    () {
      for (final value in ['{', '{"version":99}', '[]']) {
        final recovered = ProfileRepository.decode(value);
        expect(recovered.bindings, isEmpty);
        expect(recovered.recoveryMessages, isNotEmpty);
      }
      final raw =
          jsonDecode(ProfileRepository.encode(ProfileCatalog.empty())) as Map;
      raw['timing'] = {'holdMs': 0, 'gapMs': 500};
      final recovered = ProfileRepository.decode(jsonEncode(raw));
      expect(recovered.timing.holdMs, 600);
      expect(recovered.recoveryMessages, isNotEmpty);
    },
  );
}
