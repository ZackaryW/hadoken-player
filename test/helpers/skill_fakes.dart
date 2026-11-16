import 'dart:async';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';

class MemorySkills implements SkillAssignmentStore {
  String? document;
  bool fail = false;
  @override
  Future<String?> read() async => document;
  @override
  Future<void> write(String document) async {
    if (fail) throw StateError('Disk unavailable');
    this.document = document;
  }
}

class MemoryProfiles implements ProfileDocumentStore {
  String? document;
  @override
  Future<String?> read() async => document;
  @override
  Future<void> write(String value) async => document = value;
}

class FakeSkillClock implements SkillClock {
  Duration elapsed = Duration.zero;
  @override
  Future<Duration> now() async => elapsed;
}

class SkillCommands implements PlaybackCommands {
  final calls = <PlayerAction>[];
  CommandResult result = const CommandResult(ActionStatus.success, 'Skipped.');
  Completer<void>? gate;
  @override
  Future<CommandResult> execute(PlayerAction action) async {
    calls.add(action);
    await gate?.future;
    return result;
  }
}
