# player-skills Specification

## Purpose

Give player profiles assignable, predefined abilities that affect their attributed playback actions without exposing a general-purpose rule customization engine.

## Requirements

### Requirement: Code-defined skill catalog
The application SHALL offer a fixed catalog of skills with stable identities, names and behavior descriptions. Users SHALL select supported skills rather than author conditions, scripts or numerical behavior parameters. The production catalog SHALL contain Song Commitment and Force Skip; Skip Recovery SHALL no longer be available.

#### Scenario: Inspect a skill
- **WHEN** the user opens the skill selector
- **THEN** Song Commitment and Force Skip are offered with concise on-demand descriptions and no rule or effort editor

### Requirement: Persistent profile assignments
Each added profile SHALL store a set of selected known skill identities, initially empty, subject to exclusive ownership across profiles. Assigning or removing a skill SHALL NOT modify input bindings. Unknown stored skill identities SHALL be inactive with visible feedback. Unadded profiles SHALL NOT accept skill assignments.

#### Scenario: Assign and restart
- **WHEN** Song Commitment is assigned to P2 and the app restarts
- **THEN** P2 retains the assignment and its existing combinations

#### Scenario: Unassigned player
- **WHEN** a profile requests an otherwise valid action with no applicable equipped skill restriction
- **THEN** skill evaluation permits the request

#### Scenario: Retire the demonstration assignment
- **WHEN** saved data contains skip-recovery and unrelated unknown identities
- **THEN** the retired assignment is removed silently without a migration notice, unknown identities and all profile bindings are preserved, and neither new skill is silently equipped

### Requirement: Atomic skill evaluation
Skill eligibility, playback execution and successful-action state updates SHALL participate in the same ordered action-processing flow. A following request SHALL observe the previous request's completed skill effects.

#### Scenario: Rapid requests from the owner
- **WHEN** Force Skip and an ordinary next-track request arrive together during a song lock
- **THEN** they execute in order, each sees the current playback occurrence and no action is replayed

### Requirement: Stable cooldown identity and assignment changes
Skill state SHALL attach to stable skill, owner and playback-session identity rather than display name or binding. Editing a binding or navigating screens SHALL NOT clear an active block. Assignment edits SHALL be rejected while the owner has a live effect or a skill-declared assignment lock, using truthful status feedback rather than a fabricated countdown.

#### Scenario: Change the triggering combo
- **WHEN** a player changes its next-track binding during Song Commitment
- **THEN** its new combination remains restricted for the current song

#### Scenario: Remove the skill mid-cooldown
- **WHEN** the owner tries to remove Song Commitment after it locks a song
- **THEN** the assignment remains unchanged and feedback says the current song must finish

### Requirement: Session timing and recovery
Transient skill state SHALL survive backgrounding while the playback process remains alive. Listening time SHALL count only actual playing intervals, excluding pause and buffering, independently of seek position or playback speed. Session replacement, stop or a new process SHALL reset transient state while preserving assignments and macros.

#### Scenario: Background during cooldown
- **WHEN** a song continues playing in the background across twenty seconds of actual listening
- **THEN** the next evaluation sees Song Commitment locked even if UI timers were suspended

#### Scenario: New process
- **WHEN** the app starts in a new process
- **THEN** saved assignments remain and transient state starts empty

### Requirement: Visible action feedback
A denied profile action SHALL identify the profile and relevant skill with its blocking effort and release condition or remaining duration. Text SHALL distinguish ready, listening and locked states. Song-bound restrictions SHALL NOT pretend to have a fixed elapsed-time expiration.

#### Scenario: Denial feedback
- **WHEN** P2 tries to skip a committed song
- **THEN** feedback identifies P2, Song Commitment (90) and the requirement to finish the song without presenting it as a playback failure

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
- **WHEN** the catalog registers Song Commitment and Force Skip
- **THEN** their listeners, parameters and state remain in independent skill modules and shared policy has no skill-specific behavior branches

### Requirement: Typed skill capabilities
Independent skill modules SHALL request queue edits, audio mixes, action restrictions, temporary combo overrides, macro listeners and attributed playback actions through typed contracts. Requests SHALL identify their originating skill, owner and invocation. Application services SHALL execute them and return explicit applied, denied, no-op, unsupported or failed results. Skills SHALL NOT import application or platform services.

#### Scenario: Execute each supported capability
- **WHEN** a registered test skill requests each capability with valid targets and parameters
- **THEN** the real application adapters perform the requested operations and return attributable results, rather than acknowledge an unimplemented stub

#### Scenario: Unsupported request
- **WHEN** a requested audio operation is unavailable on the running backend
- **THEN** the result is unsupported with no claimed successful effect and existing playback remains usable

### Requirement: Skill event and activation contracts
Definitions SHALL declare passive hooks, manual activation support and required capabilities. Runtime events SHALL support observed combos, action decisions, successful actions, capability results, effect expiration, equipment lifecycle and playback observations. A manual activation SHALL identify its owner and skill and SHALL require that skill to be equipped and eligible.

#### Scenario: Activate an equipped skill
- **WHEN** an eligible owner's saved activation macro completes
- **THEN** the skill receives one manual activation event with the resolved owner and timed stroke observations

#### Scenario: Activation after removal
- **WHEN** a queued activation reaches execution after its skill was removed or reassigned
- **THEN** it is denied and cannot activate the former owner's runtime

#### Scenario: Passive recovery remains unchanged
- **WHEN** Force Skip produces a denied, failed or no-op playback result
- **THEN** no successful track transition is reported and the current song lock is retained

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

### Requirement: Visible skill action effort
On-demand skill details SHALL display the code-defined effort beside each mentioned action or restriction. Manual-capable skills SHALL also show their activation effort. Numbers SHALL reflect the corresponding runtime declarations and SHALL remain read-only. Details SHALL remain concise and usable with large text without crowding assignment tiles.

#### Scenario: Inspect recovery effort
- **WHEN** a player opens the production skill details
- **THEN** each protected action shows effort 90, Force Skip shows effort 100, and the listening duration remains distinct

#### Scenario: Inspect activation effort
- **WHEN** a manual-capable skill declares activation effort 80
- **THEN** its details show Activate (80) without offering an effort editor

#### Scenario: Large text details
- **WHEN** skill details are displayed at 360 by 640 logical pixels with text scaling 2.0
- **THEN** action labels and numbers remain readable and the dialog actions remain reachable without overflow

### Requirement: Declared listeners and typed session state
A skill SHALL declare named event listeners with event type, player scope and initial activation. Its runtime SHALL enable or disable declared listeners and own typed transient state. Undeclared listener activation SHALL be rejected. State and activation SHALL be isolated by skill, owner and session and reset on reassignment or session replacement.

#### Scenario: Selective subscription
- **WHEN** a skill disables one declared listener and enables another
- **THEN** only matching active listeners receive subsequent events and unrelated skills are unaffected

#### Scenario: Fresh ownership
- **WHEN** an unequipped skill is assigned to another player
- **THEN** its typed state is fresh and listeners use their declared initial activation

### Requirement: Playback observation identity
Skills SHALL receive playback observations with a stable current play identity and accumulated actual listening time. Natural completion, repeat-one restart, adjacent duplicate songs and a new playback session SHALL establish fresh play identities. Seeking or a queue edit preserving the playing occurrence SHALL NOT reset accumulated listening time.

#### Scenario: Pause and seek
- **WHEN** a player hears ten seconds, pauses for thirty seconds and seeks forward
- **THEN** accumulated listening remains ten seconds until actual playback resumes

#### Scenario: Repeat and duplicate songs
- **WHEN** the same song repeats naturally or playback advances to an adjacent occurrence of the same song
- **THEN** its listening counter and song-bound lock start fresh

### Requirement: Global song commitment
An equipped Song Commitment SHALL lock the current song once actual listening reaches twenty seconds. It SHALL block all attributed players' next-track, previous-track, seek-forward and seek-backward actions at effort 90 until the play ends or changes. Pause and stop SHALL remain available. Equipping during a play SHALL observe its existing accumulated listening time.

#### Scenario: Exact threshold and all players
- **WHEN** actual listening reaches exactly twenty seconds with Song Commitment equipped
- **THEN** all four protected actions at effort 90 or below are denied for P1, P2 and P3, including the skill owner

#### Scenario: Stronger action
- **WHEN** a valid next-track action at effort 100 changes the song
- **THEN** it overcomes the block and the next song begins unlocked

#### Scenario: No wall-clock expiry
- **WHEN** a committed song is paused for longer than its remaining audio duration
- **THEN** the block persists until the play ends or changes

### Requirement: Manual force skip
An equipped Force Skip SHALL use its owner's saved one-to-five-stroke macro to request next track at effort 100, with activation effort 100. It SHALL use ordinary effort reconciliation and playback validation. Duplicate delivery SHALL execute at most once; failures and end-of-queue no-ops SHALL not be reported as a successful skip.

#### Scenario: Override commitment
- **WHEN** the owner completes Force Skip's macro during Song Commitment
- **THEN** one next-track request at effort 100 overcomes the effort-90 block

#### Scenario: Strongest tie
- **WHEN** another valid restriction blocks next track at effort 100
- **THEN** Force Skip is denied because ties block

#### Scenario: Inactive macro
- **WHEN** the skill is removed or belongs to another player
- **THEN** the former owner's macro cannot activate it
