# Verification — 2026-11-16

Change: replace-mock-with-playback-skills. Supersedes the earlier read-only model assessment: the declared listener/state model and both production skills are now implemented.

## Outcome

All four implementation checkpoints are complete. No unresolved critical or warning findings remain in this change's tested scope. Definitions declare named listener metadata; runtimes select active listeners and own typed transient state under `lib/skills/`. Application policy supplies neutral events and capability execution, without production-skill behavior branches.

## Requirement coverage

| Requirements | Implementation and verification |
| --- | --- |
| Declared listeners, selective activation, ownership and state isolation | `lib/skills/listener.dart`, `skill.dart`, coordinator/policy lifecycle routing; `declared_listeners_test.dart` verifies named toggles, rejected unknown keys, global scope, fresh ownership/session state and typed-store isolation. Existing listening/coordinator tests cover dynamic listeners and bounded reactions. |
| Playback identity and actual listening | `ListeningClock`, `SkillPlaybackPort` and `listening_audio_adapter.dart`; `listening_audio_test.dart` covers pause, buffering, seek, speed, delayed samples, natural repeat, duplicate occurrences, completion, preserved queue occurrence and session reset. |
| Global commitment and assignment integrity | Independent Song Commitment runtime owns threshold 20s, four protected actions and block 90. `production_skills_test.dart` checks 19,999/20,000ms, P1–P3, effort ties, pause/stop availability, lock retention, assignment-edit denial, rename and play changes, and late equip. |
| Manual Force Skip and atomic evaluation | Independent Force Skip runtime declares activation/action effort 100 and a manual listener. Production and dispatcher tests cover macro routing, ordered execution, stronger/tied blocks, duplicate delivery, failure/no-op reporting and removal. |
| Fixed catalog, persistence and retirement | Production registry contains only Song Commitment and Force Skip. Retirement removes skip-recovery with feedback, preserves unrelated unknown keys and inputs, and equips neither replacement. Assignment and production tests exercise persistence and migration. Old runtime exists only as an injected test fixture. |
| Source boundaries and visible effort/status | Architecture tests enforce independent sources. Production widget tests cover tiles, generic assignment-lock feedback and details at 360×640 with text scales 1 and 2. Both action restrictions and manual activation display declared efforts. |

## Executed checks

- Final `flutter test --no-pub`: **902 passed**. The prior 901-test run also passed; final rerun includes the Android-discovered skip regression.
- Final `flutter analyze --no-pub`: **No issues found**.
- Focused playback regression suite: **26 passed**. New regression first reproduced `noOp` despite a completed skip, then passed after the fix.
- Normal Android debug APK built with `tool/build_android.ps1` and JDK 21; installed with `adb install -r` on `emulator-5554`, Medium Phone API 36.1. No app-data clearing.
- `test/experiments/production_skills_probe.dart` uses the real audio service and MixAudioAdapter, generated local audio and in-memory profiles/assignments. Foreground run passed at 22:54:17 UTC. Screen-off run passed at 22:54:52 UTC: P1/P2/P3 denied at 21,171ms listening; Force Skip (100) succeeded once; next play had 36ms listening; end-of-queue returned noOp. Pause and seek added no listening time. The probe did not edit saved setup.
- Restored the normal entrypoint APK afterward. Visually inspected the actual emulator: two square tiles, retired-assignment feedback, Song Commitment details with all four 90 labels, Force Skip activation/skip 100 labels and reachable macro screen. Existing P1/P2 and saved bindings retained; replacements remain unassigned. Left normal app on Player skills.

## Device defect resolved

The first Android probe physically advanced the song but returned noOp. Native seek re-emitted an old index; its queued callback briefly overwrote the completed transition before command attribution. The loop adapter now invalidates pending pre-completion index observations before publishing the completed manual transition. `loop_audio_adapter_test.dart` reproduces the old/target event ordering and verifies both command success and stable final index. The corrected device probes passed.

## Scope and evidence limits

Conventional unattributed app/media-session transport retains its established behavior; the global restriction applies to attributed player actions. Stop remains available by design. Exact threshold, buffering, repeats, seeking restrictions and large-text layouts were exercised in automated tests; emulator acceptance directly exercised real listening, pause/seek accounting, screen-off execution, all-player next-track denial, manual override, deduplication, end-of-queue and normal UI. This is emulator evidence, not a physical-device or exhaustive OEM battery-policy certification.

## Checkpoints

- `351354d`: declared listeners and typed session state.
- `e00e6c3`: actual-listening playback observations.
- `d638453`: production skills, retirement and UI.
- `a766ee9`: native skip ordering fix and Android acceptance probe.

Implementation commits exclude active planning. Main-spec synchronization and successful archive precede the separate artifact commit.
