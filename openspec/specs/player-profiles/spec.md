# player-profiles Specification

## Purpose

Let up to three players maintain identifiable, persistent input bindings while sharing a single audio player and a globally unambiguous combination catalog.

## Requirements

### Requirement: Up to three explicitly added profiles
The application SHALL start with P1 only. An Add profile control SHALL enable the next available stable profile identity, up to P1, P2 and P3. Added profiles, display names and bindings SHALL persist across restarts. Display-name changes SHALL NOT change identity. Profiles not yet added SHALL NOT accept bindings or participate in recognition. Existing configured profiles SHALL survive migration; unused legacy default slots SHALL remain absent.

#### Scenario: Start with one player
- **WHEN** profile configuration has not been saved
- **THEN** only P1 is shown and Add profile is available

#### Scenario: Add a player
- **WHEN** the user adds a profile and restarts
- **THEN** the new stable identity remains available, and adding beyond three is rejected atomically

#### Scenario: Reopen a configured profile
- **WHEN** the user saves P2's name and bindings and restarts the app
- **THEN** P2 retains its identity, name and saved bindings

#### Scenario: Profile limit
- **WHEN** all three profile slots are configured
- **THEN** the application offers no fourth player profile

### Requirement: Action binding configuration
Each profile SHALL offer a Set control for its bindable actions and allow replacing or clearing a saved combination. The initial bindable actions SHALL be toggle play/pause, next track, previous track, seek forward ten seconds, seek backward ten seconds and stop.

#### Scenario: Replace a binding
- **WHEN** P1 records and saves a valid new combination for next track
- **THEN** the new combination replaces P1's previous next-track binding and the old combination becomes unassigned

#### Scenario: Cancel an edit
- **WHEN** a user cancels recording or leaves an unsaved edit
- **THEN** the previously saved binding remains active

### Requirement: Complete-combination exclusivity
A complete ordered combination of button identities and tap/hold types SHALL belong to at most one profile/action pair across all three profiles. The same complete combination SHALL be rejected even when the conflicting action is different. Shared prefixes SHALL remain valid.

#### Scenario: Cross-profile duplicate
- **WHEN** P1 owns Forward tap for next track and P2 tries to save Forward tap for pause
- **THEN** saving is rejected, P1's binding remains unchanged and the editor identifies P1 and the conflicting action

#### Scenario: Shared prefix is allowed
- **WHEN** P1 owns Forward tap and P2 saves Forward tap followed by Backward hold
- **THEN** both bindings are accepted and an accessible info control beside the combo explains the shorter-combination wait on demand

#### Scenario: Same-profile duplicate
- **WHEN** P1 tries to bind the same complete combination to two different actions
- **THEN** the second binding is rejected

### Requirement: Atomic and valid configuration
Saving a binding SHALL validate against the current complete profile catalog and either persist the whole valid update or preserve the previous state. Invalid stored bindings SHALL remain inactive with visible recovery feedback rather than produce ambiguous playback actions.

#### Scenario: Competing saves
- **WHEN** two edits attempt to claim the same previously unused combination
- **THEN** at most one save succeeds and recognition uses only the committed valid catalog

#### Scenario: Invalid saved data
- **WHEN** a stored combination exceeds five strokes or duplicates another binding
- **THEN** the invalid or conflicting entries are inactive, unaffected valid entries remain available and the user is informed

### Requirement: Ownership follows the combination
Runtime profile attribution SHALL come from the owner of the matched saved combination, independently of which profile is currently displayed for editing.

#### Scenario: Another player's combo from the profile screen
- **WHEN** the runtime pad recognizes P2's combination while P1 was most recently viewed
- **THEN** the requested action belongs to P2

### Requirement: Discoverable Now Playing combo controls
Now Playing SHALL expose an explicit Player / Combo mode switch and direct
access to profile setup. Combo mode SHALL retain the player artwork and visual
style, display three circular tap/hold inputs with ordered combo and owner
feedback, and dispatch only saved bindings. Player mode SHALL retain conventional
transport behavior. Switching mode or leaving the controls SHALL cancel pending
input without executing a deferred prefix.

#### Scenario: Use combos without finding a settings subpage
- **WHEN** the user selects Combo on Now Playing
- **THEN** the three inputs and recognition feedback appear beside the existing player context, and profile setup is directly accessible

#### Scenario: Return to ordinary playback controls
- **WHEN** the user switches from Combo to Player during a pending prefix
- **THEN** the prefix is cancelled and ordinary transport controls appear without sending a profile action

#### Scenario: Small screen layout
- **WHEN** Now Playing uses a 360 by 640 logical-pixel viewport with large text
- **THEN** both modes keep their controls above the navigation bar without clipping or overflow, reducing artwork size as needed

### Requirement: Focused profile configuration
The profile screen SHALL contain only profile selection, adding/renaming profiles and action binding configuration. Global timing and practice SHALL have separate settings destinations. Control surfaces SHALL use concise labels and contextual errors rather than explanatory paragraphs.

#### Scenario: Edit a profile without unrelated settings
- **WHEN** the user opens Profiles
- **THEN** global timing fields, practice controls and instructional paragraphs are absent

#### Scenario: Change shared timing separately
- **WHEN** the user opens Combo timing from Settings
- **THEN** shared hold and continuation values can be edited without showing profile selection or action bindings

### Requirement: Compact binding rows
Each action SHALL group Set and, when bound, Clear on its heading row. Saved combo notation SHALL appear directly below. Shared-prefix timing SHALL be available through a labeled info control beside the combo rather than a persistent explanatory line. Controls and up to five strokes SHALL remain usable at 360 logical pixels wide with text scaling through 2.0.

#### Scenario: Review a shared-prefix binding
- **WHEN** a saved binding shares a prefix with another binding
- **THEN** the action and edit controls are grouped, the combo appears beneath, and the continuation explanation appears only after requesting details

#### Scenario: Clear a bound action
- **WHEN** the user selects Clear beside Set
- **THEN** the saved binding is removed and the combo and its info control disappear while Set remains available
