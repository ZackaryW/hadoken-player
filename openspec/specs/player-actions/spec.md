# player-actions Specification

## Purpose

Translate recognized player combinations into attributed playback requests with deterministic outcomes and a narrow extension point for predefined player abilities.

## Requirements

### Requirement: Attributed action requests
Each recognized executable combination SHALL produce one request containing a unique request identity, owning profile, binding identity, playback-action or skill-activation target, code-defined effort, recognition time and timed stroke observations. Ownership SHALL be determined from the committed effective binding catalog, never from the currently viewed profile. The request SHALL identify that catalog's revision.

#### Scenario: Different commands for the same action
- **WHEN** P1's Forward tap twice or P2's Forward tap then Backward hold is recognized for next track
- **THEN** each produces a next-track request bearing its respective owner's profile identity

#### Scenario: Effective binding changes before execution
- **WHEN** a request was recognized before its temporary combo override expired and executes after that revision is invalidated
- **THEN** the stale request is denied without executing the old target

### Requirement: Serialized single execution
Profile actions, skill activations, listener reactions and capability mutations SHALL use one ordered session flow. Repeated request or effect identities within the bounded retention window SHALL NOT execute twice. In-flight work SHALL remain protected until completion. A request SHALL observe previously completed effects and due expirations. Listener evaluation SHALL precede primary action eligibility in stable owner, skill and listener order; generated effects SHALL NOT become new physical input.

#### Scenario: Two near-simultaneous requests
- **WHEN** two recognized profile requests arrive before the first finishes
- **THEN** the second is evaluated against playback and ability state after the first completes

#### Scenario: Repeated delivery
- **WHEN** a retained completed request is delivered again
- **THEN** its recorded outcome is returned without another playback change or success event

#### Scenario: Listener restricts the triggering action
- **WHEN** P1's armed listener reacts to P2's combo by restricting P2's requested action at an effort at least as high as that action
- **THEN** the restriction is applied before that primary action is evaluated, which can therefore be denied

### Requirement: Explicit execution outcomes
Every dispatched request SHALL report success, denied, no-op or failure with its profile and action. Success SHALL mean the requested operation took effect; unavailable next/previous tracks SHALL be no-ops. Only successful actions SHALL produce a successful-action notification for ability state updates.

#### Scenario: End of queue
- **WHEN** next track is requested with no next item and no queue wrapping enabled
- **THEN** the outcome is no-op and no successful skip is reported

#### Scenario: Playback failure
- **WHEN** the playback backend rejects the request
- **THEN** failure feedback is shown and no successful-action notification is produced

#### Scenario: Skip into an edited future loop
- **WHEN** an attributed forward skip enters the next repeat-all loop whose occurrences differ from the previous loop
- **THEN** the observed transition is reported as success, including skill-generated skips, while unrelated queue replacement or automatic advance is not credited

### Requirement: Predefined ability extension point
The dispatcher SHALL support observed-combo hooks, pre-execution decisions, manual skill activations, post-success notifications and capability-result callbacks for registered skills. With no ability implementation installed it SHALL allow all otherwise valid playback requests. It SHALL NOT expose user-authored rules or scripts. Automatic effects SHALL retain the originating skill owner separately from the triggering input actor.

#### Scenario: Stage 1 action
- **WHEN** a valid attributed request reaches the Stage 1 dispatcher
- **THEN** the ability check permits it without imposing a cooldown

#### Scenario: Future ability denial
- **WHEN** an installed ability implementation denies a request
- **THEN** playback is not invoked and denial feedback identifies the profile, action and reason

#### Scenario: Manual skill target
- **WHEN** the request targets a skill activation instead of a playback action
- **THEN** it invokes that equipped skill's activation hook without inventing a successful next-track event

### Requirement: Playback adapter behavior
Combo actions SHALL control the existing playback session. Toggle play/pause SHALL use current playback state; seek actions SHALL move ten seconds and clamp to valid track bounds. The input labels SHALL NOT determine the action independently of the saved binding.

#### Scenario: Seek near the beginning
- **WHEN** seek backward ten seconds is requested at three seconds
- **THEN** playback seeks to zero

### Requirement: Unattributed system controls
Existing player transport controls, automatic queue advancement and Android media controls SHALL retain normal playback behavior without inventing a player identity. They SHALL NOT produce profile-success events. Profile abilities SHALL apply to attributed combo requests, not operate as an access-control boundary for all device controls.

#### Scenario: Notification skip
- **WHEN** the user skips using the Android media notification
- **THEN** normal playback changes occur without assigning the action to P1, P2 or P3

### Requirement: Capability results reflect completed effects
Each capability request SHALL be validated before application and receive its own outcome. A multi-effect invocation SHALL report each applied and failed effect, without claiming atomic rollback of irreversible playback changes. Failed or unsupported operations SHALL NOT be reported as successful skill effects. Reversible resources from a failed activation SHALL be cleaned up according to the skill's fixed failure policy.

#### Scenario: Mix fails after a queue edit
- **WHEN** an invocation successfully inserts a queue item and then cannot load a requested mix layer
- **THEN** the result reports the insertion as applied and the mix as failed, and does not pretend the insertion never happened

#### Scenario: Repeat a capability callback
- **WHEN** a result or capability request with a retained already processed identity is delivered again
- **THEN** the original outcome is returned or ignored without applying a second effect or reactivating a listener

### Requirement: Deterministic effort reconciliation
An otherwise valid action SHALL pass only when its effort exceeds every applicable active block. Ties SHALL block at every level, including the extrema. With no applicable block, any effort SHALL be eligible. Reconciliation SHALL compare levels without arithmetic, spending or execution reordering. Effort SHALL NOT bypass binding/ownership validity, capability support or execution failures.

#### Scenario: Stronger manual skip overcomes a global block
- **WHEN** a global next-track block has effort 60 and an equipped manual skill requests an otherwise valid skip at effort 80
- **THEN** the skill-generated skip executes once while an ordinary effort-50 skip remains denied

#### Scenario: Equal or weaker action loses
- **WHEN** skip effort is 60 or 40 and an applicable block is effort 60
- **THEN** the skip is denied without a successful-action event

#### Scenario: Infinite extrema and ties
- **WHEN** an effort-100 skip encounters an effort-99 block, an effort-100 block, or an effort-minus-1 block
- **THEN** it passes the first and third blocks but is denied by the effort-100 block

#### Scenario: Several blockers
- **WHEN** an effort-80 action encounters applicable blocks at 20, 60 and 90
- **THEN** it is denied by the effort-90 block regardless of application order

#### Scenario: Minimum effort without a live block
- **WHEN** an otherwise valid effort-minus-1 action has only expired or irrelevant blocks
- **THEN** it remains eligible, but an applicable live effort-minus-1 block would deny it

### Requirement: Skill-generated playback retains attribution
Skill-requested playback SHALL retain its source skill/owner, added player, invocation and effort. It SHALL use ordinary attributed reconciliation and success reporting without becoming physical input or using the system-transport bypass. Activation and generated playback SHALL be checked separately. Generated success reactions SHALL share a bounded invocation budget and SHALL NOT generate further playback actions in the same chain.

#### Scenario: Activation succeeds but its generated action is blocked
- **WHEN** a skill activation is allowed but its generated skip is tied with an applicable skip block
- **THEN** the activation reports that generated action as denied and does not claim playback success

#### Scenario: Block activation itself
- **WHEN** a manual activation is blocked at equal or higher effort
- **THEN** its runtime is not activated and emits no generated action

### Requirement: Bounded action bookkeeping
Completed request and skill invocation outcomes SHALL retain the latest 256 entries per service; completed effect results SHALL retain the latest 4096 entries. In-flight work SHALL NOT be evicted. Execution-only request state SHALL be released after every terminal outcome. Evicted identities SHALL have no replay guarantee. Live effect cleanup SHALL remain independent of cached outcomes.

#### Scenario: Long-running input
- **WHEN** input exceeds the completed retention limits
- **THEN** completed bookkeeping stays within those limits and recent duplicate delivery returns its saved outcome without reexecution

#### Scenario: Pending and unsuccessful work
- **WHEN** an action is still pending or completes with denial, no-op or failure
- **THEN** pending duplicates share its execution and all terminal paths release execution-only state

#### Scenario: Active effect outlives cached result
- **WHEN** an effect result is evicted while its effect remains active
- **THEN** that effect remains registered and expires or revokes normally
