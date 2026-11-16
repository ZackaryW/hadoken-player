import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/registry.dart';

void main() {
  test(
    'all 102 levels obey strict ordering and ties block, including infinities',
    () {
      for (var action = -1; action <= 100; action++) {
        for (var block = -1; block <= 100; block++) {
          expect(
            Effort(action).overcomes(Effort(block)),
            action > block,
            reason: 'action=$action block=$block',
          );
        }
      }
      expect(Effort.minimum, Effort(-1));
      expect(Effort.maximum, Effort(100));
      expect(Effort.normal, Effort(50));
      expect(() => Effort(-2), throwsRangeError);
      expect(() => Effort(101), throwsRangeError);
    },
  );

  test('effort belongs to each action, activation and block declaration', () {
    expect(skillDefinitions.first.activationEffort, Effort.normal);
    final context = SkillContext(
      sessionId: 's',
      owner: 'p1',
      elapsed: Duration.zero,
    );
    expect(context.effort, Effort.normal);
    final block = RestrictActions(
      'block',
      players: PlayerSelector(PlayerScope.all),
      actions: [const PlaybackSkillTarget(SkillAction.nextTrack)],
      lifetime: const Duration(seconds: 10),
      effort: Effort(60),
    );
    final action = ExecutePlayerAction(
      'skip',
      player: 'p2',
      action: SkillAction.nextTrack,
      effort: Effort(80),
    );
    expect(action.capability, SkillCapability.playbackAction);
    expect(action.effort.overcomes(block.effort), isTrue);
    expect(
      ExecutePlayerAction(
        'normal',
        player: 'p1',
        action: SkillAction.stop,
      ).effort,
      Effort.normal,
    );
    expect(
      () => ExecutePlayerAction('bad', player: '', action: SkillAction.stop),
      throwsArgumentError,
    );
  });
}
