# Spec Delta

## MODIFIED Requirements

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
- **THEN** the retired assignment is removed with feedback, unknown identities and all profile bindings are preserved, and neither new skill is silently equipped

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

## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Owner-specific skip recovery
**Reason**: The demonstration skill is replaced by song-based commitment and manual force skip.
**Migration**: Retire skip-recovery assignments with feedback; preserve other configuration and require explicit assignment of new skills.

### Requirement: Only successful attributed skips trigger recovery
**Reason**: The demonstration skill is replaced by song-based commitment and manual force skip.
**Migration**: Retire skip-recovery assignments with feedback; preserve other configuration and require explicit assignment of new skills.
