import 'skill.dart';
import 'skip_recovery/skip_recovery.dart';

export 'skill.dart';

/// Explicit registration of reviewed, code-defined skills. No dynamic loading.
const skillDefinitions = <SkillDefinition>[SkipRecovery()];

extension SkillMetadata on SkillId {
  SkillDefinition get definition =>
      skillDefinitions.singleWhere((skill) => skill.id == this);
  String get label => definition.label;
  String get summary => definition.summary;
  String get description => definition.description;
}
