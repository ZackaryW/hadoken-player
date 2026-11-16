## 1. Effort visibility

- [x] 1.1 Show code-derived effort beside skill action/block mentions and manual activation in details; verify passive/manual widget coverage at normal and large text, existing skill behavior tests and analysis.
- [x] 1.2 Build and install the normal Android app without clearing data; inspect the updated Skip Recovery dialog on the emulator and record the result here.

## Verification

- 28 focused widget, independent-skill and architecture tests passed. Manual activation shows Activate (80); passive details show every skip/block mention with (50), including at 360×640 and text scale 2.0. Existing cooldown behavior remains unchanged.
- `flutter analyze --no-pub`: no issues. Android debug build passed using `tool/build_android.ps1`; install-replace preserved app data.
- Actual emulator inspection on 2026-11-16 confirmed Skip Recovery details read “After your skip (50): block your skip (50) for 10s. Other players: skip (50).” Dialog controls remain visible without overflow; P1/P2 and P1's equipped tile remain intact.
- Spec review: one added requirement and three scenarios covered; no missing implementation or design divergence found.

## Workflow follow-up

- Commit verified code/tests incrementally with zmem validation and pspec preflight, keeping active planning local.
- Synchronize the player-skills delta, archive the completed change, clear its temporal state, then commit the reviewed specification/archive artifacts.
