# Design

## Context

See proposal.md for motivation and the five capability deltas for behavior. The accepted decisions are current and future loop targeting, listeners across any player's combos, and the existing six input types with a five-stroke limit.

Repository evidence:

- `lib/skills/skill.dart` currently offers action eligibility, post-success recording and recovery inspection; no effect execution or macro event contract exists.
- `SkillPolicy` creates independent runtimes but routes only the requesting profile's assignments. `PlayerActionDispatcher.runOrdered` already serializes actions and assignment edits.
- `ComboInput` resolves a single saved `ActionBinding` and retains stroke observations. `ProfileControls` currently drops those observations when constructing the playback request.
- Profile storage already atomically validates complete-combination uniqueness, but its targets are playback actions only. Skill assignments use a separate stable-ID document.
- `Queue` has one original/playback order and a current index. `AudioServicePort` exposes current-queue edits, speed and volume; it has no loop plan, mixing or pitch contract.
- `JustAudioAdapter` owns one `AudioPlayer` and mirrors native indices. `AudioSessionService` pauses/ducks that port; a second unmanaged player would evade those controls. The lockfile pins just_audio 0.10.5.
- Existing tests include pure skill timing, policy delegation, real playback-adapter integration with a test audio port, profile uniqueness and responsive skill tiles.

## Goals / Non-Goals

**Goals:** Provide working application adapters behind an independent typed capability API. Let code-defined skills express all requested mechanics without adding behavior branches to shared policy or UI. Preserve ordinary transport, exclusive ownership and saved configurations.

**Non-Goals:** A user-authored rule engine, downloadable code, an invented new catalog of gameplay abilities, exported/destructively edited music files, beat detection or sample-accurate DJ synchronization. Mixing here means audible temporary noise and simultaneous two-song blending with fixed gains, offsets, speed and pitch chosen by skill code. This is an Android acceptance target; other backends must report their actual support.

## Decisions

### 1. Extend the independent source contract, keep services outside it

Keep all neutral types in `lib/skills/`, with subfolders for capability contracts and skill implementations. Add sealed event and request types rather than string commands or expressions. A definition declares its trigger modes, required capabilities and code-owned limits; each runtime owns its private state.

The application supplies immutable `SkillContext` snapshots: elapsed time, session/loop identity, added player IDs, the equipped owner, resolved input actor, effective bindings, queue occurrences, relevant opaque song references and backend support. No Flutter widgets, app entities, file handles or native players cross this boundary. Media selection uses stable library IDs or queue-occurrence references; the adapter resolves accessible local files. The typed FindSongs request supplies a bounded read-only song-catalog query (1–200 results) through the queue capability; result callbacks receive opaque references when a skill needs to select beyond the current queue.

Use `onEvent(event, context) -> SkillReaction` for input observation, manual activation, action success and expiration; reactions contain typed capability requests. Keep `decide(action, context)` side-effect free. `CapabilityResult` callbacks update private state but cannot recursively submit a new batch in the same result chain. A skill declares its fixed failure cleanup policy. Skip Recovery keeps its existing action-success semantics through this contract.

| Request family | Minimum contract |
| --- | --- |
| Queue edit | session ID, loop selector, expected revision, insert/remove operations, opaque song/occurrence references |
| Start mix | source references, noise/song layer kind, offsets, gain/speed/pitch, duration, source-change policy |
| Restrict actions | target profile selector, playback or skill-activation action selectors, duration |
| Override combos | explicit profile/action replacements, one-to-five neutral strokes, duration |
| Arm listener | listener key, exact stroke pattern, target profile selector, duration, once/repeated mode |
| Execute playback action | attributed added player, playback action, code-defined effort; origin/invocation retained |
| Revoke effect | effect handle belonging to the requesting owner/skill |

Each request carries invocation/effect IDs supplied or validated by the coordinator. Results include status, reason, applied revision and optional effect handle/deadline. An invocation can have mixed results; there is no fictitious cross-audio/storage transaction. Validate shapes, targets, support and revisions first, then apply in order and return each outcome. Existing playback outcomes remain success/denied/no-op/failure; capability results additionally distinguish unsupported operations.

### 2. One deterministic coordinator and finite effect ownership

Extend the ordered dispatcher flow rather than creating independent timers that mutate profiles/audio from skill code. Within one input request:

1. Retire due effects; validate the effective-catalog revision and executable target.
2. Publish one immutable physical-combo observation to the snapshot of eligible listeners, ordered by owner P1–P3, skill key and listener key.
3. Apply listener reactions in that order, validating each again against current state. A listener installed during this input cannot observe that same input. Revalidate the primary target if a reaction changed effective bindings.
4. Validate eligibility and reconcile the primary target's code-defined effort against all applicable active blocks, then execute the playback action or manual activation.
5. Deliver success-only action hooks and capability results. Return one primary outcome plus associated effect outcomes.

Listener effects can therefore block the triggering action. A denied primary action still corresponds to an observed physical combo; it never creates an action-success event. Synthetic outputs, callbacks and expired actions cannot re-enter the physical input path. Cache input, invocation, effect and callback identities to prevent double application. Use bounded per-event effect counts and no recursive reaction chains; limits live in code, not a user rule editor.

An effect ledger records source skill/owner, target IDs, session, deadline, resource handle and cleanup operation. Resolve `self`, `others`, `all` and explicit selectors to added profile IDs when an effect is applied; newly added profiles require a later invocation. Restrictions union together; an expired cause does not erase another. Ordinary system transport bypasses player restrictions as before. A restriction can select playback actions or manual activation targets; it does not arbitrarily prohibit editing/settings.

Effect timers enqueue cleanup, while every evaluation also checks absolute elapsed deadlines. Android elapsedRealtime remains the clock source. Audio-layer expiry additionally needs service-side scheduling so a suspended UI timer cannot leave sound running. Cleanup is idempotent and runs on expiry, revocation, stop, session replacement or teardown. Active effects lock the source owner's assignment edits. Do not persist effects or resume them after process death. Discrete queue edits already applied are not undone by unequipping; pending future plans are session effects with cleanup handles.

### 2a. Reconcile actions with code-defined effort

The user confirmed higher effort wins, ties block, and values belong in skill code. Introduce a validated integer `Effort` value: -1 is infinite minimum, 0–99 normal levels and 100 infinite maximum. Use 50 for ordinary actions and unspecified declarations. Compare values directly; do not perform arithmetic on the infinity sentinels or use effort to reorder the session queue.

Each manual activation and generated playback action carries its own code-owned effort. Runtime eligibility blocks and temporary restriction effects also carry effort. An otherwise valid action must be strictly greater than every applicable live block; the highest block determines denial, with stable source ordering for tied blockers. No blocks means eligible even at -1. An effort-100 block cannot be overcome, including by an effort-100 action. Effort cannot bypass invalid ownership/bindings, unavailable capabilities or actual playback failures. Normal Skip Recovery retains its ten-second behavior at default effort; it participates in the same comparison when a skill explicitly generates a stronger action.

Add `ExecutePlayerAction` to the capability contract so a manual skill can request a skip without touching playback services directly. Preserve the source skill, owner, attributed target player and invocation. Execute inside the existing ordered operation, validate/reconcile, and notify success only for a real successful action. A permitted activation does not automatically authorize its generated skip: those are distinct targets and checked separately. Generated action success may update passive runtimes and produce bounded non-playback effects; it cannot recursively request another playback action in the same chain. All effects share the original event's finite budget. These outputs never become physical combo observations. The ordinary notification/device transport path remains unattributed as before.

### 3. Model loops before mutating native playlists

Add a session queue coordinator with a baseline, monotonically increasing forward-loop ordinal, stable occurrence IDs, revisioned per-loop snapshots and scheduled edit plans. A shared monotonic mutation revision conservatively invalidates stale requests across loops. `LoopSelector` supports current, one absolute future ordinal, and a future range with optional open end. Resolve relative N+offset selectors against a snapshot at submission; never reinterpret a stale future target as current.

Materialize a future loop from the baseline and applicable edit plans in committed order. Queue insert/remove operations address occurrence IDs, not indices or song IDs alone. Preserve a baseline-occurrence identity across materializations so a range can remove the same baseline song occurrence from several loops. Inserted occurrences get distinct identities. Future plans have bounded elapsed-time lifetimes and explicit revocation, including plans whose loop range has an open end. A future loop is only committed when playback enters it: preloading is provisional. Expiry, revocation or another edit rebuilds affected unstarted loops, including the prepared native window, without undoing an already applied current-loop edit.

Ordinary queue edits continue updating the user's baseline and live queue; skill current-only edits affect that loop only. Revalidate scheduled removals when materializing after baseline changes and report stale/no-op results. A replacement playlist starts a new session generation and invalidates old plans. Removing the current occurrence chooses its next surviving successor without rewinding to an already played item; if none remains, stop. Preserve pause state. Empty planned loops stop rather than spin through unbounded empty cycles.

The audio adapter maintains a bounded native window for the current and next loop and maps native items to session/loop/occurrence IDs. It must prepare the edited next loop before forward advancement; relying on native repeat-all to wrap and then patching the queue is too late. All manual navigation and native transition observations enter the same coordinator with revision checks. Only forward wrap advances the loop ordinal; previous navigation stays within the current materialized loop. Repeat-one does not advance a loop. With repeat off, future plans stay dormant until repeat-all is enabled and the boundary is reached. Shuffle order is materialized per loop and remains stable during that loop's edits.

### 4. Coordinate audio layers under the existing service

Introduce an application `SkillAudioEffectsPort` implemented by a mixer coordinator owned by the existing audio session. Keep the primary decoder and add bounded secondary just_audio players for local noise/song layers; do not create another audio_service handler or notification. The independent skill API describes layers; the mixer owns player creation, source preparation, gain envelopes, speed/pitch, transport and teardown.

First support one active mix session at a time; competing mix requests receive an explicit conflict. One noise overlay or a two-song blend is sufficient to exercise the API. When a source-bound two-song mix includes the current occurrence, reuse the primary player; continue-until-deadline mixes use independent layers so a new primary occurrence cannot inherit the old transformation; otherwise temporarily attenuate the primary output while the requested layers sound, retaining the primary timeline. Source-track changes cancel source-bound mixes. Gains compose with current user volume, fade and duck factors so cleanup cannot overwrite a newer user volume. Resume only layers belonging to a still-live effect and only when the session's playback intent permits it. Parameters and durations are bounded by code-owned backend limits.

Evidence: upstream [multiple-player support](https://pub.dev/packages/just_audio#working-with-multiple-players) and [pitch API](https://pub.dev/documentation/just_audio/latest/just_audio/AudioPlayer/setPitch.html) make this approach plausible. These documents do not prove this app's background/interruption behavior, layer alignment or installed-version/device support.

Before production mixer integration, run a bounded Android feasibility check with two local test tones/song clips and a bundled/generated noise clip: prove both frequency components are present in captured output, speed/pitch changes are measurable, pause/duck/stop affect every layer, screen-off effects expire, and failing a source releases prepared resources. Keep the experiment and evidence under the active change or normal test sources. This plan does not execute that experiment. If the current backend cannot meet these criteria, stop the mixer checkpoint and revise the adapter choice; do not mark support complete with an unsupported stub. No beat alignment or sample-accurate timing claim is part of this change.

### 5. Unified executable macros and separate listeners

Generalize the executable target to `PlaybackAction` or `ActivateSkill(skillId)`. Keep three physical buttons and the six tap/hold stroke types; the maximum is five strokes everywhere, including programmatic listeners and overrides. Preserve timed observations all the way from ComboInput to SkillContext. All executable targets use the same longest-match timing and conflict checks.

Listeners subscribe to a completed attributed runtime combo, not an extra candidate in the recognizer trie. A listener pattern matches the whole resolved stroke sequence exactly. Multiple listeners may match one input; they never steal its primary target or lengthen its prefix wait. The actor is the owner of the effective executable binding. The shared on-screen pad cannot identify who physically touched an unbound sequence; unmatched sequences remain unattributed and do not trigger player-scoped listeners. Listening to any player means any resolved P1/P2/P3 combo, including manual activation combos. Recording and practice produce no listener events.

Manual macro configuration lives on a dedicated view linked from skill details. Tiles stay assignment/status controls. Passive-only skills have no macro editor. Saved manual macros remain reserved but dormant when their owner does not hold the skill. Re-equipping reactivates only that owner's macro; reassignment cannot transfer a former owner's input binding implicitly.

### 6. Effective bindings are temporary overlays

Keep persistent base bindings separate from an effect-owned overlay map keyed by profile and playback action. An override replaces one effective sequence without changing target ownership. Validate proposed overrides atomically against saved bindings (including dormant manual reservations) and other active overlays. Reject competing live overrides of the same target; do not add a stack whose restoration order is difficult to explain.

Base edits remain possible under an override, provided the new base passes the same reservation checks. Expiry reveals the latest base value. Publishing a new effective-catalog revision cancels pending input immediately; execution checks the originating revision again. A saved binding cannot be edited into an active override's sequence. Bindings show a compact temporary badge and effective notation; underlying saved sequence, source and expiry stay in on-demand details.

### 7. Compatibility, registration and verification boundary

Extend the profile document to a new version that can atomically persist playback and skill-activation targets in the same uniqueness namespace. Preserve the existing preferences key and migrate older documents with existing names, bindings and timing unchanged; default to no manual macros. Keep skill assignment version/IDs unchanged. Add explicit fixtures for corrupt/duplicate/unknown targets; unknown skills stay dormant with feedback.

The default catalog still contains Skip Recovery. Use developer/test-only definitions to exercise each new capability through real adapters and the recorder/page; do not silently ship invented abilities or a rules editor. Registration tests must prove the policy needs no per-skill branches. Retain and extend the source-boundary test so Flutter/native concerns stay out of `lib/skills/`.

## Risks / Trade-offs

- Native transitions and future-loop edits can race → stable IDs/revisions, bounded preparation window, serialized observation and tests at exact boundaries.
- Temporary overrides can conflict with later saves → reserve base/manual/effective sequences and reject collisions before publishing a revision.
- Cross-player listeners can recurse or execute twice → physical-input-only delivery, listener snapshots, stable ordering and invocation/effect deduplication.
- Audio behavior may vary despite upstream API availability → measured Android feasibility checkpoint and explicit support/failure outcomes; no fake success.
- Effects span external services that cannot transact atomically → per-effect results and declared cleanup, preserving already completed playback facts.
- Expanded profile storage cannot safely be read by every older binary → retain a pre-migration backup, test rollback restoration and never silently erase unknown macros.

## Migration Plan

Implement in verified checkpoints: neutral contract/coordinator, effective bindings and triggers, restrictions/overrides, loop-aware queues, audio feasibility then mixing, integration/UI acceptance. Each checkpoint includes its own tests and code commit while planning remains local. Old assignments and base combos migrate without new effects. New sessions start without transient listeners, overrides, restrictions, mixes or future plans.

Before release, run the full test suite and Android checks for normal playback, macro isolation, cross-player effects, loop boundaries, screen-off mixing, interruption cleanup and process restart. Sync the five delta specs and archive only after all tracked work passes; then commit the final artifacts. Implementation and measured acceptance results are recorded in acceptance.md and audio-feasibility.md.
