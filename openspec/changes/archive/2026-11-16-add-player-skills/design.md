# Design

## Context

See proposal.md for motivation. This change depends on completion and synchronization/archive of `add-profile-input-bindings`. The prerequisite is verified and archived as 2026-11-16-add-profile-input-bindings; its four main specifications and current implementation define the contract. Troona is the selected audio foundation. Existing upstream AudioServicePort commands remain the playback boundary; this change adds no second audio engine and no behavior inside Troona's audio adapter.

The prerequisite introduces stable P1-P3 identities, globally unique complete combinations, a serialized attributed action dispatcher, explicit outcomes and an allow-all PlayerAbilityPolicy. Its `player-actions` specification already permits a pre-execution ability decision and post-success notification, so the new `player-skills` capability implements that extension without changing input ownership or recognition requirements.

## Goals / Non-Goals

**Goals:** Implement a small code-defined skill catalog, persistent profile assignment and deterministic runtime effects through the existing dispatcher. Start with the user's ten-second skip-recovery example and meaningful fake-time and integration tests.

**Non-Goals:** A rule language, visual condition editor, downloadable skill code, user-configurable skill durations, point systems, networking or input-device extensions. Only attributed combos invoke player skills; conventional transport and Android media controls retain their Stage 1 behavior. A process restart begins a new skill session, so this is not anti-cheat enforcement.

## Decisions

### 1. Use static skill definitions with a fixed initial catalog

Introduce `lib/features/player_skills` domain/data/presentation modules. Define stable `SkillId` values and code-owned metadata/behavior; the initial value is `skip-recovery`. Its display name is Skip Recovery and its duration is a constant ten seconds. The profile selector displays its behavior and allows assignment, with no configurable conditions or numeric fields.

Persist each profile's set of assigned known IDs in a separate versioned preferences document. Empty sets are the default and the initial catalog has only one entry; using a set permits future named skills without introducing a general rule graph. New skill behavior still requires code, review and tests. Do not introduce third-party plugin loading or a generic expression evaluator. Unknown stored IDs are inactive and shown as unavailable rather than executed or silently reinterpreted.

### 2. Attach effects to profiles, not bindings

Install a concrete PlayerAbilityPolicy implementation in the existing composition root. It evaluates the request's stable profile ID and canonical action. Bindings remain editable independently; a new input sequence for next track reaches the same profile cooldown. Display-name changes and profile navigation do not modify skill state.

Assignment changes are serialized with action processing. If the affected profile has an active cooldown, reject assignment changes with remaining-time feedback. This prevents removing/reassigning the skill from erasing a live effect. Saved assignment updates activate only after persistence succeeds. Other profiles' assignments remain editable. There is no need to freeze the whole profile or to restrict unrelated actions.

### 3. Implement Skip Recovery as one explicit state transition

State is a map from stable profile ID to an elapsed-time deadline. Before next track, deny if Skip Recovery is assigned and `now < deadline`; otherwise permit. Other actions are permitted by this skill. After a successful attributed next-track operation, set only that profile's deadline to `completionTime + 10 seconds`.

The dispatcher already serializes checks, playback and success processing. Preserve that order and make success handling idempotent by request ID. Failed, denied and no-op outcomes cannot update the deadline. A later request is checked at processing time, not against the recognition time captured before it waited in the queue. Other profiles' actions never reset or extend this profile's deadline.

No state timer needs to execute a deferred playback command. Cooldown expiry simply makes the next request eligible. A display timer updates remaining-time text while visible; eligibility always compares actual elapsed time. Completed request identities are retained for the service session by the prerequisite's dispatcher.

### 4. Use a clock that includes Android sleep for cooldowns

Inject a small elapsed-time source so domain tests control time without sleeping. On Android use `SystemClock.elapsedRealtime()` through a narrow platform adapter at evaluation/success/resume boundaries; it is monotonic and includes deep sleep. Foreground UI countdown interpolation is cosmetic and must refresh from that clock before eligibility decisions. Do not assume a suspended UI timer or wall-clock subtraction is authoritative. [Android clock documentation](https://developer.android.com/reference/android/os/SystemClock).

Skill runtime state is retained for the process/service session and is not stored across process death. Assignment persistence is independent. On return from background, recompute remaining time; on a new process, begin with empty deadlines. This avoids resurrecting stale actions or introducing clock-recovery rules outside the requested gameplay scope.

### 5. Expose named abilities and understandable feedback

Add a separate Player skills Settings destination with an existing-profile selector, named skill assignment and current recovery status. Keep Profiles exclusively for bindings. Show a concise ten-second summary and expose the fuller description on demand. Use the existing action outcome surface to display denials such as P2 / Skip Recovery / 4 seconds remaining. Expose text and accessible status rather than relying on color. The input recorder retains its fighting-game combo display and remains free of skill side effects.

The fixed catalog and optional assignment are intentionally different from editing the binding. Users can see which action a combo requests and separately which skill changes its eligibility.

## Risks / Trade-offs

- [Prerequisite contract changes during implementation] -> Before applying, compare the synchronized player-actions/player-profiles specifications and existing code to this plan; reconcile concrete drift before dependent edits.
- [Playback failures incorrectly start cooldowns] -> Consume only confirmed success outcomes and test boundary no-ops, adapter failures and duplicate deliveries.
- [Two rapid requests both pass] -> Keep eligibility and post-success state changes inside the existing serialized dispatcher, including assignment mutations.
- [Background timers pause] -> Compare Android elapsed-time deadlines, refresh on resume, and cover real background transitions in acceptance checks.
- [Small initial catalog] -> Ship one fully specified skill; additional named skills need explicit code changes rather than exposing generic customization.

## Migration Plan

1. Require the first change's implemented, verified and synchronized contract before applying.
2. Load existing profiles with empty assignments when the skill document is absent; preserve bindings, library and playback state.
3. Register the static catalog, policy and skills UI, then verify the P1/P2 interaction and persistence cases.
4. A rollback to the Stage 1 application ignores the separate skill document and restores normal attributed command eligibility; it does not delete bindings or media data.

## Integration reconciliation — 2026-11-16

Use the existing PlayerAbilityPolicy async pre-check/post-success hook. Add a dispatcher-owned ordered mutation entry point for assignment changes so they cannot race in-flight playback; do not mutate assignments directly from UI. The profile repository now contains only explicitly added profiles (P1 by default). Skill edits reject unadded profiles. Register the policy once with the existing audio adapter, without an awaited clock platform call during startup. Runtime policy failures remain fail-closed under the existing dispatcher contract.

Verification and implementation evidence stays in this OpenSpec change; do not create docs or inline help paragraphs.

## Verification status
Formal verification completed on 2026-11-16 with all requirements covered and no unresolved findings. See formal-verification.md and evidence.md. Synchronization and archive follow this verified checkpoint.
