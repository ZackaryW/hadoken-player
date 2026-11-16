# Proposal

## Why

The skills screen uses a settings-style switch rather than the requested game-like tile selection. Assignments also allow the same skill on multiple players, contrary to the clarified exclusive ownership requirement.

## What Changes

- Present skills as square icon-and-text tiles, lit when assigned to the selected player and gray when inactive.
- Enforce one owner per known skill across profiles; show the owner on unavailable tiles and require explicit removal before reassignment.
- Recover legacy duplicate assignments deterministically with visible feedback.
- Preserve Skip Recovery's fixed ten-second behavior and existing cooldown edit guard.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `player-skills`: exclusive persistent skill ownership and a responsive tile-grid selector.

## Impact

Skill assignment repository, Skills page, semantic icons, and focused domain/widget tests. No new dependencies, skills, rule engine, or one-skill-per-player limit.
