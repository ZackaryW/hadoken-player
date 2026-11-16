# Tasks

## 1. Integrate the prerequisite and persistent skill catalog

- [x] 1.1 Confirm `add-profile-input-bindings` is implemented, verified and synchronized/archived; compare its actual dispatcher/outcome and stable-profile contracts with this design, and verify any reconciliation through existing action tests before introducing skill behavior.
- [x] 1.2 Add the static Skip Recovery definition, stable skill identity and separate versioned assignment repository; verify empty-default migration, assignment reload, unknown-ID handling and failed-write rollback without altering existing profile bindings.
- [x] 1.3 Document the catalog contract and fixed ten-second behavior, including process-session cooldown scope; verify the catalog metadata and tests agree with the user-facing description and expose no parameter or rule editor.

## 2. Implement deterministic skill effects

- [x] 2.1 Add an injectable elapsed-time source with Android elapsedRealtime support and fake-clock tests; verify that background/suspend time counts and wall-clock changes cannot alter eligibility.
- [x] 2.2 Implement owner-specific next-track recovery through the existing ability hook; verify eligible/denied behavior immediately before and exactly at ten seconds, unrelated actions, separate profiles and independent deadlines.
- [x] 2.3 Keep eligibility, playback, post-success updates and assignment changes serialized; verify rapid queued requests, duplicate request/success delivery, failures, no-ops and mid-cooldown assignment rejection through dispatcher integration tests.
- [x] 2.4 Verify profile renames, new bindings, navigation and background/resume preserve the same deadline while a new process clears only runtime state; document the supported state lifecycle in this OpenSpec change.

## 3. Profile assignment and action feedback

- [x] 3.1 Add a separate Player skills screen with an added-profile selector with the fixed catalog, assignment controls and readable descriptions; verify assignment persistence, unavailable IDs and active-cooldown edit rejection with widget tests.
- [x] 3.2 Display profile/skill/remaining-time denial feedback and accessible ready/cooling-down status; verify countdown refresh on foreground return and that expiration never replays a rejected command.
- [x] 3.3 Keep recording, practice, conventional controls, Android media controls and automatic next-track events outside player skill activation; verify they do not start or extend a profile cooldown and record this behavior in OpenSpec evidence.

## 4. Integrated acceptance

- [x] 4.1 Run the P2-success/P2-denied/P1-allowed/P2-allowed-at-ten-seconds scenario through real saved combos and the playback adapter; verify only successful attributed skips affect deadlines, including queue-boundary failure/no-op cases.
- [x] 4.2 Run formatting, analysis, the full relevant test suite and APK build, then repeat Android screen-off, app-switch, notification and interruption checks with skills assigned; record environment and results, leaving unavailable device checks incomplete.

## Workflow follow-up

- Verify this implementation against the player-skills specification, then synchronize the main specification and archive the completed change.
- Keep any authorized implementation checkpoints separate from the final archived-specification checkpoint; this task list does not authorize commits or publication.
