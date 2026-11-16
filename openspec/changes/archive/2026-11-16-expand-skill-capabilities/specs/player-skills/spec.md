## MODIFIED Requirements

### Requirement: Owner-specific skip recovery
After a profile with Skip Recovery successfully performs next track, that profile's next-track requests at ordinary default effort SHALL be denied for ten seconds measured from completion. Its code-defined block SHALL participate in shared effort reconciliation; a strictly stronger attributed action may overcome it. At or after the deadline the block SHALL no longer apply. This skill SHALL NOT restrict other actions or other profiles, which remain subject to their own assigned skills.

#### Scenario: Original player is restricted
- **WHEN** P2 succeeds at next track at time zero and requests it again at five seconds
- **THEN** the second ordinary-effort request is denied without changing playback

#### Scenario: Other player can skip
- **WHEN** P2 is cooling down and P1 requests next track without an active restriction of its own
- **THEN** P1's request is eligible

#### Scenario: Deadline equality
- **WHEN** P2 requests next track exactly ten seconds after its successful skip
- **THEN** Skip Recovery permits the request

#### Scenario: Other action during recovery
- **WHEN** P2 requests pause during its skip cooldown
- **THEN** Skip Recovery does not deny pause

## ADDED Requirements

### Requirement: Typed skill capabilities
Independent skill modules SHALL request queue edits, audio mixes, action restrictions, temporary combo overrides, macro listeners and attributed playback actions through typed contracts. Requests SHALL identify their originating skill, owner and invocation. Application services SHALL execute them and return explicit applied, denied, no-op, unsupported or failed results. Skills SHALL NOT import application or platform services.

#### Scenario: Execute each supported capability
- **WHEN** a registered test skill requests each capability with valid targets and parameters
- **THEN** the real application adapters perform the requested operations and return attributable results, rather than acknowledge an unimplemented stub

#### Scenario: Unsupported request
- **WHEN** a requested audio operation is unavailable on the running backend
- **THEN** the result is unsupported with no claimed successful effect and existing playback remains usable

### Requirement: Skill event and activation contracts
Definitions SHALL declare passive hooks, manual activation support and required capabilities. Runtime events SHALL support observed combos, action decisions, successful actions, capability results and effect expiration. A manual activation SHALL identify its owner and skill and SHALL require that skill to be equipped and eligible. Existing Skip Recovery SHALL retain its success-only ten-second behavior.

#### Scenario: Activate an equipped skill
- **WHEN** an eligible owner's saved activation macro completes
- **THEN** the skill receives one manual activation event with the resolved owner and timed stroke observations

#### Scenario: Activation after removal
- **WHEN** a queued activation reaches execution after its skill was removed or reassigned
- **THEN** it is denied and cannot activate the former owner's runtime

#### Scenario: Passive recovery remains unchanged
- **WHEN** Skip Recovery observes failed, denied, duplicate or no-op next-track requests
- **THEN** no cooldown starts or extends

### Requirement: Targeted action restrictions
Skills SHALL support bounded action restrictions targeting explicit profiles, the owner, others or all added players. Each restriction SHALL block actions at equal or lower effort. Overlapping restrictions SHALL expire independently. Denial feedback SHALL identify the source and remaining time. Unattributed device transport SHALL remain unaffected.

#### Scenario: Block other players
- **WHEN** P1 applies a next-track restriction to other players at the default effort and they use ordinary default-effort actions
- **THEN** P2 and P3 next-track requests are denied while P1 and unrelated actions remain eligible

#### Scenario: Block all players
- **WHEN** a skill restricts next track for all added players at the default effort and they use ordinary default-effort actions
- **THEN** its owner is restricted as well, while notification transport retains ordinary playback behavior

#### Scenario: Overlapping restrictions expire
- **WHEN** two restrictions can block P2's action at its effort and only the first reaches its deadline
- **THEN** the second remains effective and feedback identifies a remaining cause

### Requirement: Effect ownership and cleanup
Temporary effects and listeners SHALL have stable handles, source ownership, bounded lifetimes and explicit revocation. Expiration SHALL use elapsed time including background time. Removing a skill SHALL NOT bypass an active effect; assignment edits SHALL remain locked while that owner has live effects. A new process SHALL discard transient effects while retaining saved assignments and macros.

#### Scenario: Background expiration
- **WHEN** an effect expires while the app is backgrounded
- **THEN** it is no longer effective at the next evaluation and cleanup occurs without replaying its triggering action

#### Scenario: Unequip during an effect
- **WHEN** an owner tries to remove a skill while its restriction, mix, listener or combo override remains active
- **THEN** removal is rejected with the remaining effect status

#### Scenario: Stop the session
- **WHEN** the playback/game session is explicitly stopped or replaced
- **THEN** session effects and listeners are revoked, audio layers are released and temporary bindings are removed without deleting saved configuration

### Requirement: Cross-player listening macros
An equipped skill SHALL be able to arm and revoke a listener for a one-to-five-stroke pattern and an owner, others, all or explicit-profile scope. Listeners SHALL observe completed attributed runtime combos, including combos owned by other players, without claiming exclusive execution ownership. Listeners SHALL receive stroke timing and the triggering profile and SHALL NOT execute in recording or practice.

#### Scenario: React to another player's input
- **WHEN** P1's skill listens for P2's matching combo and P2 completes it
- **THEN** the skill receives one event identifying P1 as skill owner and P2 as input actor

#### Scenario: Observe without stealing
- **WHEN** multiple skills listen to P2's playback combo
- **THEN** each applicable listener is evaluated once in deterministic order and the combo retains one primary executable target

#### Scenario: Unattributed input
- **WHEN** a sequence has no executable binding that identifies a player
- **THEN** no player identity is invented from the currently selected profile and no player-scoped listener fires

#### Scenario: Prevent reaction recursion
- **WHEN** a listener produces an effect or a synthetic command
- **THEN** that output is not reintroduced as physical combo input or recursively delivered to listeners

### Requirement: Code-defined effort declarations
Skill code SHALL declare effort for its manual activation, generated actions and blocking decisions/effects. Ordinary profile actions and unspecified declarations SHALL use a default effort of 50. The value SHALL be an integer from -1 through 100: -1 denotes infinite minimum, 0–99 normal levels and 100 infinite maximum. Effort SHALL NOT be editable through player configuration.

#### Scenario: Reject an invalid declaration
- **WHEN** skill code supplies an effort outside -1 through 100
- **THEN** construction or validation fails before any effect executes

#### Scenario: Keep player setup focused
- **WHEN** a player configures a combo or assigns a skill
- **THEN** no effort editor is shown and configured input cannot raise the code-owned action effort
