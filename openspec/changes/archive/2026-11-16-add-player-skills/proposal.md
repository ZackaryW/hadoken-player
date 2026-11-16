# Proposal

## Why

Players should have distinct abilities while sharing one music player. A small catalog of predefined skills provides that game-like behavior without asking users to build or maintain a general rule system.

## What Changes

- Depend on `add-profile-input-bindings` for profile identities, recognized action requests and the playback dispatch interface.
- Add a code-defined catalog of skills and a separate Player skills screen for assigning them. Users select existing skills rather than authoring conditions, durations or scripts.
- Introduce an initial fixed skip-cooldown skill: after its owner successfully skips to the next track, that owner cannot skip again for ten seconds; other profiles remain eligible subject to their own skills.
- Evaluate skill behavior at the central action dispatcher and update transient skill state only after a successful playback action.
- Display skill descriptions and action-denial feedback, including remaining cooldown time.
- Keep input bindings independent of skill assignment so changing an input sequence cannot bypass a profile's ability behavior.

## Capabilities

### New Capabilities

- `player-skills`: Predefined skill catalog, per-profile assignment, deterministic action effects and feedback.

### Modified Capabilities

None at planning time. The prerequisite change defines a skill-aware dispatch extension point; this change supplies its concrete implementation. Reconcile against the prerequisite's synchronized main specifications before applying if its contract changes.

## Impact

Adds skill definitions, assignment persistence, temporary runtime state and a focused skills screen. Integration uses the dispatcher implemented by `add-profile-input-bindings`; the selected audio backend is not modified to contain game rules. The first skill is intentionally narrow, with its ten-second duration and behavior defined in code. No general-purpose rules engine, skill scripting, user-authored conditions or arbitrary skill parameters are introduced.
