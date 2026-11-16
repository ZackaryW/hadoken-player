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
After a profile with Skip Recovery successfully performs next track, that profile's next-track requests SHALL be denied for ten seconds measured from completion. At or after the deadline they SHALL become eligible again. This skill SHALL NOT restrict other actions or other profiles, which remain subject to their own assigned skills.

#### Scenario: Original player is restricted
- **WHEN** P2 succeeds at next track at time zero and requests it again at five seconds
- **THEN** the second request is denied without changing playback

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
