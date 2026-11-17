# Design

## Context

See proposal.md for motivation. The audit probes reproduce all three behavior failures. ProfileControls creates a fresh UUID at its sole production dispatch site; there is no request retry/replay transport. The current maps nevertheless retain every result. Independent skill modules and existing effort reconciliation remain unchanged.

## Goals / Non-Goals

Goals: correct observed outcomes and listener delivery; prevent unwanted interruption resume; bound completed bookkeeping without losing active resources.

Non-goals: network delivery guarantees, durable replay storage, new gameplay rules, UI changes, or physical-device certification.

## Decisions

- Route comboObserved declarations when the filter is absent or matches. Keep activation and scope in runtime matching rather than duplicating them in policy. Legacy combo trigger declarations remain armed-only capability callbacks; explicit subscriptions do not also receive dynamically armed callbacks.
- For a forward wrap on a LoopQueuePort, compare session, expected next loop and first occurrence in the resulting loop. Check the original loop/occurrence again after quiescing playback. Preserve ordinary same-order checks elsewhere. This accepts legitimate future edits without treating any queue replacement as success. Empty next loops remain no-ops.
- Serialize interruption events. Record resumption only after a successful pause of playing audio. Expose a small optional transport-intent revision contract from the native adapter so another pause, resume, stop or session replacement invalidates pending resumption even if status stays paused. Route loss cancels immediately. Status-only checks cannot detect repeated Pause commands. Keep normal duck gain behavior.
- Retain up to 256 completed request/invocation outcomes and 4096 effect results in insertion order; keep pending futures separately. Drop execution budgets/session captures at the dispatch terminal boundary, including exceptions. Completed effect cache eviction does not revoke live effects. No persistent store or new identity protocol: neither is justified by the actual input path. Old evicted IDs have no duplicate guarantee, documented in the delta.
- Verify with focused regressions using existing fake native players and real adapters. Keep the previous 902-test suite and exact CI format/analyze gates as whole-change acceptance.

## Risks / Trade-offs

- Native transition races → preserve pre-skip pause guard, compare session/loop identity and test unrelated replacement and automatic advance rejection.
- Asynchronous interruption pause → ordered events plus intent revision checks; tests cover rapid begin/end, failed pause and cancellation.
- Evicted duplicate identities can run again → callers issue fresh IDs; recent/in-flight duplicate tests cover the real contract. No replay infrastructure is added.
- Cache pruning could discard resource ownership → effect ledger remains authoritative and tests exercise cleanup after eviction.

## Migration Plan

No saved-data migration. Implement and verify each checkpoint before committing explicit code/test paths. Active planning stays local. Final artifact synchronization/archive is separate from implementation and occurs only when requested after verification.
