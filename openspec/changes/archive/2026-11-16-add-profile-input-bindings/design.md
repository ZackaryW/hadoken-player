# Design

## Context

See proposal.md for motivation and the four capability specifications for behavior. Troona is now imported and the Stage 1 implementation is present. The user selected [Troona](https://github.com/donfreddy/troona-music) after comparing mature playback components and complete apps. The reviewed import revision is `3f233344a28328fa380b2e8ac0c81ab061259ff6`; Initial planning inspected source remotely; subsequent local builds, tests and emulator observations are recorded in evidence/hadoken-verification.md.

Observed upstream extension points at that revision:

- `lib/features/player/domain/ports/audio_service_port.dart`: typed playback commands returning `Either<Failure, Unit>`, current state and streams.
- `lib/features/player/data/adapters/just_audio_adapter.dart`: playback implementation; `audio_handler_impl.dart` bridges the same port to Android media controls.
- `lib/services/audio/audio_service_initializer.dart` and `audio_session_service.dart`: service initialization and interruptions. The Android manifest declares the playback foreground service, receiver and permissions.
- `lib/core/di/injection.dart`: GetIt registrations; existing settings and session stores use SharedPreferences. Player presentation uses Bloc.
- Relevant existing tests cover the handler, adapter, queue, session restore and progress. `.github/workflows/ci.yml` runs formatting, analysis and tests with Flutter 3.47.5; `pubspec.yaml` requires Dart ^3.10.8. This is evidence of intended checks, not a claim they have passed here.
- Audio packages are `just_audio ^0.10.4`, `audio_service ^0.18.18` and `audio_session ^0.2.2`. A vendored media-query dependency must accompany the import.

Source references: [port](https://github.com/donfreddy/troona-music/blob/3f233344a28328fa380b2e8ac0c81ab061259ff6/lib/features/player/domain/ports/audio_service_port.dart), [manifest](https://github.com/donfreddy/troona-music/blob/3f233344a28328fa380b2e8ac0c81ab061259ff6/android/app/src/main/AndroidManifest.xml), [tests](https://github.com/donfreddy/troona-music/tree/3f233344a28328fa380b2e8ac0c81ab061259ff6/test/unit/player), [license](https://github.com/donfreddy/troona-music/blob/3f233344a28328fa380b2e8ac0c81ab061259ff6/LICENSE).

## Goals / Non-Goals

**Goals:** Retain Troona's local library and background playback while introducing pure-Dart, testable input recognition and attributed actions behind its existing interface. Use on-screen input only: three buttons, each with tap/hold classification. A globally unique complete binding determines the player.

**Non-Goals:** Replacing the audio engine, global keyboard capture, Bluetooth/gamepad support, network multiplayer, simultaneous button chords, rhythm scoring, scripted rules or Stage 2 skills. Existing system and normal transport controls remain unattributed; this is a gameplay interaction feature, not an anti-cheat system.

## Decisions

### 1. Import a pinned complete application, then prove the baseline

Import the reviewed revision into this repository during implementation, using a temporary upstream checkout as the source. Preserve this repository's `.git`, OpenSpec artifacts and unrelated user files. Integrate README/ignore rules deliberately, retain upstream license/attribution, and include the vendored dependency. Use a distinct Android application identity and Hadoken display name so this app cannot overwrite an installed Troona. Preserve upstream Dart package paths initially to avoid a broad rename. Disable upstream app-update installation prompts or point them only to a Hadoken-owned destination; never offer Troona packages as Hadoken updates.

Run the existing format/analyze/test checks and build an Android APK before adding controls. Validate foreground, screen-off and app-switch playback, automatic next track, notification controls and interruption recovery on a recorded Android environment. A missing device is a reported incomplete acceptance gate, not a passing test.

Troona was chosen for its existing local-player UI and small playback contract. The official audio_service example would require building more library UI; the original Flutter-Music-Player lacks a service foundation. Troona's small-project maturity remains a tradeoff accepted in foundation selection.

### 2. Keep gameplay input outside the audio implementation

Use feature modules under `lib/features/profiles`, `lib/features/input_bindings` and `lib/features/player_actions`, following existing domain/data/presentation boundaries. Register shared repositories, recognizer and dispatcher in the existing composition root. New widgets/Cubits manage editing; neither the recorder nor recognizer depends on Flutter audio plugins.

The runtime flow is:

```text
Three-button pad --> timestamped down/up events --> stroke recognizer
    --> global binding matcher --> attributed action dispatcher
    --> Hadoken playback adapter --> existing AudioServicePort
```

The binding editor uses the same stroke classifier but bypasses matching/dispatch while recording. Practice uses matching with a non-executing sink. System media controls retain the upstream bridge and do not fabricate a player ID.

### 3. Persist profiles and bindings as a small versioned document

Use a project-owned SharedPreferences document, independent of upstream playback-session keys. Use fixed identity capacity P1-P3, but persist only added profiles, beginning with P1. Store display names, action-to-combination mappings, document version and global timing settings. Version 2 stores the active profile list; version 1 migration retains configured names/bindings but omits unused default P2/P3 entries. Each action has zero or one saved binding per profile. One whole-document write follows validation against the current snapshot; failed persistence leaves the prior in-memory catalog active.

A combination's canonical key is the ordered list of `(buttonId, tapOrHold)` pairs. Timing observations do not enter this key. Enforce uniqueness across every profile/action pair, including within a profile. Shared prefixes are legal. Load-time validation deactivates malformed entries and all members of an ambiguous duplicate group, preserves valid entries, and exposes repair feedback. Rename/display settings never change profile IDs.

This small bounded configuration does not justify adding a second database or a generic rules schema. Future skills will store stable IDs separately and will not be embedded in binding definitions.

### 4. Recognize strokes using monotonic elapsed time

Use an injectable clock and scheduler. Defaults are a 600 ms hold threshold and 500 ms maximum gap; expose app-wide timing settings with positive finite durations. Global timing prevents the same physical gesture being classified differently for two profiles. Preserve down/up timestamps and measured durations in ephemeral events so a future timing-sensitive extension can be added without changing input capture; rhythm-specific bindings are not introduced now.

Classify on release: duration below threshold is tap; equality or above is hold. A live marker indicates that the hold threshold was crossed, but crossing it does not itself emit a command. Repeated down events, stale release events and overlapping presses cannot create extra strokes. Focus loss, pointer cancellation, mode/catalog changes cancel the attempt. A held pointer waits for release or cancellation; it does not repeatedly execute actions.

### 5. Match globally with bounded longest-prefix resolution

At most 18 action bindings exist (three profiles times six actions), each at most five strokes. A straightforward candidate filter over this small catalog is preferable to a generalized parser. Track the current attempt, surviving candidates and longest complete candidate. Fire an unambiguous terminal match immediately. If that match is also a prefix, defer until the gap deadline or a longer completed match.

The gap runs from the last release to the next down. Process expiration before a down at exactly the deadline. A timely next down suspends gap expiry while the user holds; re-evaluate when the stroke finishes. On mismatch/timeout, emit the pending complete candidate if any and discard the rest of the attempt. Do not replay consumed or mismatching strokes into a second command. At five strokes there can be no longer candidate. Input cancellation discards even a pending complete candidate.

This introduces a deliberate delay for shorter bindings that prefix longer ones. The editor shows that consequence; disallowing prefixes was rejected by the user.

### 6. Use explicit command outcomes and one future skill hook

Proposed domain types are `PlayerActionRequest` (request ID, profile ID, binding ID, action, monotonic recognition time) and `PlayerActionOutcome` (success/denied/no-op/failure, message and optional metadata). The dispatcher snapshots ownership from the committed catalog, serializes requests, checks a narrow `PlayerAbilityPolicy`, invokes a `PlaybackCommands` adapter and publishes a post-success notification before the next request is evaluated. Stage 1 installs an allow-all implementation. The request deduplication record lives for the service session; rejected/no-op outcomes are also remembered.

The adapter wraps the existing AudioServicePort. Resolve toggle against current state, clamp +/-10-second seeks, and detect queue-boundary no-ops before invoking skip. Compare the requested operation's before/after queue occurrence, not only track title, to avoid crediting a no-op or unrelated automatic advance as a successful skip. A playback call's return alone is not proof of effect. Request processing must not await a future that represents an entire track's playback duration.

For gameplay pause, explicitly pass a zero fade through the port rather than inheriting Troona's 300 ms cosmetic fade. Normal upstream pause behavior remains intact. New actions do not create a second player instance or dispose the shared port.

### 7. Provide a profile action recorder and clear combo notation

The profile screen starts with P1, offers Add profile up to three, and lists only the selected player's six actions. Global timing and Practice live on separate Settings destinations. Set opens a recorder with the three buttons, live tap/hold feedback and an ordered strip of up to five strokes. Use Forward/Pause/Backward symbols, a distinct HOLD badge or bar, tap markers and accessible text. Provide undo/clear/cancel/save. Saving reports the owner/action of any duplicate; shared-prefix warnings explain recognition delay.

Recording gaps are not used to auto-save or split the draft, allowing the user to build the intended ordered sequence deliberately. Runtime/practice uses the configured gap timer. A runtime pad identifies the recognized profile/action and presents denial/failure feedback; choosing a profile for editing does not activate that player's bindings exclusively.

### 8. Bring combo controls into Now Playing

Accepted on 2026-11-16 after inspecting the running API 36 emulator: the
standalone pad is too hidden below the profile action list. Add an explicit
Player / Combo switch on Now Playing and a visible profile-setup shortcut.
Player mode retains conventional transport. Combo mode uses the existing
recognizer/dispatcher through a page-owned input session, with circular
Backward / Pause / Forward inputs, compact ordered tap/hold notation and owner
feedback. Preserve the live player's background, artwork, thin icons and glass
dock; do not add another blurred surface. Reserve control space first and shrink
the artwork on smaller screens. Cancel input on mode changes, navigation and
focus loss. Retain the existing recorder and separate Practice pad.

## Risks / Trade-offs

- [Upstream tests or build may fail locally] -> Import and baseline verification are the first checkpoint; resolve specific failures before dependent work and report device limits honestly.
- [Short combinations wait for longer candidates] -> Accessible on-demand prefix details, separate timing settings and fake-time boundary tests.
- [UI recording accidentally controls playback] -> Separate recording/practice sinks and widget tests proving no adapter calls.
- [Skill bypass through renamed profiles or alternate combos] -> Stable identity and central attributed dispatch; conventional media controls remain explicitly outside gameplay attribution.
- [Concurrent automatic queue advancement] -> Distinguish operation-correlated success from unrelated playback events in adapter tests.
- [Upstream updates conflict with changes] -> Pin the import and keep Hadoken features in separate modules with a thin playback adapter.

## Migration Plan

1. Import the pinned source while preserving existing repository files and attribution; record the source revision and baseline results.
2. Introduce versioned profile configuration with empty bindings; existing music playback remains usable before setup.
3. Add recognition, dispatcher and UI incrementally with focused tests and the final Android playback matrix.
4. Roll back a faulty new configuration to the last valid document; disabling combo controls leaves the upstream player usable. Do not overwrite music-library or playback-session data.
5. Complete and synchronize/archive this change before applying `add-player-skills`, so the second change can verify the final dispatch contract.

## UI simplification accepted 2026-11-16

Each screen has one responsibility. Remove prose help alongside profile,
recorder and pad controls, retaining concise action labels, tap/hold markers,
owner conflicts and validation. Do not add documentation outside OpenSpec/zmem
without an explicit request. Move agent-written reports from docs into this
change's local evidence area; preserve upstream licensing/provenance files.

## Verification status

Formal verification completed on 2026-11-16; see evidence/formal-verification.md for coverage and the resolved timing-observation gap. All implementation checkpoints pass. Synchronization/archive follow this verified checkpoint; Stage 2 remains separate.
