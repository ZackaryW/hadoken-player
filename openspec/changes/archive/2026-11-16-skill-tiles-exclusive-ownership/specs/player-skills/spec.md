## MODIFIED Requirements

### Requirement: Persistent profile assignments
Each added profile SHALL store a set of selected known skill identities, initially empty, subject to exclusive ownership across profiles. Assigning or removing a skill SHALL NOT modify input bindings. Unknown stored skill identities SHALL be inactive with visible feedback. The initial catalog contains only one assignable skill. Unadded profiles SHALL NOT accept skill assignments.

#### Scenario: Assign and restart
- **WHEN** Skip Recovery is assigned to P2 and the app restarts
- **THEN** P2 retains the assignment and its existing combinations

#### Scenario: Unassigned player
- **WHEN** a profile with no assigned skill requests an otherwise valid action
- **THEN** skill evaluation permits the request

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

## ADDED Requirements

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
