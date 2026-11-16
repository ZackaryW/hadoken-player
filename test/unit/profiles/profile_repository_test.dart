import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';

class MemoryProfileStore implements ProfileDocumentStore {
  String? document;
  bool fail = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<String?> read() async => document;
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

  test('three stable slots, three buttons, two durations and six actions', () {
    expect(repository.catalog.names, {
      ProfileId.p1: 'P1',
      ProfileId.p2: 'P2',
      ProfileId.p3: 'P3',
    });
    expect(InputButton.values.length, 3);
    expect(StrokeKind.values.length, 2);
    expect(PlayerAction.values.length, 6);
    expect(repository.catalog.bindings, isEmpty);
  });

  test(
    'rename and bindings survive restart without changing identity',
    () async {
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
      expect(jsonDecode(store.document!)['version'], 1);
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
      await repository.rename(ProfileId.p3, 'Chun-Li');
      expect(repository.catalog.names[ProfileId.p1], 'Ryu');
      expect(events.length, 1);
    },
  );

  test(
    'rejects identical complete combos across profiles and actions',
    () async {
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
          jsonDecode(ProfileRepository.encode(ProfileCatalog.empty())) as Map;
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
