# Design

## Context

See proposal.md for motivation. Current independent definitions expose trigger sets and private runtime fields; combo listeners are dynamic capability requests. SkillPolicy routes owner actions and the coordinator validates and executes typed reactions. The production adapter has session generations and stable loop occurrence identities, but no listening-time contract. Main specs explicitly preserve the retired mock and must change with the implementation.

## Goals / Non-Goals

**Goals:** Make listener metadata, activation and typed transient state reusable across hardcoded skills; derive gameplay from real playback observations; preserve serialized action execution and exclusive ownership.

**Non-Goals:** A rule editor, arbitrary persistent metadata, changing conventional unattributed transport, redesigning the player or adding more abilities.

## Decisions

### Named subscriptions and typed state

Add neutral listener declarations with stable keys, trigger, player scope, optional combo filter and initial enabled state. Runtimes explicitly toggle declared keys, with rejection of unknown keys. Route matched listeners through a named callback, preserving onEvent compatibility for existing test definitions. Static declarations complement dynamic bounded ArmComboListener requests; they do not compete with executable combos. Equip/unequip and playback observations join the event contract. Manual activation must have an active matching listener.

Provide a typed key/value session-state container per runtime, rather than untyped JSON or app-owned skill fields. Reset on ownership/session changes, retaining persistent assignments/macros only. Skill modules own state keys and defaults. Reactions still return capabilities; result callbacks cannot recursively execute them. Generic decision scope allows a global equipped skill to evaluate every added player's action without per-skill policy branches.

### Actual listening observations

Add an optional playback observation port implemented by the production audio adapter. A monotonic accumulator counts intervals only while the decoder is playing/ready and transport intent permits playback. Pause/loading/buffering exclude time; seeking and speed changes add no artificial time. Sampling at action evaluation closes gaps when UI timers/background callbacks are delayed. Stable session/loop/occurrence identity plus native natural-transition observations distinguish repeat-one and duplicate songs. Current-occurrence-preserving queue edits retain the counter; completion or a different play resets it.

Use adapter-native state and discontinuity observations, not UI position deltas or a twenty-second widget timer. Position-delta accumulation would falsely count seeking and speed changes. Tests inject elapsed time and drive native-like transitions. The policy forwards snapshots within the existing ordered queue and before eligibility checks; stale observations cannot overwrite a newer play. Playback observations cannot recursively generate playback commands.

### Production skills

Song Commitment declares an initially active playback listener and global decision scope. Its typed state tracks play identity and whether twenty seconds have been heard. The independent runtime owns threshold, protected actions, effort 90, concise status and an assignment-lock reason. It remains locked through pauses, even for unknown durations, and unlocks only when the play ends/changes. Equipping mid-song uses the current accumulated snapshot. Assignment changes cannot bypass the active lock. No fictional remaining-duration countdown is used.

Force Skip declares a manual listener and requests ExecutePlayerAction for its owner at effort 100, with activation effort 100. Existing validation, strongest-block comparison, invocation deduplication and backend result reporting apply. A no-op must not be rendered as a successful skip. There is no additional cooldown or number editor.

### UI and migration

Keep the square grid and existing macro recorder. Use presentation-only icons, generic runtime status and generic assignment-lock feedback. Details interpolate declared efforts for each action. Retire skip-recovery from the production registry and remove its saved assignment with a recovery message; require explicit opt-in to new behavior. Preserve unrelated unknown keys and all profile inputs. Retain the old behavior only as a test fixture where it verifies generic cooldown support, not as a production skill.

## Risks / Trade-offs

- Native transitions and playlist transactions can emit transient indices → sample stable occurrence identity; ignore intermediate render identities and test current-occurrence edits, duplicate songs and repeats.
- Background observation may be delayed → monotonic listening snapshots are read at execution and UI refresh, independent of widget timers.
- A global lock can appear removable through its owner's tile → independent assignment-lock status is checked in the same ordered operation as edits.
- Existing tests use the mock as a generic policy fixture → explicitly inject a test-only fixture and separately verify the production registry and migration.
- Listener/state lifecycle could leak between owners → ownership synchronization and session reset tests, including disabled listeners and late events.

## Migration Plan

Implement and verify the reusable contracts/routing first, then playback observation, then production skills/catalog/UI and migration. Commit each coherent verified checkpoint with active planning excluded. Run focused regression tests, the full suite, static analysis, Android build and emulator smoke checks. Keep acceptance evidence here. Synchronize specs and archive only after implementation verification; a final artifact commit follows successful sync/archive. Rollback code does not restore a retired assignment automatically, but profile bindings remain intact.
