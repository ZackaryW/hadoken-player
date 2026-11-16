# input-recognition Specification

## Purpose

Capture three on-screen buttons as timed tap/hold strokes, record and display player combinations, and recognize one unambiguous action from a shared input stream.

## Requirements

### Requirement: Three buttons and six stroke types
The on-screen input pad SHALL expose Forward, Pause and Backward. Each press/release pair SHALL produce exactly one short-press or long-hold stroke. These button names SHALL identify inputs, not directly execute their conventional playback actions.

#### Scenario: Long hold is one stroke
- **WHEN** Forward remains pressed for at least the hold threshold and is released
- **THEN** exactly one Forward hold stroke is produced and no Forward tap or repeated strokes are produced

#### Scenario: Short press
- **WHEN** Pause is released before the hold threshold
- **THEN** one Pause tap stroke is produced without inherently pausing playback

### Requirement: Shared recognition timing
The application SHALL use shared configurable hold and inter-stroke thresholds across all profiles, initially 600 ms and 500 ms respectively. Durations SHALL use elapsed time. Key-down, key-up and gap measurements SHALL be retained during recognition; recorded timing differences SHALL NOT create separate ownership for an otherwise identical combination.

#### Scenario: Threshold boundary
- **WHEN** a press lasts exactly the configured hold threshold
- **THEN** it is recognized as a hold

#### Scenario: Clock adjustment
- **WHEN** the device wall clock changes during a sequence
- **THEN** tap/hold and gap recognition remain based on elapsed durations

#### Scenario: Timing settings change
- **WHEN** valid positive timing thresholds are saved
- **THEN** the new thresholds apply to all subsequent input attempts and any in-progress attempt is cleared

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

### Requirement: Fighting-game combination display
Saved and recorded combinations SHALL appear in order as readable button symbols with distinct short-press and hold markers, resembling fighting-game move notation. Each combination SHALL also have an accessible text description; color alone SHALL NOT encode hold versus tap.

#### Scenario: Read a mixed combination
- **WHEN** the displayed binding is Forward tap followed by Backward hold
- **THEN** the UI shows both ordered button symbols, a clear hold marker on Backward and an equivalent text description

### Requirement: Longest completed combination
Recognition SHALL allow shared prefixes and choose the longest completed matching combination in the current attempt. A completed prefix with longer candidates SHALL wait for continuation. A next button-down before the gap deadline suspends that deadline until release, allowing a hold to complete. At the deadline or a mismatch, any pending completed match fires once and the attempt is cleared.

#### Scenario: Longer player's combination wins
- **WHEN** P1 owns Forward tap, P2 owns Forward tap then Backward hold, and the user starts Backward before the gap expires and releases it as a hold
- **THEN** only P2's action is requested, even if the hold itself lasts longer than the gap threshold

#### Scenario: Shorter combination after timeout
- **WHEN** Forward tap is a complete match and no next button-down occurs before its continuation deadline
- **THEN** its owner's action is requested once

#### Scenario: Exact gap deadline
- **WHEN** a new button-down arrives at or after the continuation deadline
- **THEN** the expired attempt resolves first and the new press starts a separate attempt

#### Scenario: Mismatching continuation
- **WHEN** a completed prefix is pending and a completed continuation stroke matches no longer candidate
- **THEN** the pending match fires once, the mismatching stroke is discarded and the attempt is cleared

#### Scenario: No completed match
- **WHEN** an attempt times out or mismatches without any completed binding
- **THEN** no playback action is requested and the attempt is cleared

### Requirement: Safe cancellation and sequential input
Recognition SHALL accept sequential single-button strokes only. Overlapping presses, pointer cancellation, app focus loss and binding changes SHALL clear pending input without firing a fallback action. A cancelled or stale release SHALL NOT create a stroke.

#### Scenario: App leaves the foreground
- **WHEN** the app loses focus during a pending combination
- **THEN** the combination is discarded while existing background playback continues

#### Scenario: Two buttons held together
- **WHEN** a second button is pressed before the first is released
- **THEN** the attempt is cancelled and feedback explains that combinations are sequential

### Requirement: Recording and practice are non-executing
Recording and practice modes SHALL show observed strokes and recognition feedback without sending playback commands, activating skills, firing listeners or producing successful-action events. Runtime recognition SHALL use the committed effective catalog of saved playback/activation bindings and valid temporary overrides.

#### Scenario: Practice a skip
- **WHEN** a player enters a valid skip combination in practice mode
- **THEN** the owner and next-track action are shown but the current song does not change

#### Scenario: Practice a skill or listener pattern
- **WHEN** input in practice or recording matches an activation macro or armed listener
- **THEN** no skill invocation, effect, listener event or gameplay cooldown is created

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
