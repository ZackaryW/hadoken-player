import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/player_skills/data/android_skill_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reads Android elapsed time each time, including resume jumps',
    () async {
      var elapsed = 1000;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidSkillClock.channel, (call) async {
            expect(call.method, 'elapsedRealtime');
            return elapsed;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AndroidSkillClock.channel, null),
      );
      const clock = AndroidSkillClock();
      expect(await clock.now(), const Duration(seconds: 1));
      elapsed += 12000;
      expect(await clock.now(), const Duration(seconds: 13));
    },
  );
  test('unavailable clock fails rather than substituting wall time', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AndroidSkillClock.channel,
          (_) async => throw PlatformException(code: 'unavailable'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidSkillClock.channel, null),
    );
    await expectLater(
      const AndroidSkillClock().now(),
      throwsA(isA<PlatformException>()),
    );
  });
}
