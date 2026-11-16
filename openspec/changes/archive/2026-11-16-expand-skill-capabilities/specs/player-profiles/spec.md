## MODIFIED Requirements

### Requirement: Complete-combination exclusivity
A complete ordered combination of button identities and tap/hold types SHALL belong to at most one profile/executable-target pair across all three profiles, including playback actions and manual skill activations. Identical complete combinations SHALL be rejected across saved bindings and effective temporary overrides even for different targets. Shared prefixes SHALL remain valid. Listening patterns SHALL not claim executable ownership.

#### Scenario: Cross-profile duplicate
- **WHEN** P1 owns Forward tap for next track and P2 tries to save Forward tap for pause
- **THEN** saving is rejected, P1's binding remains unchanged and the editor identifies P1 and the conflicting action

#### Scenario: Shared prefix is allowed
- **WHEN** P1 owns Forward tap and P2 saves Forward tap followed by Backward hold
- **THEN** both bindings are accepted and an accessible info control beside the combo explains the shorter-combination wait on demand

#### Scenario: Same-profile duplicate
- **WHEN** P1 tries to bind the same complete combination to two different actions
- **THEN** the second binding is rejected

#### Scenario: Manual activation conflicts with playback
- **WHEN** a skill activation is assigned a combo already saved for another executable target
- **THEN** the save is rejected and identifies the existing owner and target

### Requirement: Ownership follows the combination
Runtime profile attribution SHALL come from the owner of the matched committed effective combination, independently of which profile is currently displayed for editing. Temporary overrides SHALL change the sequence but retain the target profile and action identity. Listener ownership SHALL remain separate from the actor whose input matched.

#### Scenario: Another player's combo from the profile screen
- **WHEN** the runtime pad recognizes P2's combination while P1 was most recently viewed
- **THEN** the requested action belongs to P2

#### Scenario: Override another player's action
- **WHEN** P1's skill temporarily changes P2's next-track combo and the replacement combo is entered
- **THEN** the resulting next-track request belongs to P2, not P1

### Requirement: Discoverable Now Playing combo controls
Now Playing SHALL expose an explicit Player / Combo mode switch and direct
access to profile setup. Combo mode SHALL retain the player artwork and visual
style, display three circular tap/hold inputs with ordered combo and owner
feedback, and dispatch only committed effective bindings. Player mode SHALL retain conventional
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

## ADDED Requirements

### Requirement: Persistent manual skill macros
Manual-capable equipped skills SHALL offer a dedicated macro configuration view with Set, Clear and ordered tap/hold notation. Macro bindings SHALL persist by profile and stable skill identity. Unequipped macros SHALL remain dormant and reserve their saved combinations until cleared. Passive-only skills SHALL not require a manual macro. Assignment tiles SHALL remain focused on assignment and status.

#### Scenario: Save and restart
- **WHEN** P2 saves a manual skill macro and restarts
- **THEN** the same macro is available when P2 owns that skill, without changing playback bindings

#### Scenario: Reassign a skill
- **WHEN** a skill moves from P1 to P2
- **THEN** P1's saved macro stays dormant and only P2's configured macro can activate the skill

#### Scenario: Configure without crowded tiles
- **WHEN** a user opens macro controls from a manual-capable skill's details
- **THEN** a focused macro editor appears without adding timing controls or explanatory paragraphs to the skill grid

### Requirement: Temporary combo overrides
Skills SHALL be able to replace selected playback-action combos for other added profiles for a bounded lifetime. Overrides SHALL retain saved bindings underneath, pass global uniqueness validation and identify their source and expiry. A second live override for the same profile/action SHALL be rejected. Expiry or revocation SHALL restore the latest valid saved binding without overwriting intervening user edits.

#### Scenario: Apply and expire
- **WHEN** a skill replaces P2's next-track combo for ten seconds
- **THEN** only the replacement executes during that interval and the saved combo resumes at expiry

#### Scenario: Conflicting replacement
- **WHEN** an override would duplicate another saved or effective executable combo
- **THEN** the entire override request is rejected and both profiles retain their prior behavior

#### Scenario: User edits under an override
- **WHEN** P2 saves a new valid base combo while its action is temporarily overridden
- **THEN** the temporary combo remains effective and expiry restores the new saved combo

#### Scenario: Competing overrides
- **WHEN** another skill tries to override a profile/action that already has a live override
- **THEN** it receives a conflict result without replacing or extending the first effect

#### Scenario: Inspect an overridden action
- **WHEN** a player views an affected binding
- **THEN** the effective combo and a concise temporary-status indicator are visible, with saved combo/source/expiry details available on demand
