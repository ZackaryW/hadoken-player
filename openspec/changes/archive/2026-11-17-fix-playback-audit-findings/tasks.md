# Tasks

## 1. Listener delivery and skip attribution

- [x] 1.1 Fix declared combo routing and edited-loop skip outcomes; add regressions for unfiltered/filtered/scoped/inactive listeners, changed next-loop contents, pause preservation and unrelated transition rejection; run the relevant player action, skill and loop tests and commit this verified slice.

## 2. Interruption recovery

- [x] 2.1 Track interruption-owned resume intent and subsequent cancellation, serialize begin/end handling, and add paused/stopped, active, failed-pause, disabled-resume, explicit cancellation, route-loss and rapid-event regressions; run interruption/mixer/native adapter tests and commit this verified slice.

## 3. Bounded bookkeeping

- [x] 3.1 Bound completed dispatcher/coordinator retention, preserve pending duplicate protection and release request-local policy state on every terminal path; verify retention limits, denied/no-op/failure cleanup, pending duplicates and live-effect cleanup after eviction, then commit this verified slice.

## 4. Integration acceptance

- [x] 4.1 Format the reported test file, run the exact CI formatter, analysis, full test suite, original audit probes and strict change validation; record actual results in this change and commit the formatting correction after checks pass.

## Workflow follow-up

- Keep active planning local. Review/verify before the separately requested synchronization and archive; only then commit reviewed main specs and archived artifacts.
