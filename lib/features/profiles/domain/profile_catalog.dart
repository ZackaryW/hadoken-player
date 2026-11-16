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

sealed class ExecutableBinding {
  final ProfileId profile;
  final List<Stroke> strokes;
  ExecutableBinding(this.profile, Iterable<Stroke> strokes)
    : strokes = List.unmodifiable(strokes) {
    if (this.strokes.isEmpty || this.strokes.length > 5) {
      throw const FormatException('A combination needs one to five strokes.');
    }
  }

  String get id;
  String get label;
  String get comboKey => strokes.map((s) => s.key).join('|');
}

final class ActionBinding extends ExecutableBinding {
  final PlayerAction action;
  ActionBinding(ProfileId profile, this.action, Iterable<Stroke> strokes)
    : super(profile, strokes);
  @override
  String get id => '${profile.name}.${action.name}';
  @override
  String get label => action.label;
}

final class SkillMacroBinding extends ExecutableBinding {
  final String skillKey;
  SkillMacroBinding(ProfileId profile, this.skillKey, Iterable<Stroke> strokes)
    : super(profile, strokes) {
    if (skillKey.trim().isEmpty) {
      throw const FormatException('A skill identity is required.');
    }
  }
  @override
  String get id => '${profile.name}.skill:$skillKey';
  @override
  String get label => 'Activate $skillKey';
}

final class BindingConflict implements Exception {
  final ExecutableBinding owner;
  const BindingConflict(this.owner);
  @override
  String toString() =>
      'Already assigned to ${owner.profile.label}: ${owner.label}.';
}

final class ProfileCatalog {
  final Map<ProfileId, String> names;
  final List<ActionBinding> bindings;
  final List<SkillMacroBinding> macros;
  Iterable<ExecutableBinding> get executableBindings sync* {
    yield* bindings;
    yield* macros;
  }

  final RecognitionTiming timing;
  final List<String> recoveryMessages;

  ProfileCatalog({
    required Map<ProfileId, String> names,
    required Iterable<ActionBinding> bindings,
    Iterable<SkillMacroBinding> macros = const [],
    required this.timing,
    Iterable<String> recoveryMessages = const [],
  }) : names = Map.unmodifiable(names),
       bindings = List.unmodifiable(bindings),
       macros = List.unmodifiable(macros),
       recoveryMessages = List.unmodifiable(recoveryMessages) {
    if (!names.containsKey(ProfileId.p1) ||
        names.length > 3 ||
        names.values.any((name) => name.trim().isEmpty)) {
      throw const FormatException(
        'Add one to three named profiles, starting with P1.',
      );
    }
    final combinations = <String, ExecutableBinding>{};
    final slots = <String>{};
    for (final binding in executableBindings) {
      if (!names.containsKey(binding.profile)) {
        throw const FormatException('Add this profile first.');
      }
      final owner = combinations[binding.comboKey];
      if (owner != null) throw BindingConflict(owner);
      if (!slots.add(binding.id)) {
        throw const FormatException('An action can have only one binding.');
      }
      combinations[binding.comboKey] = binding;
    }
  }

  factory ProfileCatalog.empty() => ProfileCatalog(
    names: const {ProfileId.p1: 'P1'},
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

  SkillMacroBinding? macroFor(ProfileId profile, String skillKey) {
    for (final macro in macros) {
      if (macro.profile == profile && macro.skillKey == skillKey) return macro;
    }
    return null;
  }

  ExecutableBinding? executableById(String id) {
    for (final binding in executableBindings) {
      if (binding.id == id) return binding;
    }
    return null;
  }

  List<ExecutableBinding> sharedPrefixes(ExecutableBinding binding) => [
    for (final other in executableBindings)
      if (other.id != binding.id &&
          (startsWithCombo(other.strokes, binding.strokes) ||
              startsWithCombo(binding.strokes, other.strokes)))
        other,
  ];
}
