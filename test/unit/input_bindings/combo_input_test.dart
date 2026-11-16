import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';

const f = Stroke(InputButton.forward, StrokeKind.tap);
const bh = Stroke(InputButton.backward, StrokeKind.hold);
const p = Stroke(InputButton.pause, StrokeKind.tap);

class FakeInputClock implements InputClock {
  final FakeAsync time;
  Duration offset = Duration.zero;
  FakeInputClock(this.time);
  @override
  Duration get elapsed => time.elapsed + offset;
  @override
  CancelInputTimer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback).cancel;
}

ProfileCatalog catalog([List<ActionBinding>? bindings]) => ProfileCatalog(
  names: {for (final id in ProfileId.values) id: id.label},
  bindings:
      bindings ??
      [
        ActionBinding(ProfileId.p1, PlayerAction.nextTrack, [f]),
        ActionBinding(ProfileId.p2, PlayerAction.nextTrack, [f, bh]),
      ],
  timing: RecognitionTiming(),
);

void main() {
  test(
    'accessible holds use the same threshold and cannot survive cancellation',
    () {
      fakeAsync((time) {
        final input = ComboInput(
          catalog: catalog(),
          clock: FakeInputClock(time),
          mode: InputMode.recording,
          onRuntimeMatch: (_) => fail('recording dispatched'),
        );
        input.semanticPress(InputButton.backward, hold: true);
        time.elapse(const Duration(milliseconds: 599));
        expect(input.strokes, isEmpty);
        time.elapse(const Duration(milliseconds: 1));
        expect(input.strokes, [bh]);
        input.semanticPress(InputButton.forward, hold: true);
        input.cancel();
        input.semanticPress(InputButton.pause);
        time.elapse(const Duration(seconds: 1));
        expect(input.strokes, [bh, p]);
        input.dispose();
        expect(time.pendingTimers, isEmpty);
      });
    },
  );
  void stroke(
    ComboInput input,
    FakeAsync time,
    InputButton button, [
    int ms = 100,
    int pointer = 1,
  ]) {
    input.down(button, pointer);
    time.elapse(Duration(milliseconds: ms));
    input.up(pointer);
  }

  test(
    'retains bounded monotonic stroke measurements without changing identity',
    () {
      fakeAsync((time) {
        final matches = <ComboMatch>[];
        final input = ComboInput(
          catalog: catalog(),
          clock: FakeInputClock(time),
          onRuntimeMatch: matches.add,
        );
        stroke(input, time, InputButton.forward, 100);
        expect(input.observations.single.downAt, Duration.zero);
        expect(
          input.observations.single.upAt,
          const Duration(milliseconds: 100),
        );
        expect(input.observations.single.gapBefore, isNull);
        time.elapse(const Duration(milliseconds: 250));
        stroke(input, time, InputButton.backward, 700);
        final match = matches.single;
        expect(match.binding.profile, ProfileId.p2);
        expect(match.observations.map((o) => o.stroke), [f, bh]);
        expect(
          match.observations.last.downAt,
          const Duration(milliseconds: 350),
        );
        expect(
          match.observations.last.upAt,
          const Duration(milliseconds: 1050),
        );
        expect(
          match.observations.last.gapBefore,
          const Duration(milliseconds: 250),
        );
        expect(
          match.observations.last.heldFor,
          const Duration(milliseconds: 700),
        );
        expect(() => match.observations.clear(), throwsUnsupportedError);
        expect(input.observations, isEmpty);
        stroke(input, time, InputButton.forward);
        input.cancel();
        expect(input.observations, isEmpty);
        input.dispose();
      });
    },
  );

  test('mismatch result retains only matched prefix observations', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final input = ComboInput(
        catalog: catalog(),
        clock: FakeInputClock(time),
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.forward);
      stroke(input, time, InputButton.pause);
      expect(matches.single.observations.map((o) => o.stroke), [f]);
      expect(input.observations, isEmpty);
      input.dispose();
    });
  });

  test('599 ms is a tap; equality is a hold, emitted only once on release', () {
    fakeAsync((time) {
      final input = ComboInput(
        catalog: catalog(),
        clock: FakeInputClock(time),
        mode: InputMode.recording,
        onRuntimeMatch: (_) => fail('recording dispatched'),
      );
      stroke(input, time, InputButton.forward, 599);
      input.down(InputButton.backward, 2);
      time.elapse(const Duration(milliseconds: 600));
      expect(input.holding, isTrue);
      expect(input.strokes, [f]);
      input.up(2);
      input.up(2);
      expect(input.strokes, [f, bh]);
      input.dispose();
    });
  });

  test(
    'repeated downs and stale releases cannot add strokes or reset hold time',
    () {
      fakeAsync((time) {
        final input = ComboInput(
          catalog: catalog(),
          clock: FakeInputClock(time),
          mode: InputMode.recording,
          onRuntimeMatch: (_) => fail('recording dispatched'),
        );
        input.down(InputButton.backward, 7);
        time.elapse(const Duration(milliseconds: 400));
        input.down(InputButton.backward, 7);
        input.up(99);
        time.elapse(const Duration(milliseconds: 200));
        input.up(7);
        expect(input.strokes, [bh]);
        input.down(InputButton.forward, 8);
        input.cancel();
        input.up(8);
        expect(input.strokes, [bh]);
        input.dispose();
      });
    },
  );

  test('overlap cancels the attempt until all pointers release', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final input = ComboInput(
        catalog: catalog(),
        clock: FakeInputClock(time),
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.forward);
      input.down(InputButton.backward, 1);
      input.down(InputButton.pause, 2);
      input.up(1);
      input.down(InputButton.forward, 3);
      input.up(2);
      input.up(3);
      time.elapse(const Duration(seconds: 2));
      expect(matches, isEmpty);
      expect(input.strokes, isEmpty);
      stroke(input, time, InputButton.forward);
      time.elapse(const Duration(milliseconds: 500));
      expect(matches.single.binding.profile, ProfileId.p1);
      input.dispose();
    });
  });

  test('terminal match is immediate and ownership is global', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final input = ComboInput(
        catalog: catalog([
          ActionBinding(ProfileId.p3, PlayerAction.stop, [p]),
        ]),
        clock: FakeInputClock(time),
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.pause);
      expect(matches.single.binding.profile, ProfileId.p3);
      expect(matches.single.recognizedAt, const Duration(milliseconds: 100));
      time.elapse(const Duration(seconds: 10));
      expect(matches.length, 1);
      input.dispose();
    });
  });

  test('short prefix waits 500 ms after release, then emits once', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final input = ComboInput(
        catalog: catalog(),
        clock: FakeInputClock(time),
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.forward);
      time.elapse(const Duration(milliseconds: 499));
      expect(matches, isEmpty);
      expect(input.waitingForContinuation, isTrue);
      time.elapse(const Duration(milliseconds: 1));
      expect(matches.single.binding.profile, ProfileId.p1);
      expect(input.strokes, isEmpty);
      input.dispose();
    });
  });

  test('timely hold can span the gap; longest completed match wins', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final input = ComboInput(
        catalog: catalog(),
        clock: FakeInputClock(time),
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.forward);
      time.elapse(const Duration(milliseconds: 499));
      input.down(InputButton.backward, 2);
      time.elapse(const Duration(seconds: 3));
      expect(matches, isEmpty);
      input.up(2);
      expect(matches.single.binding.profile, ProfileId.p2);
      expect(matches.single.binding.strokes, [f, bh]);
      time.elapse(const Duration(seconds: 3));
      expect(matches.length, 1);
      input.dispose();
    });
  });

  test('exact deadline expires before down even if its timer has not run', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final clock = FakeInputClock(time);
      final input = ComboInput(
        catalog: catalog(),
        clock: clock,
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.forward);
      time.elapse(const Duration(milliseconds: 499));
      clock.offset = const Duration(milliseconds: 1);
      input.down(InputButton.backward, 2);
      expect(matches.single.binding.profile, ProfileId.p1);
      time.elapse(const Duration(milliseconds: 600));
      input.up(2);
      expect(matches.length, 1);
      input.dispose();
    });
  });

  test(
    'mismatch falls back to completed prefix, without replaying mismatch',
    () {
      fakeAsync((time) {
        final matches = <ComboMatch>[];
        final input = ComboInput(
          catalog: catalog([
            ...catalog().bindings,
            ActionBinding(ProfileId.p3, PlayerAction.stop, [p]),
          ]),
          clock: FakeInputClock(time),
          onRuntimeMatch: matches.add,
        );
        stroke(input, time, InputButton.forward);
        stroke(input, time, InputButton.pause);
        expect(matches.single.binding.profile, ProfileId.p1);
        expect(input.strokes, isEmpty);
        stroke(input, time, InputButton.pause);
        expect(matches.last.binding.profile, ProfileId.p3);
        input.dispose();
      });
    },
  );

  test('timeout/mismatch with no complete candidate reset without action', () {
    fakeAsync((time) {
      final matches = <ComboMatch>[];
      final input = ComboInput(
        catalog: catalog([
          ActionBinding(ProfileId.p2, PlayerAction.stop, [f, bh]),
        ]),
        clock: FakeInputClock(time),
        onRuntimeMatch: matches.add,
      );
      stroke(input, time, InputButton.forward);
      time.elapse(const Duration(milliseconds: 500));
      expect(matches, isEmpty);
      expect(input.strokes, isEmpty);
      stroke(input, time, InputButton.forward);
      stroke(input, time, InputButton.pause);
      expect(matches, isEmpty);
      expect(input.strokes, isEmpty);
      input.dispose();
    });
  });

  test(
    'five-stroke terminal match fires once; six-stroke recording is rejected',
    () {
      fakeAsync((time) {
        final matches = <ComboMatch>[];
        final input = ComboInput(
          catalog: catalog([
            ActionBinding(ProfileId.p1, PlayerAction.stop, List.filled(5, f)),
          ]),
          clock: FakeInputClock(time),
          onRuntimeMatch: matches.add,
        );
        for (var i = 0; i < 5; i++) {
          stroke(input, time, InputButton.forward);
        }
        expect(matches.length, 1);
        input.setMode(InputMode.recording);
        for (var i = 0; i < 6; i++) {
          stroke(input, time, InputButton.forward);
        }
        expect(input.strokes.length, 5);
        expect(input.feedback, contains('Maximum five'));
        expect(matches.length, 1);
        input.undo();
        expect(input.strokes.length, 4);
        input.clearDraft();
        expect(input.strokes, isEmpty);
        input.dispose();
      });
    },
  );

  test(
    'recording gaps never split drafts; practice never dispatches playback',
    () {
      fakeAsync((time) {
        final matches = <ComboMatch>[];
        final practice = <ComboMatch>[];
        final input = ComboInput(
          catalog: catalog(),
          clock: FakeInputClock(time),
          mode: InputMode.recording,
          onRuntimeMatch: matches.add,
          onPracticeMatch: practice.add,
        );
        stroke(input, time, InputButton.forward);
        time.elapse(const Duration(seconds: 10));
        stroke(input, time, InputButton.backward, 600);
        expect(input.strokes, [f, bh]);
        expect(matches, isEmpty);
        input.setMode(InputMode.practice);
        expect(input.strokes, isEmpty);
        stroke(input, time, InputButton.forward);
        time.elapse(const Duration(milliseconds: 500));
        expect(practice.single.binding.profile, ProfileId.p1);
        expect(matches, isEmpty);
        input.dispose();
      });
    },
  );

  test(
    'focus, catalog, timing and mode changes discard pending matches and releases',
    () {
      for (final cancellation in ['focus', 'catalog', 'timing', 'mode']) {
        fakeAsync((time) {
          final matches = <ComboMatch>[];
          final input = ComboInput(
            catalog: catalog(),
            clock: FakeInputClock(time),
            onRuntimeMatch: matches.add,
          );
          stroke(input, time, InputButton.forward);
          input.down(InputButton.backward, 2);
          switch (cancellation) {
            case 'focus':
              input.cancel();
            case 'catalog':
              input.replaceCatalog(catalog());
            case 'timing':
              input.replaceCatalog(
                ProfileCatalog(
                  names: catalog().names,
                  bindings: catalog().bindings,
                  timing: RecognitionTiming(holdMs: 900),
                ),
              );
            case 'mode':
              input.setMode(InputMode.practice);
          }
          time.elapse(const Duration(seconds: 3));
          input.up(2);
          expect(matches, isEmpty, reason: cancellation);
          expect(input.strokes, isEmpty, reason: cancellation);
          input.dispose();
        });
      }
    },
  );
}
