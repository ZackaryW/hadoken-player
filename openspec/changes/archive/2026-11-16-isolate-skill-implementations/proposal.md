# Proposal

## Why

Skill-specific behavior is embedded in the shared policy, and the UI names Skip Recovery directly. This does not provide the independent skill source folder the user requires.

## What Changes

- Establish `lib/skills/` as an independent pure-Dart source boundary, with a shared contract, static registry and one folder per implementation.
- Move Skip Recovery metadata, duration, effects and session state into its own module.
- Make the feature policy an adapter and render tiles from registered definitions.
- Verify isolated behavior and enforce the import boundary with tests.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `player-skills`: independent skill source modules with a stable application-facing contract.

## Impact

Skill policy, catalog imports, tile rendering, tests and project context. Existing assignments, skill IDs, cooldown behavior and tile appearance stay compatible. No additional skills, dependencies, scripting or configurable rule engine.
