enum ProfileId { p1, p2, p3 }

extension ProfileLabel on ProfileId {
  String get label => name.toUpperCase();
}

enum InputButton { forward, pause, backward }

enum StrokeKind { tap, hold }

enum PlayerAction {
  togglePlayback,
  nextTrack,
  previousTrack,
  seekForward,
  seekBackward,
  stop;

  String get label => switch (this) {
    togglePlayback => 'Play / pause',
    nextTrack => 'Next track',
    previousTrack => 'Previous track',
    seekForward => 'Forward 10 seconds',
    seekBackward => 'Back 10 seconds',
    stop => 'Stop',
  };
}

final class Stroke {
  final InputButton button;
  final StrokeKind kind;
  const Stroke(this.button, this.kind);

  String get key => '${button.name}:${kind.name}';
  String get label =>
      '${button.name} ${kind == StrokeKind.tap ? 'tap' : 'hold'}';

  Map<String, String> toJson() => {'button': button.name, 'kind': kind.name};

  factory Stroke.fromJson(Object? value) {
    final json = value as Map;
    return Stroke(
      InputButton.values.byName(json['button'] as String),
      StrokeKind.values.byName(json['kind'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Stroke && button == other.button && kind == other.kind;
  @override
  int get hashCode => Object.hash(button, kind);
}

bool startsWithCombo(List<Stroke> sequence, List<Stroke> prefix) {
  if (prefix.length > sequence.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (sequence[i] != prefix[i]) return false;
  }
  return true;
}

final class RecognitionTiming {
  final int holdMs;
  final int gapMs;
  RecognitionTiming({this.holdMs = 600, this.gapMs = 500}) {
    if (holdMs <= 0 || gapMs <= 0) {
      throw const FormatException(
        'Hold and continuation times must be positive.',
      );
    }
  }
}

final class ActionBinding {
  final ProfileId profile;
  final PlayerAction action;
  final List<Stroke> strokes;

  ActionBinding(this.profile, this.action, Iterable<Stroke> strokes)
    : strokes = List.unmodifiable(strokes) {
    if (this.strokes.isEmpty || this.strokes.length > 5) {
      throw const FormatException('A combination needs one to five strokes.');
    }
  }

  String get id => '${profile.name}.${action.name}';
  String get comboKey => strokes.map((s) => s.key).join('|');
}

final class BindingConflict implements Exception {
  final ActionBinding owner;
  const BindingConflict(this.owner);
  @override
  String toString() =>
      'Already assigned to ${owner.profile.label}: ${owner.action.label}.';
}

final class ProfileCatalog {
  final Map<ProfileId, String> names;
  final List<ActionBinding> bindings;
  final RecognitionTiming timing;
  final List<String> recoveryMessages;

  ProfileCatalog({
    required Map<ProfileId, String> names,
    required Iterable<ActionBinding> bindings,
    required this.timing,
    Iterable<String> recoveryMessages = const [],
  }) : names = Map.unmodifiable(names),
       bindings = List.unmodifiable(bindings),
       recoveryMessages = List.unmodifiable(recoveryMessages) {
    if (names.length != 3 ||
        ProfileId.values.any((id) => (names[id] ?? '').trim().isEmpty)) {
      throw const FormatException('P1, P2 and P3 each need a name.');
    }
    final combinations = <String, ActionBinding>{};
    final slots = <String>{};
    for (final binding in this.bindings) {
      final owner = combinations[binding.comboKey];
      if (owner != null) throw BindingConflict(owner);
      if (!slots.add(binding.id)) {
        throw const FormatException('An action can have only one binding.');
      }
      combinations[binding.comboKey] = binding;
    }
  }

  factory ProfileCatalog.empty() => ProfileCatalog(
    names: {for (final id in ProfileId.values) id: id.label},
    bindings: const [],
    timing: RecognitionTiming(),
  );

  ActionBinding? bindingFor(ProfileId profile, PlayerAction action) {
    for (final binding in bindings) {
      if (binding.profile == profile && binding.action == action) {
        return binding;
      }
    }
    return null;
  }

  List<ActionBinding> sharedPrefixes(ActionBinding binding) => [
    for (final other in bindings)
      if (other.id != binding.id &&
          (startsWithCombo(other.strokes, binding.strokes) ||
              startsWithCombo(binding.strokes, other.strokes)))
        other,
  ];
}
