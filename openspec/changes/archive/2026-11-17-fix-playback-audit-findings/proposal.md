# Proposal

## Why

The playback audit reproduced three correctness defects and found unbounded action bookkeeping plus a failing formatting gate. Fixing these closes gaps in declared listeners, attributed skip results and interruption recovery before extending the skill catalog.

## What Changes

- Deliver unfiltered declared combo listeners according to their activation and player scope.
- Recognize successful forward entry into an edited loop while rejecting unrelated queue changes.
- Resume after interruptions only when the interruption paused active playback and no later transport intent cancels resumption.
- Bound completed action/invocation/effect bookkeeping and release per-request execution state with bounded recent duplicate protection.
- Correct the one formatter failure and add focused regression coverage for the audit cases.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `player-skills`: clarify optional combo filters and scoped delivery.
- `player-actions`: specify edited-loop success and bounded request bookkeeping, preserving in-flight duplicate protection.
- `audio-playback`: require interruption-owned resume intent and cancellation by later user transport or route loss.

## Impact

Policy/coordinator/dispatcher, playback command adapter, native transport intent tracking and audio session service; focused unit/integration tests. No dependencies or UI changes. Existing independent skill modules, effort rules and silent cleanup remain unchanged. Physical-device acceptance and unrelated audit exclusions are outside this change.
