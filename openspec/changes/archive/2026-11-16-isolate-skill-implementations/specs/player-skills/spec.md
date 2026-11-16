## ADDED Requirements

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
