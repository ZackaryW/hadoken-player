import 'skill.dart';
import 'song_commitment/song_commitment.dart';
import 'force_skip/force_skip.dart';

export 'skill.dart';

/// Explicit registration of reviewed, code-defined skills. No dynamic loading.
const skillDefinitions = <SkillDefinition>[SongCommitment(), ForceSkip()];

extension SkillMetadata on SkillId {
  SkillDefinition get definition =>
      skillDefinitions.singleWhere((skill) => skill.id == this);
  String get label =>
      skillDefinitions.where((skill) => skill.id == this).firstOrNull?.label ??
      key;
  String get summary => definition.summary;
  String get description => definition.description;
}
