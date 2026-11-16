import 'package:troona/skills/skill.dart';
import '../entities/loop_queue.dart';

/// Optional capability implemented by the session's concrete audio adapter.
abstract interface class LoopQueuePort {
  LoopSnapshot? get currentLoop;
  LoopSnapshot? previewLoop(int ordinal, Duration elapsed);
  Future<LoopEditResult> editLoopQueue(
    EditLoopQueue request, {
    required String sessionId,
    required int expectedLoop,
    required String planId,
    required Duration elapsed,
  });
  Future<void> revokeLoopPlan(
    String sessionId,
    String planId,
    Duration elapsed,
  );
  Future<List<SongReference>> findSkillSongs(String query, {int limit = 50});
}
