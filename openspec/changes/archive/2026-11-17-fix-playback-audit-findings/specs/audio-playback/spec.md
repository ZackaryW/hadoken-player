# Spec Delta

## ADDED Requirements

### Requirement: Interruption-owned resumption
Automatic resumption SHALL occur only when a qualifying interruption successfully paused active playback, configured resumption permits it, and no subsequent transport intent or route loss cancels that intent. Previously paused or stopped playback SHALL remain inactive. Duplicate or unmatched interruption endings SHALL NOT start playback.

#### Scenario: Paused before interruption
- **WHEN** a pause interruption begins and ends while music was already paused
- **THEN** it remains paused with the queue preserved

#### Scenario: Resume interrupted playback
- **WHEN** an interruption successfully pauses playing music and ends with resumption enabled and no cancellation
- **THEN** the existing session resumes once, including its mix layers

#### Scenario: Explicit cancellation
- **WHEN** a user pauses or stops, or headphones disconnect, after interruption-induced pause
- **THEN** ending the interruption does not resume audio

#### Scenario: Failed pause or disabled resumption
- **WHEN** interruption pause fails or resumption is disabled
- **THEN** its ending does not issue a resume command

#### Scenario: Rapid begin and end
- **WHEN** interruption end arrives before its asynchronous pause finishes
- **THEN** handling preserves event order and resumes only after a successful uncancelled pause
