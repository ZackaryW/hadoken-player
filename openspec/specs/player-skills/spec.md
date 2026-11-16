# player-skills Specification

## Purpose

Give player profiles assignable, predefined abilities that affect their attributed playback actions without exposing a general-purpose rule customization engine.

## Requirements

### Requirement: Code-defined skill catalog
The application SHALL offer a fixed catalog of skills with stable identities, names and behavior descriptions. Users SHALL select supported skills rather than author conditions, scripts or numerical behavior parameters. The initial catalog SHALL contain Skip Recovery, with a fixed ten-second restriction after a successful next-track action.

#### Scenario: Inspect a skill
- **WHEN** the user opens the profile skill selector
- **THEN** Skip Recovery describes who is restricted, which action triggers it and the ten-second duration, with no rule or duration editor

### Requirement: Persistent profile assignments
Each added profile SHALL store a set of selected known skill identities, initially empty, subject to exclusive ownership across profiles. Assigning or removing a skill SHALL NOT modify input bindings. Unknown stored skill identities SHALL be inactive with visible feedback. The initial catalog contains only one assignable skill. Unadded profiles SHALL NOT accept skill assignments.

#### Scenario: Assign and restart
- **WHEN** Skip Recovery is assigned to P2 and the app restarts
- **THEN** P2 retains the assignment and its existing combinations

#### Scenario: Unassigned player
- **WHEN** a profile with no assigned skill requests an otherwise valid action
- **THEN** skill evaluation permits the request

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

### Requirement: Only successful attributed skips trigger recovery
Denied, failed, duplicate and no-op requests SHALL NOT start or extend recovery. Recording, practice, automatic advancement and unattributed system controls SHALL NOT activate a profile's skill. Another profile's successful skip SHALL NOT restart an existing cooldown.

#### Scenario: End-of-queue attempt
- **WHEN** P2's next-track request produces no-op because no following track exists
- **THEN** P2 does not enter cooldown

#### Scenario: Another player's action
- **WHEN** P2's cooldown expires at ten seconds and P1 skips at three seconds
- **THEN** P2's deadline remains ten seconds

#### Scenario: Duplicate delivery
- **WHEN** the success of the same request is delivered again
- **THEN** no additional cooldown is created and the existing deadline does not move

### Requirement: Atomic skill evaluation
Skill eligibility, playback execution and successful-action state updates SHALL participate in the same ordered action-processing flow. A following request SHALL observe the previous request's completed skill effects.

#### Scenario: Rapid requests from the owner
- **WHEN** two next-track requests from P2 arrive before the first playback operation completes
- **THEN** after the first succeeds the second is denied by the new cooldown

### Requirement: Stable cooldown identity and assignment changes
Cooldown state SHALL attach to stable profile identity rather than display name or binding. Editing a binding or navigating screens SHALL NOT clear it. Skill-assignment changes for a profile SHALL be rejected while that profile has an active cooldown, with remaining-time feedback.

#### Scenario: Change the triggering combo
- **WHEN** P2 changes its next-track binding during cooldown and uses the new combination
- **THEN** its next-track action remains restricted until the same deadline

#### Scenario: Remove the skill mid-cooldown
- **WHEN** P2 attempts to remove Skip Recovery before its deadline
- **THEN** the assignment remains unchanged and the UI shows when it can be edited

### Requirement: Session timing and recovery
Cooldowns SHALL use elapsed time and survive app backgrounding while the playback process remains alive. They SHALL be transient to that process session; a new process starts with no active cooldowns while retaining assignments. Returning to the foreground SHALL recompute remaining time without replaying expired actions.

#### Scenario: Background during cooldown
- **WHEN** the app backgrounds for twelve seconds after a successful skip and the same process resumes
- **THEN** the profile is eligible again without an extra skip occurring

#### Scenario: New process
- **WHEN** the app starts in a new process
- **THEN** saved assignments remain and cooldown state is empty

### Requirement: Visible action feedback
A denied profile action SHALL identify the profile, relevant skill and remaining cooldown time. Allowed or expired state SHALL be distinguishable from an active cooldown using text as well as visual styling.

#### Scenario: Denial feedback
- **WHEN** P2 tries to skip with four seconds remaining
- **THEN** feedback identifies P2 and Skip Recovery and shows the remaining time without presenting the request as a playback failure

### Requirement: Focused skill configuration
Assignment controls SHALL live on a separate Player skills screen as a responsive grid of square icon-and-label tiles. Assigned tiles SHALL light up; inactive tiles SHALL appear gray. Text and accessibility state SHALL distinguish assignment and cooldown state. Descriptions SHALL remain on demand. The binding screen SHALL remain focused on inputs.

#### Scenario: Configure a skill
- **WHEN** the user opens Player skills from Settings
- **THEN** only existing profiles, skill assignments and readiness status are shown, without binding or timing editors

#### Scenario: Toggle a tile
- **WHEN** the selected player taps an available inactive skill tile, then taps it again while no cooldown is active
- **THEN** the first tap assigns and illuminates the tile and the second removes the assignment and grays it out

#### Scenario: View another owner's skill
- **WHEN** P1 views a skill assigned to P2
- **THEN** its tile is gray, identifies P2 as owner and does not offer assignment to P1

#### Scenario: Large text
- **WHEN** the screen is 360 by 640 logical pixels with text scaling up to 2.0
- **THEN** tiles reflow with readable labels and reachable controls without overflow

### Requirement: Exclusive skill ownership
Each known skill SHALL have at most one owner across added profiles. Attempts to assign another player's skill SHALL be rejected without modifying saved assignments. Removal and reassignment SHALL be explicit and remain subject to the existing cooldown edit restriction. This SHALL NOT impose a one-skill-per-player limit.

#### Scenario: Competing assignments
- **WHEN** P1 and P2 request the same unowned skill concurrently
- **THEN** only the first successful assignment takes ownership and the other receives owner feedback

#### Scenario: Release and reassign
- **WHEN** P2 removes its skill after recovery and P1 assigns it
- **THEN** P1 becomes its sole owner and remains so after restart

#### Scenario: Legacy duplicates
- **WHEN** saved data assigns a known skill to multiple profiles
- **THEN** only the first added owner in P1, P2, P3 order remains assigned, recovery feedback is visible, and unrelated unknown skill identities are preserved

### Requirement: Independent skill source modules
Skill implementations SHALL live in a dedicated `lib/skills/` source folder, with a separate module per skill owning its metadata, fixed parameters, behavior and session state. They SHALL depend only on Dart and contracts within that folder. The application SHALL integrate registered skills through a shared contract; skill effects SHALL NOT be hardcoded in the shared policy or UI.

#### Scenario: Exercise a skill independently
- **WHEN** a developer supplies action events and elapsed timestamps to a skill runtime
- **THEN** eligibility, successful-action effects and cooldown state can be tested without Flutter, profile storage or playback services

#### Scenario: Register a skill implementation
- **WHEN** a supported skill definition is registered
- **THEN** the application policy routes assigned actions through its runtime and the selector renders its metadata without skill-specific policy branches

#### Scenario: Preserve existing behavior
- **WHEN** an existing installation loads Skip Recovery through the new module
- **THEN** its stored identity, exclusive owner, ten-second recovery, success-only activation and tile states remain unchanged

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
