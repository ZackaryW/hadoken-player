# Tasks

## 1. Independent contracts and effect coordination

- [x] 1.1 Extend `lib/skills/` with neutral event/context, trigger declaration, target, capability request/result and effect-handle types for all five capability families; verify pure-Dart contract tests and the architecture import test, including invalid parameters and one-to-five-stroke limits.
- [x] 1.2 Add ordered invocation dispatch, per-effect outcomes, deduplication and bounded reaction processing around `PlayerActionDispatcher`; verify deterministic execution, duplicate requests/callbacks, mixed success/failure and no recursive result-to-input delivery with fake capability adapters.
- [x] 1.3 Add the session effect ledger with elapsed deadlines, idempotent cleanup, source ownership, assignment locking and stop/replacement teardown; verify overlapping handles, background-time expiry, fresh-process state and cleanup failures without losing successful playback outcomes.
- [x] 1.4 Adapt Skip Recovery and registration to the extended contract without skill-specific policy branches; verify its existing ten-second success-only behavior, exclusive ownership, injected definitions and standalone Dart execution of the independent source folder.

## 1a. Effort contract refinement

- [x] 1.5 Add validated code-owned effort to actions, activation declarations, runtime blocks and restrictions, plus the typed attributed playback request; verify the entire -1 through 100 comparison range, ties blocking at both extrema, invalid values, default 50 and unchanged ordinary Skip Recovery behavior. This task extends the completed contract checkpoint; it does not claim the generated-action adapter is implemented.

## 2. Executable macros and persistent bindings

- [x] 2.1 Generalize executable binding targets to playback actions or stable skill activations and migrate profile storage atomically with a pre-migration backup; verify v1/v2 migration, rollback restoration, corrupt/unknown targets, unchanged timing/names and global uniqueness including dormant macros.
- [x] 2.2 Extend effective-catalog recognition and attributed requests to preserve timed observations and catalog revisions; verify shared-prefix longest matches, five-stroke limits, stale revision cancellation and owner attribution independent of the selected profile.
- [x] 2.3 Route manual activation only to the currently equipped, eligible owner and keep dormant bindings non-executable; verify reassignment before queued execution, re-equipping, no fabricated playback success and recording/practice isolation.
- [x] 2.4 Add a focused manual-macro editor linked from skill details using existing Set/Clear and combo notation; verify save/restart/conflict feedback, passive-only skills without an editor, concise skill tiles and small-screen/large-text widget layouts with an injected manual-capable definition.

## 3. Listening, restrictions and temporary combos

- [x] 3.1 Implement armed listeners with exact completed-combo matching, owner/others/all/explicit scopes and deterministic snapshots before primary eligibility; verify cross-player actor versus owner, multiple listeners, once/repeated mode, deadline/revocation races, unmatched input and no listener-induced prefix delay or practice events.
- [x] 3.2 Implement bounded action restrictions and effort reconciliation for playback/manual activation using profile selectors resolved at application; add the attributed skill-generated playback adapter in the same ordered flow. Verify owner/others/all targeting, maximum applicable blocker, ties/extrema, effort-80 manual skip versus a global effort-60 block, separate activation denial, bounded nonrecursive success hooks, expiry, source/time feedback and ordinary system-transport bypass.
- [x] 3.3 Implement atomic temporary playback-binding overlays with saved/manual reservation checks and one live override per profile/action; verify multi-target conflict rejection, queued/pending input invalidation, preserved attribution, base edits during an override and restoration on expiry/revocation/stop.
- [x] 3.4 Present effective combo notation and compact temporary status with source, saved combo and expiry on demand; verify widget updates at expiry, actionable denial feedback and no new timing controls or explanatory paragraphs on profile/skill surfaces.

## 4. Current and future playback loops

- [x] 4.1 Introduce session generations, loop ordinals, stable occurrence identities, per-loop revisions and a baseline/plan model behind the queue port; verify duplicate tracks, current-only edits, selected future loops, finite/open-ended ranges with bounded lifetimes and stale-session rejection.
- [x] 4.2 Implement ordered queue insertion/removal capability adapters and bounded song-reference lookup; verify accessible/unavailable media, revision conflicts, range removals by occurrence identity, truthful partial outcomes and removal of the playing/final occurrence while playing or paused.
- [x] 4.3 Integrate the current/next native queue window with forward transitions and manual navigation; verify repeat-off dormancy, repeat-one, forward/previous wrap, shuffle, empty-loop stop and native-transition/edit races without applying an edit twice or to another loop.
- [x] 4.4 Rebuild provisional unstarted loops when plans, baseline or deadlines change and invalidate plans on queue replacement; verify expiry/revocation after preloading, ordinary queue edits versus current-only skill edits and stable playback of the unaffected current loop.

## 5. Android audio feasibility and mixer integration

- [x] 5.1 Run the bounded Android feasibility experiment described in design.md using the installed backend, two local test tones/clips and noise; verify captured output contains both sources, measurable speed/pitch changes, coordinated pause/duck/stop, screen-off expiry and failed-source cleanup. Record commands, device/backend versions and measured evidence inside this change. If the backend fails, revise the adapter design before proceeding; an unsupported stub does not complete this checkpoint.
- [x] 5.2 Add the real audio-effects port, support query and bounded one-active-mix adapter after the feasibility check passes; verify noise and two-song source preparation, offset/gain/speed/pitch validation, competing-mix conflict, unavailable-source cleanup and correct per-effect results in adapter tests.
- [x] 5.3 Integrate layer gain and playback intent with the existing audio session and service-side expiry; verify all-layer pause/resume/volume/duck/headphone/interrupt/stop behavior, volume changes during a mix, expiry while paused and source-change/replacement teardown without unintended restart.
- [x] 5.4 Verify the integrated mixer on Android with captured audio and service inspection: audible noise/blend, requested transformations, one media notification, screen-off continuation/expiry, system pause, interruption and repeated cleanup with no leaked secondary playback. Keep acceptance evidence in this change.

## 6. End-to-end capability and regression acceptance

- [x] 6.1 Add developer/test-only registered definitions that exercise all five effect capability families and attributed generated playback through real application adapters and manual/listening activation; verify registration requires no policy/UI behavior branches, effort conflicts, per-effect failure reporting, source ownership, assignment locking and no invented abilities in the default production catalog.

- [x] 6.2 Run cross-feature scenarios combining a listener, an action restriction, a temporary override and a future-loop edit; verify deterministic ordering at expiry/loop boundaries, a cancelled stale input, persisted base configuration and clean stop/restart without transient effects.
- [x] 6.3 Run `flutter test`, `flutter analyze` and the established Android debug build, then inspect the actual emulator's Now Playing, profile, skill-grid and macro-editor flows with preserved user data; record outcomes in this change, including ordinary playback/background controls, exclusive ownership, concise layouts and absence of overflow.

## Checkpoint evidence

- Independent contracts/coordinator/lifecycle committed as `017398a`. Verification: 74 focused tests passed; `flutter analyze --no-pub` reported no issues; a copied `lib/skills/` plus standalone smoke entry point ran with `dart run` outside the Flutter project. Effort reconciliation was requested afterward and is tracked separately in 1.5 and 3.2.
- Effort contracts/policy committed as `f9d1922`: 43 focused tests passed, including all 10,404 level comparisons; analysis clean. Macro storage/migration committed as `f1c7a02`: 49 profile/input/widget tests passed; analysis clean. Manual macro recognition, activation and focused editor committed as `21e3ec9`: 112 combined profile/input/skill tests passed, including 360×640 at text scales 1 and 2; analysis clean. Widget fixture setup/teardown explicitly drains real and fake-time queues.

- Listening/restriction/generated-playback checkpoint committed as `b38d759`: 92 focused domain/widget tests passed; analysis clean. Covers deterministic snapshots, all selector scopes, exact expiry/revocation, effort-80 versus block-60, ties/extrema, independent activation blocking, backend non-success, deduplication, nonrecursive generated success and shared reaction budgets. Custom skill identities register without adding policy branches.

- Temporary combo checkpoint committed as `59d4e96`: 121 focused tests passed; analysis clean. Verified atomic reservation conflicts (including an in-flight base save), stale/pending input cancellation, target attribution, edited-base restoration and revoke/session teardown. Profile details and timed expiry passed at 360×640 with text scales 1.3 and 2.0; corrected a bottom-sheet overflow found by the test.

- Loop model checkpoint committed as `9b32f8c`: 7 focused tests passed; analysis clean. Added the optional queue capability port, stable duplicate occurrences, copy-before-native-commit state, current/future/range edits, provisional materialization and exact-deadline revocation. Native queue execution remains in 4.2–4.4.

- Queue integration checkpoint committed as `0df76b9`: full suite passed 872 tests before the final timer/decoder-preservation additions; the final 13 native-loop/real-capability tests passed and analysis is clean. Android debug build succeeded with the established JDK helper. Covers native boundary during source lookup, stopped final occurrence, live decoder preservation, dormant repeat modes, duplicate IDs, future-range rebuilds, owned expiry cleanup and stale/partial outcomes. Android source readability is checked through an asset descriptor before scheduling distant insertions. Actual emulator interaction remains in 6.3.

- Android feasibility: device-only probe and emulator-output capture verified actual simultaneous tones, noise, 1.5× pitch/speed, coordinated pause/duck/stop, timed expiry while Android reported Dozing and failed-source cleanup. See audio-feasibility.md for measured results, backend/device versions and reproducible commands. Production mixing and task 5.4 were still pending at that checkpoint.

- Final checkpoints: production mixer/session integration committed as `2dabbb0`; Android integrated capture, manual UI fixture and all-capability integration committed as `a8245c0`. All 24 tasks are now complete. Full suite: 888 passing tests; analysis clean; normal Android debug build and actual emulator checks passed. See acceptance.md and verification.md. All five delta specs were synchronized and validated before CLI archive; archive used `--skip-specs` only because that merge was already complete. The post-archive pspec state-clear command completed with unchanged: no temporal values needed removal.

## Workflow follow-up

- Complete and verify each coherent checkpoint before starting dependent work. For authorized incremental commits, review only its explicit code/test paths, validate the message with zmem and run `pspec check commit` immediately before committing. Active planning remains local and absent from every proposed commit tree.
- Keep decisions and acceptance evidence in OpenSpec/zmem; do not add documentation elsewhere.
- After all implementation and acceptance tasks pass, verify the change, synchronize its five delta specs and successfully archive it. Then run `pspec state clear --change expand-skill-capabilities` and report cleanup separately if it fails.
- Only after successful synchronization and archive, review and commit main-spec updates and archived artifacts as the final artifact checkpoint using the same zmem and commit-preflight workflow. Do not archive unfinished work to permit an implementation commit.
