# Proposal

## Why

The production catalog still contains the Skip Recovery demonstration. Real gameplay needs a global song commitment and a manual override, backed by declared listeners and scoped state rather than skill-specific application code.

## What Changes

- Add named listener declarations, explicit listener activation, lifecycle events and typed transient state to independent skill runtimes.
- Supply actual listening-time and track-boundary observations from the playback service, including background playback, pause/buffering and repeat boundaries.
- **BREAKING** Replace Skip Recovery with Song Commitment: after 20 seconds of actual listening, block next track, previous track and seeking for all attributed players at effort 90 until the song ends or a stronger action changes it.
- Add Force Skip with a user-recorded manual macro and activation/generated-skip effort 100.
- Keep exclusive skill ownership, concise illuminated tiles and effort numbers in on-demand details. Remove the retired mock assignment without silently equipping a stronger replacement.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `player-skills`: declared listeners and state lifecycle, playback observation, production skill catalog, removal of recovery-specific requirements and updated status/migration behavior.

## Impact

Independent skill contracts/modules, skill policy and coordinator, playback adapter observation, dependency wiring, assignment migration and existing skill UI/tests. No new packages, user rule editor or persisted transient gameplay state. Conventional unattributed transport retains its existing behavior.
