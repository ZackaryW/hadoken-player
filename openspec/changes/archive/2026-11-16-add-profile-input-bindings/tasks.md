# Tasks

## 1. Import and verify the Troona baseline

- [x] 1.1 Import Troona revision `3f233344a28328fa380b2e8ac0c81ab061259ff6`, including vendored dependencies, without replacing this repository's Git identity, planning or unrelated files; verify the imported revision/file inventory and retain upstream attribution in the integrated project documentation.
- [x] 1.2 Set the Hadoken Android application identity/display name and disable upstream app-update installation prompts; verify the APK identity differs from Troona and the settings UI offers no Troona package as a Hadoken update.
- [x] 1.3 Resolve dependencies with a compatible Flutter/Dart toolchain, run upstream formatting, analysis and tests, and build an Android APK; record tool versions and command results, correcting concrete compatibility failures before later checkpoints.
- [x] 1.4 Run the baseline Android playback matrix using two local tracks: foreground playback, app switching, screen-off next-track advancement, media notification controls and interruption recovery; record device/API and outcomes, leaving unavailable device checks explicitly incomplete.

## 2. Persistent profiles and globally valid bindings

- [x] 2.1 Add stable P1-P3 models, three input-button IDs, tap/hold types, the six-action catalog and a versioned profile repository using the existing preferences dependency; verify save/reload, name stability and failed-write rollback with repository tests.
- [x] 2.2 Implement atomic whole-catalog validation for one-to-five-stroke bindings and global complete-combination uniqueness while allowing shared prefixes; verify cross-profile/same-profile duplicates, replacement, clearing, competing saves and malformed stored data with domain tests.
- [x] 2.3 Store shared recognition thresholds (initially 600 ms hold and 500 ms gap) separately from combo identity; verify positive-duration validation and record the persisted schema and ownership rule in this change's OpenSpec evidence.

## 3. Timed stroke recognition and prefix matching

- [x] 3.1 Implement the pure-Dart down/up classifier with an injected elapsed clock and scheduler, retaining bounded per-attempt down/up and gap observations; verify observation retention, threshold equality, single hold emission, repeated/stale events, pointer cancellation and overlapping presses with fake-time tests.
- [x] 3.2 Implement global longest-completed matching over the saved catalog; verify terminal matches, shorter-prefix timeout, longer match precedence, a hold spanning the gap window, exact deadline ordering, mismatch fallback, no-match reset and the five-stroke bound.
- [x] 3.3 Add distinct recording/practice/runtime modes and cancellation on timing/catalog/focus changes; verify drafts never auto-save or dispatch, practice has no playback effects and mode changes cannot leak pending strokes.
- [x] 3.4 Document recognition timing and prefix-delay behavior with the P1 Forward-tap/P2 Forward-tap-Backward-hold example; verify the documented examples match recognizer tests.

## 4. Attributed actions and playback integration

- [x] 4.1 Implement the serialized request dispatcher, session deduplication, explicit outcomes and allow-all ability hook; verify ownership, arrival ordering, duplicate delivery and pre-check/post-success ordering with fake playback and policy implementations.
- [x] 4.2 Implement the adapter around Troona's AudioServicePort for toggle, next/previous, bounded ten-second seek and stop; verify actual-success versus boundary no-op/failure, repeated track occurrences, concurrent automatic advancement and immediate gameplay pause without changing conventional controls.
- [x] 4.3 Register the feature in the existing composition root and publish outcome feedback; verify no second player is created, background service ownership survives navigation, and normal/system controls do not emit profile events. Document the Stage 2 hook and outcome contract.

## 5. Profile screen, Set recorder and combo pad

- [x] 5.1 Add the P1-P3 profile screen with names, per-action Set/clear controls and saved combination strips; verify persistence, duplicate-owner feedback and shared-prefix details with widget tests (presentation refined by section 9).
- [x] 5.2 Add the three-button Set recorder with live tap/hold indicators, five-stroke cap, undo/clear/cancel/save and fighting-game-style icon notation; verify mixed sequences, empty/sixth-stroke rejection and accessible text labels with widget tests.
- [x] 5.3 Add the runtime/practice pad and shared timing settings; verify profile attribution independent of the viewed profile, non-executing practice/recording, focus cancellation and visible outcome feedback. Record the three-button setup flow in OpenSpec evidence; the later focused-screen revision removes inline instructional help.

## 6. Integrated acceptance

- [x] 6.1 Exercise two complete profile setups through recording, restart, shared-prefix resolution and playback; verify each matched combo executes exactly once for its owner and conflicting complete combos cannot be saved.
- [x] 6.2 Run formatting, analysis, existing and new tests plus the APK build, then repeat the Android playback matrix after integration; record results and retain any unresolved device checks as incomplete rather than inferred passes.

## 7. Now Playing discovery and visual integration

- [x] 7.1 Add the accepted Player / Combo switch and profile shortcut on Now Playing; reuse the recognizer for circular inputs and compact notation, cancel pending input on mode/focus/navigation changes, and verify attribution plus small-screen layout with widget tests. Build and install the updated APK, compare both modes against the live emulator reference, and record this as one verified UI checkpoint.

## 8. Focused profiles and documentation policy

- [x] 8.1 Start new catalogs with P1, add profiles atomically up to three, persist added identities and migrate configured legacy profiles; verify limits, competing adds, rollback, disabled-profile rejection and reload.
- [x] 8.2 Separate profile bindings, timing and practice screens; remove prose beside controls, preserve concise conflict feedback, and verify navigation, adding profiles and scaled layouts. Relocate agent-written reports to OpenSpec, record the documentation restriction, build/install and inspect the simplified UI on the emulator.

## 9. Compact binding presentation and artifact reconciliation

- [x] 9.1 Group Set/Clear with each action, keep the saved combo directly below, and move prefix timing into an accessible info control beside the combo. Verify clear/edit/detail interactions and a five-stroke shared prefix at 360×640 with text scales through 2.0; build/install and inspect on the existing emulator. Reconcile stale proposal/design/task text and validate the updated OpenSpec artifacts.

## Workflow follow-up

- Formal verification completed; see evidence/formal-verification.md. Synchronize all four main specifications and archive before applying add-player-skills.
- Keep implementation checkpoints separate from the final archived-specification checkpoint.
