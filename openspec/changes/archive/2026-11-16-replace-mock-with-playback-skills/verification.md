# Verification — 2026-11-16

Latest assessment: the 2026-11-17 follow-up below supersedes the initial clean verdict.

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

## Follow-up verification and Ponytail audit — 2026-11-17

This assessment supersedes the earlier clean verdict above. Reviewed working tree based on `8e78f45`. This was a read-only application audit: no production code or tracked tests were changed. Temporary reproductions live in ignored `.dart_tool/ponytail_audit_test.dart`.

### Archive and synchronization

`openspec list --json` reports the existing project root and zero active changes. The change is already archived at this directory. Active-change `status` and `instructions apply` reject its former name, so their task aggregation cannot be rerun without reopening the change; it was not reopened or archived a second time. The archived schema is spec-driven and its checklist has four checked tasks.

Compared all 15 delta operations against main specs: 4 additions, 9 modifications and 2 removals. The only difference is the explicit later user correction to Persistent profile assignments: retirement is silent, as implemented and committed in `8e78f45`. The current main spec is authoritative for that correction. Replaying the older delta would incorrectly restore the rejected notice. All five main specs pass strict validation. No main-spec edit was needed.

The two removed behaviors were checked against their usable baseline in `2c04f1a^:openspec/specs/player-skills/spec.md`, after querying computed zmem memory. Production registration contains only Song Commitment and Force Skip. Recovery implementation remains solely an explicitly injected test fixture; production keeps only its migration identity. Both removals are confirmed.

### OpenSpec scorecard

| Dimension | Result |
| --- | --- |
| Completeness | Archived checklist 4/4 checked; implementation located for 13/13 ADDED/MODIFIED requirements; both removals confirmed. Fresh CLI Task Completion aggregation not verified because the CLI accepts active changes only. |
| Correctness | All 13 requirements mapped to implementation/tests; two reproduced behavior gaps remain (findings 1 and 2 below). Existing scenarios have source/test evidence, but the two new edge-case probes fail. Silent retirement follows the user's superseding correction. |
| Coherence | Independent Dart skill modules, typed state, listener activation, native listening observations and concise tiles follow the design. Optional combo-filter routing diverges from the declaration contract. CI formatting also fails (finding 5). |

Mapping reviewed: catalog and persistence (`registry.dart`, `skill_assignments.dart`, assignment/production tests); atomic evaluation (`action_dispatcher.dart`, dispatcher tests); stable assignment locks (`skill_controls.dart`, production tests); timing and playback identity (`listening_clock.dart`, `listening_audio_adapter.dart`, listening tests); feedback and effort (`player_skills_page.dart`, production widget tests at scales 1/2); independent modules (architecture tests); events and declared listeners (`skill.dart`, `listener.dart`, coordinator/policy, declared-listener and manual tests); global commitment and manual force (`song_commitment.dart`, `force_skip.dart`, production tests and prior Android probe evidence).

OpenSpec assessment: no missing whole requirement implementation found. Three warnings affect correctness/coherence: optional listener routing, edited-loop skip attribution and the CI formatting gate. Fresh active-task CLI aggregation is not verified for this already-archived change. This is not a clean readiness verdict; the historic archive is preserved and the defects need follow-up fixes.

### Ponytail audit

Method: upstream `https://github.com/DietrichGebert/ponytail/blob/main/skills/ponytail-audit/SKILL.md`, retrieved read-only. No plugin or hooks installed. Expected load is one Android device, at most three profiles, a local music library and a background playback process that may stay alive across many sessions. No new abstractions or removal of explicitly requested skill capabilities is proposed.

Map: `main.dart` boots DI, database and audio service. Device audio is scanned into Isar; playlists/history and backup restore use that database. Profile combos/macros and assignments use SharedPreferencesAsync. Pointer input passes through ComboInput, effective bindings and ordered dispatch, then skill policy/coordinator and native playback/loop/mixer adapters. System controls and interruption handling enter the audio port directly by design. Optional metadata uses network APIs behind opt-in settings. Backup import validates JSON before a database transaction. Android manifest/build configuration and CI were inspected.

#### Must fix

1. **Declared unfiltered combo listeners never fire** — `lib/features/player_skills/domain/skill_policy.dart:337`, `lib/skills/listener.dart:34`.
   - What: listener metadata permits an omitted combo filter, meaning any matching event in the selected player scope.
   - Problem: policy first requires `listener.combo == observedCombo`; a null filter never passes. A registered all-player listener received zero callbacks for P2's valid attributed input; expected one.
   - Fix: route comboObserved declarations when their filter is absent or matches, then let runtime matching enforce activation and scope. Add the focused regression to the tracked suite.
   - If skipped: future skills declared to watch any player's inputs silently do nothing. Current Song Commitment/Force Skip do not use this trigger.

2. **A successful skip across an edited loop reports noOp** — `lib/features/player_actions/data/playback_commands_adapter.dart:91`.
   - What: the command adapter determines skip success by comparing queue order before and after.
   - Problem: with current `[a,b]`, repeat-all, and next loop `[a,b,c]`, skip from b really enters loop 1 at a, but `sameOrder` fails and returns noOp. The regression confirmed both changed loop identity and the false result. Force Skip uses this adapter.
   - Fix: use the loop/occurrence transition to confirm expected wrap success when this port supports loop queues; retain guards against unrelated concurrent queue replacement and automatic advance.
   - If skipped: UI and success listeners disagree with real playback when queue-edit skills and skip skills interact.

3. **An interruption can start music that was paused** — `lib/services/audio/audio_session_service.dart:105`.
   - What: interruption-end resumes playback whenever the setting is enabled and its hint allows it.
   - Problem: no state records whether the interruption actually paused playing audio. With a loaded paused queue, a pause interruption begin/end leaves native playback running. A focused test reproduced false becoming true.
   - Fix: track whether this interruption paused active playback, and resume only that case; cancel resume intent on explicit user stop/pause or route loss. Cover paused-before-interruption and user cancellation.
   - If skipped: ending a call or other interruption can start unwanted audio.

#### Should fix

4. **Action bookkeeping has no retention bound** — `lib/features/player_actions/domain/action_dispatcher.dart:90`, `lib/features/player_skills/domain/skill_policy.dart:52`, `lib/features/player_skills/domain/skill_coordinator.dart:50`.
   - What: maps retain request futures/outcomes, budgets, request sessions, invocations and capability results.
   - Problem: every new UUID adds entries, including denied/no-op input. No eviction exists; session reset only resets runtimes/effects. The app-lifetime dispatcher retains bindings and stroke observations for every completed request.
   - Fix: discard execution-only budgets/session entries after completion and scope duplicate-result retention to an explicit bounded window/session while keeping in-flight requests protected. Test both duplicate rejection and bounded retained state.
   - If skipped: memory grows with cumulative play, even though there are only three players. This finding is source-confirmed; no heap-size or time-to-exhaustion claim is made.

5. **The configured CI formatting step fails** — `.github/workflows/ci.yml:18`, `test/unit/player_skills/all_capabilities_test.dart`.
   - What: CI rejects files that differ from Dart formatter output.
   - Problem: the exact check identified this test file; a targeted rerun exited 1. Tests and analysis passing do not make CI green.
   - Fix: format this one file and rerun the formatting gate.
   - If skipped: CI stops before analysis/tests. This is a failing configured check, not a style preference.

The suspected upstream update-feed issue was rejected: `lib/core/di/injection.dart:487` explicitly constructs UpdateCubit with `enabled: false`, preventing both automatic and manual checks. No finding is reported for it. No justified line/dependency deletion estimate was established.

### Fresh evidence and limits

- Existing `flutter test --no-pub`: 902 passed.
- `flutter analyze --no-pub`: no issues found.
- `dart format --output=none --set-exit-if-changed lib test`: one file differs; targeted check confirmed exit 1.
- Three temporary behavioral probes: all fail on their expected-correct assertions, reproducing findings 1–3. These are additional audit probes, not part of the passing 902-test suite.
- `openspec validate --specs --strict`: five passed.
- No application fixes were made. The normal emulator installation was not rebuilt or retested during this audit; prior foreground/screen-off evidence remains dated 2026-11-16.
- Reviewed high-impact flows rather than all 466 Dart files individually. Not checked exhaustively: generated/localization code, every UI route, native third-party plugin internals, physical-device/OEM interruptions and battery policies, iOS, release signing, dependency CVEs, live remote services, or long-duration heap profiling. No CodeGraph index or usable Ripwire interface exists here, so source/search/tests were used.

Verdict: fix the three reproduced bugs and formatting gate before treating this revision as release-ready; bound action bookkeeping for long-running sessions. The existing archive and latest main-spec correction remain intact.
