# Proposal

## Why

Hadoken Player needs a dependable background audio foundation and a way for up to three players to express the same playback action through different timed input sequences. Keeping player attribution separate from playback will allow a later change to add predefined player skills without rebuilding input recognition.

## What Changes

- Import Troona (`donfreddy/troona-music`) at reviewed revision `3f233344a28328fa380b2e8ac0c81ab061259ff6` and verify its Android background playback before extending controls. Preserve this repository's identity and local planning files.
- Add a focused binding screen starting with P1 and an explicit Add profile control, up to three persistent players. Global timing and practice have separate settings screens. Each added profile has independent action bindings. Three on-screen buttons (Forward, Pause and Backward) each support short press and long hold, giving six stroke types.
- Recognize sequences of one to five tap/hold strokes, preserving timestamps and allowing configurable hold and inter-stroke timing.
- Make each complete combination exclusive across all profiles, regardless of its assigned action. Allow shared prefixes and resolve them with an explicit continuation timeout; the matched combination identifies its owning profile.
- Keep each binding compact: group Set/Clear with the action, put the combo directly below, and expose shared-prefix timing through an adjacent info control on demand.
- Add a Set recorder for each action, global conflict validation, and a practice mode. Show recorded combinations as Street Fighter-style ordered button icons with tap/hold markers; recording and practice never change playback.
- Surface a Player / Combo mode switch on Now Playing, preserving its artwork and glass styling while exposing circular combo inputs and direct profile setup.
- Route recognized commands through a single profile-attributed action dispatcher and playback adapter, leaving one explicit extension point for the separate player-skills change.
- Capture on-screen button presses while the app is visible; infer the profile from the uniquely owned complete combination. Background music and standard system media controls continue without promising on-screen input while the app is hidden.

## Capabilities

### New Capabilities

- `audio-playback`: Playback, queue operations and Android background media controls independent of profile screens.
- `player-profiles`: Persistent profile identities and profile-specific input customization.
- `input-recognition`: Three buttons with six tap/hold stroke types, timed sequences, Set recording, combo display, validation and practice feedback.
- `player-actions`: Profile-attributed dispatch, playback results and a narrow extension point for predefined skills.

### Modified Capabilities

None. There are no existing main specifications.

## Impact

Troona's application, dependencies and Android setup are imported. The implementation adds profile storage, input capture/recognition and an adapter to its existing playback interface. Troona is a smaller project with relevant tests, not a proven large-scale application; baseline and integrated Android checks are recorded in evidence/hadoken-verification.md; formal whole-change verification, main-spec synchronization and archive are still pending. This change does not implement skills, an arbitrary rule editor, scripts, remote multiplayer or additional platform support. It is the prerequisite for `add-player-skills`.
