enum SkillId {
  skipRecovery;

  String get key => 'skip-recovery';
  String get label => 'Skip Recovery';
  String get summary => 'Next track · 10s recovery';
  String get description =>
      'After you skip, wait 10 seconds before skipping again. Other players can still skip.';
}

const skipRecoveryDuration = Duration(seconds: 10);
