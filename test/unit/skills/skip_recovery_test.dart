import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/registry.dart';
import '../../helpers/recovery_skill.dart';

SkillEvent event(
  String request,
  String player,
  int milliseconds, [
  SkillAction action = SkillAction.nextTrack,
]) => SkillEvent(
  requestId: request,
  playerId: player,
  action: action,
  elapsed: Duration(milliseconds: milliseconds),
);

void main() {
  test('registry has unique stable IDs and complete metadata', () {
    expect(skillDefinitions.map((s) => s.id).toSet(), SkillId.values.toSet());
    expect(skillDefinitions.length, SkillId.values.length);
    for (final skill in skillDefinitions) {
      expect(skill.label, isNotEmpty);
      expect(skill.description, isNotEmpty);
      expect(skill.summary, isNotEmpty);
      expect(skill.id.definition, same(skill));
    }
    expect(const SkipRecovery().id.key, 'skip-recovery');
  });

  test('isolated skill uses successful completion time and exact deadline', () {
    final runtime = const SkipRecovery().createRuntime();
    expect(runtime.denialFor(event('first', 'p2', 0)), isNull);
    // Eligibility alone cannot create an effect.
    expect(runtime.remaining('p2', const Duration(seconds: 20)), Duration.zero);
    expect(runtime.recordSuccess(event('first', 'p2', 20000)), isTrue);
    expect(
      runtime.denialFor(event('next', 'p2', 25000)),
      'Skip Recovery · 5s remaining',
    );
    expect(runtime.denialFor(event('other', 'p1', 25000)), isNull);
    for (final action in SkillAction.values.where(
      (a) => a != SkillAction.nextTrack,
    )) {
      expect(
        runtime.denialFor(event('other-action', 'p2', 25000, action)),
        isNull,
      );
      expect(
        runtime.recordSuccess(event('other-action', 'p2', 25000, action)),
        isFalse,
      );
    }
    expect(
      runtime.denialFor(event('edge', 'p2', 29999)),
      'Skip Recovery · 1s remaining',
    );
    expect(runtime.denialFor(event('edge', 'p2', 30000)), isNull);
  });

  test('duplicates, other players, elapsed jumps and fresh sessions', () {
    const definition = SkipRecovery();
    final runtime = definition.createRuntime();
    runtime.recordSuccess(event('first', 'p2', 0));
    expect(runtime.recordSuccess(event('first', 'p2', 3000)), isFalse);
    runtime.recordSuccess(event('other', 'p1', 3000));
    expect(
      runtime.remaining('p2', const Duration(seconds: 3)),
      const Duration(seconds: 7),
    );
    expect(
      runtime.remaining('p1', const Duration(seconds: 3)),
      const Duration(seconds: 10),
    );
    expect(runtime.remaining('p2', const Duration(seconds: 12)), Duration.zero);
    expect(
      definition.createRuntime().remaining('p1', Duration.zero),
      Duration.zero,
    );
  });
}
