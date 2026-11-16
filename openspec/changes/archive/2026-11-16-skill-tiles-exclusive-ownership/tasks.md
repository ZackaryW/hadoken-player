# Tasks

## 1. Exclusive ownership checkpoint

- [x] 1.1 Enforce exclusive known-skill ownership, recover duplicate saved assignments, and verify concurrency, failed writes, restart, unknown IDs and cooldown-safe reassignment with focused domain tests.

## 2. Tile interface checkpoint

- [x] 2.1 Replace switch rows with responsive square tiles and ownership feedback; verify toggle, details, cooldown, disabled-owner state and large-text layouts with widget tests.
- [x] 2.2 Build and install on the current emulator, inspect active/inactive/other-owner tiles, and run analysis plus the full test suite; record evidence in this change.

## Workflow follow-up

- Commit each verified implementation checkpoint using zmem validation and pspec preflight, keeping active planning local.
- Verify implementation against the delta, synchronize main specs, archive and clear temporary change state, then commit reviewed final artifacts.
