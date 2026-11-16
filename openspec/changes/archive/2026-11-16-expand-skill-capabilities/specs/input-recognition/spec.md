## MODIFIED Requirements

### Requirement: Set records one to five strokes
Selecting Set for a profile action or manual skill activation SHALL enter an isolated recording mode that captures one to five sequential strokes using the same tap/hold classification as runtime. The editor SHALL allow undo, clear, cancel and explicit save. No binding becomes active until it passes validation and is saved.

#### Scenario: Record and save
- **WHEN** P2 selects Set for next track, taps Forward, holds Backward and saves
- **THEN** the editor proposes the two-stroke combination for P2 and saves it only if it has no complete-combination conflict

#### Scenario: Recording limits
- **WHEN** the user attempts a sixth stroke or saves an empty recording
- **THEN** the sixth stroke is not appended or the empty save is rejected respectively, with visible feedback

#### Scenario: Review without an automatic save
- **WHEN** recording reaches five strokes or the user pauses input
- **THEN** the draft remains available for explicit review and save without executing its action

#### Scenario: Record a skill activation
- **WHEN** an owner records a manual activation macro
- **THEN** it uses Forward, Pause and Backward tap/hold inputs and the same one-to-five-stroke limit as playback bindings

### Requirement: Recording and practice are non-executing
Recording and practice modes SHALL show observed strokes and recognition feedback without sending playback commands, activating skills, firing listeners or producing successful-action events. Runtime recognition SHALL use the committed effective catalog of saved playback/activation bindings and valid temporary overrides.

#### Scenario: Practice a skip
- **WHEN** a player enters a valid skip combination in practice mode
- **THEN** the owner and next-track action are shown but the current song does not change

#### Scenario: Practice a skill or listener pattern
- **WHEN** input in practice or recording matches an activation macro or armed listener
- **THEN** no skill invocation, effect, listener event or gameplay cooldown is created

## ADDED Requirements

### Requirement: Unified executable macro recognition
Playback and manual skill-activation macros SHALL participate in one longest-completed-match catalog. Shared prefixes SHALL remain valid and an identical complete executable combination SHALL remain exclusive. A match SHALL produce one primary target and immutable timed stroke observations. Listening patterns SHALL NOT add executable candidates or extend a primary combination's wait.

#### Scenario: Skill macro extends a playback prefix
- **WHEN** a playback combo is a prefix of a longer activation macro and the longer macro completes within existing timing rules
- **THEN** only the skill activation is requested

#### Scenario: Listener does not delay playback
- **WHEN** a listening pattern has a longer prefix than an otherwise complete playback combo
- **THEN** the listener alone does not delay or consume that playback match

#### Scenario: Match timing reaches listeners
- **WHEN** a runtime combo completes
- **THEN** the primary request and applicable listeners receive the same ordered tap/hold observations, down/up times and gaps with the resolved input actor

### Requirement: Recognition revision boundaries
Applying, expiring or revoking a temporary binding override SHALL publish a new validated effective catalog revision and cancel in-progress input without firing a fallback. Requests SHALL be revalidated at execution against their originating revision and target. No stale key release or expired binding SHALL trigger an action.

#### Scenario: Override expires during a prefix
- **WHEN** a player has partially entered an overridden combo at its expiration deadline
- **THEN** that attempt is cancelled and only a fresh attempt can use the restored binding

#### Scenario: Listener event was queued before revocation
- **WHEN** a listener's lifetime ends before its queued event is evaluated
- **THEN** the event cannot activate the expired listener
