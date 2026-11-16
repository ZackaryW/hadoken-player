import 'dart:async';
import '../../profiles/domain/profile_catalog.dart';

typedef CancelInputTimer = void Function();

abstract interface class InputClock {
  Duration get elapsed;
  CancelInputTimer schedule(Duration delay, void Function() callback);
}

final class StopwatchInputClock implements InputClock {
  final Stopwatch _watch = Stopwatch()..start();
  @override
  Duration get elapsed => _watch.elapsed;
  @override
  CancelInputTimer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback).cancel;
}

enum InputMode { recording, practice, runtime }

final class ComboMatch {
  final ActionBinding binding;
  final Duration recognizedAt;
  const ComboMatch(this.binding, this.recognizedAt);
}

/// One source of timing semantics for the recorder, practice and runtime pad.
/// Pure Dart; callers cancel on route/focus loss and replace catalogs on commit.
final class ComboInput {
  final InputClock clock;
  final void Function(ComboMatch match) onRuntimeMatch;
  final void Function(ComboMatch match)? onPracticeMatch;
  final void Function()? onChanged;
  ProfileCatalog _catalog;
  InputMode _mode;
  final _contacts = <int>{};
  final _attempt = <Stroke>[];
  final _draft = <Stroke>[];
  ActionBinding? _pending;
  InputButton? _button;
  int? _pointer;
  Duration? _downAt;
  Duration? _gapDeadline;
  CancelInputTimer? _cancelGap;
  CancelInputTimer? _cancelHold;
  bool _overlap = false;
  bool _holding = false;
  String? feedback;
  ComboMatch? lastMatch;
  bool _disposed = false;
  int _semanticPointer = -1;
  final _semanticReleases = <int, CancelInputTimer>{};

  ComboInput({
    required ProfileCatalog catalog,
    required this.clock,
    required this.onRuntimeMatch,
    this.onPracticeMatch,
    this.onChanged,
    InputMode mode = InputMode.runtime,
  }) : _catalog = catalog,
       _mode = mode;

  InputMode get mode => _mode;
  InputButton? get pressedButton => _button;
  bool get holding => _holding;
  List<Stroke> get strokes =>
      List.unmodifiable(_mode == InputMode.recording ? _draft : _attempt);
  bool get waitingForContinuation => _gapDeadline != null;

  void setMode(InputMode mode) {
    cancel();
    _draft.clear();
    _mode = mode;
    lastMatch = null;
    feedback = null;
    _notify();
  }

  void replaceCatalog(ProfileCatalog catalog) {
    cancel();
    _catalog = catalog;
    // A draft recorded under old thresholds must be recorded again.
    _draft.clear();
    feedback = null;
    lastMatch = null;
    _notify();
  }

  void down(InputButton button, int pointer) {
    if (_disposed || _contacts.contains(pointer)) return;
    if (_contacts.isNotEmpty) {
      _contacts.add(pointer);
      _overlap = true;
      _discardAttempt();
      _releasePress();
      feedback = 'Use one button at a time.';
      _notify();
      return;
    }
    // Deadline equality expires the previous attempt before this new press.
    final deadline = _gapDeadline;
    if (deadline != null && clock.elapsed >= deadline) _finish(_pending);
    _stopGap(); // A timely down protects a hold, even beyond the gap deadline.
    _contacts.add(pointer);
    _button = button;
    _pointer = pointer;
    _downAt = clock.elapsed;
    _holding = false;
    feedback = null;
    final downAt = _downAt;
    _cancelHold = clock.schedule(
      Duration(milliseconds: _catalog.timing.holdMs),
      () {
        if (_disposed || _downAt != downAt || _pointer != pointer) return;
        _holding = true;
        _notify();
      },
    );
    _notify();
  }

  /// Screen-reader activation uses the same classifier and shared threshold.
  void semanticPress(InputButton button, {bool hold = false}) {
    if (_disposed) return;
    final pointer = _semanticPointer--;
    down(button, pointer);
    if (!hold) {
      up(pointer);
      return;
    }
    _semanticReleases[pointer] = clock.schedule(
      Duration(milliseconds: _catalog.timing.holdMs),
      () {
        _semanticReleases.remove(pointer);
        up(pointer);
      },
    );
  }

  void up(int pointer) {
    if (_disposed || !_contacts.remove(pointer)) return;
    if (_overlap) {
      if (_contacts.isEmpty) _overlap = false;
      return;
    }
    if (_pointer != pointer || _button == null || _downAt == null) return;
    final elapsed = clock.elapsed - _downAt!;
    final stroke = Stroke(
      _button!,
      elapsed.inMicroseconds >= _catalog.timing.holdMs * 1000
          ? StrokeKind.hold
          : StrokeKind.tap,
    );
    _releasePress();
    if (_mode == InputMode.recording) {
      if (_draft.length == 5) {
        feedback = 'Maximum five strokes. Undo or clear to change the draft.';
      } else {
        _draft.add(stroke);
      }
    } else {
      _recognize(stroke);
    }
    _notify();
  }

  void _recognize(Stroke stroke) {
    _attempt.add(stroke);
    final candidates = _catalog.bindings
        .where((b) => startsWithCombo(b.strokes, _attempt))
        .toList();
    for (final binding in candidates) {
      if (binding.strokes.length == _attempt.length) _pending = binding;
    }
    final hasLonger = candidates.any((b) => b.strokes.length > _attempt.length);
    if (!hasLonger || _attempt.length == 5) {
      _finish(_pending);
      return;
    }
    final gap = Duration(milliseconds: _catalog.timing.gapMs);
    final deadline = _gapDeadline = clock.elapsed + gap;
    _cancelGap = clock.schedule(gap, () {
      if (_disposed || _gapDeadline != deadline) return;
      _finish(_pending);
      _notify();
    });
  }

  void _finish(ActionBinding? binding) {
    _discardAttempt(); // No mismatching or consumed stroke is replayed.
    if (binding == null) {
      feedback = 'No matching combination.';
      return;
    }
    final match = lastMatch = ComboMatch(binding, clock.elapsed);
    feedback = '${binding.profile.label}: ${binding.action.label}';
    if (_mode == InputMode.runtime) onRuntimeMatch(match);
    if (_mode == InputMode.practice) onPracticeMatch?.call(match);
  }

  void undo() {
    cancel();
    if (_draft.isNotEmpty) _draft.removeLast();
    feedback = null;
    _notify();
  }

  void clearDraft() {
    cancel();
    _draft.clear();
    feedback = null;
    _notify();
  }

  /// Does not save or execute a pending match. Completed recording strokes
  /// survive focus loss; mode/catalog changes explicitly clear them.
  void cancel() {
    for (final cancel in _semanticReleases.values) {
      cancel();
    }
    _semanticReleases.clear();
    _contacts.clear();
    _overlap = false;
    _releasePress();
    _discardAttempt();
    _notify();
  }

  void _discardAttempt() {
    _stopGap();
    _attempt.clear();
    _pending = null;
  }

  void _stopGap() {
    _cancelGap?.call();
    _cancelGap = null;
    _gapDeadline = null;
  }

  void _releasePress() {
    _cancelHold?.call();
    _cancelHold = null;
    _button = null;
    _pointer = null;
    _downAt = null;
    _holding = false;
  }

  void _notify() {
    if (!_disposed) onChanged?.call();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
