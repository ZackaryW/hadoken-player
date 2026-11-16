// This entry point is also copied outside the Flutter project and run with Dart.
// ignore: avoid_relative_lib_imports
import '../../../lib/skills/registry.dart';

void check(bool condition) {
  if (!condition) throw StateError('Independent skill contract check failed.');
}

void main() {
  final definition = skillDefinitions.single;
  final runtime = definition.createRuntime();
  final context = SkillContext(
    sessionId: 's',
    owner: 'p1',
    actor: 'p1',
    players: ['p1', 'p2'],
    elapsed: Duration.zero,
  );
  const target = PlaybackSkillTarget(SkillAction.nextTrack);
  check(runtime.decide(target, context, 'first') == null);
  check(
    runtime
        .onEvent(SkillActionSucceeded('first', target), context)
        .stateChanged,
  );
  check(runtime.decide(target, context, 'second') != null);
  check(
    !runtime
        .onEvent(SkillActionSucceeded('first', target), context)
        .stateChanged,
  );
  check(
    PlayerSelector(PlayerScope.others).resolve('p1', context.players).single ==
        'p2',
  );
  final macro = SkillCombo([SkillStroke.forwardTap, SkillStroke.backwardHold]);
  final request = ArmComboListener(
    'effect',
    listenerKey: 'watch',
    combo: macro,
    players: PlayerSelector(PlayerScope.all),
    lifetime: const Duration(seconds: 5),
  );
  check(
    SkillReaction(requests: [request]).requests.single.capability ==
        SkillCapability.listener,
  );
}
