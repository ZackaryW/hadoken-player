# Spec Delta

## MODIFIED Requirements

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

### Requirement: Capability results reflect completed effects
Each capability request SHALL be validated before application and receive its own outcome. A multi-effect invocation SHALL report each applied and failed effect, without claiming atomic rollback of irreversible playback changes. Failed or unsupported operations SHALL NOT be reported as successful skill effects. Reversible resources from a failed activation SHALL be cleaned up according to the skill's fixed failure policy.

#### Scenario: Mix fails after a queue edit
- **WHEN** an invocation successfully inserts a queue item and then cannot load a requested mix layer
- **THEN** the result reports the insertion as applied and the mix as failed, and does not pretend the insertion never happened

#### Scenario: Repeat a capability callback
- **WHEN** a result or capability request with a retained already processed identity is delivered again
- **THEN** the original outcome is returned or ignored without applying a second effect or reactivating a listener

## ADDED Requirements

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
