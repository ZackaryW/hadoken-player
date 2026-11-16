# Spec Delta

## Purpose

Translate recognized player combinations into attributed playback requests with deterministic outcomes and a narrow extension point for predefined player abilities.

## ADDED Requirements

### Requirement: Attributed action requests
Each recognized saved combination SHALL produce one request containing a unique request identity, owning profile, binding identity, requested action and recognition time. Ownership SHALL be determined from the committed binding catalog, never from the currently viewed profile.

#### Scenario: Different commands for the same action
- **WHEN** P1's Forward tap twice or P2's Forward tap then Backward hold is recognized for next track
- **THEN** each produces a next-track request bearing its respective owner's profile identity

### Requirement: Serialized single execution
Profile action requests SHALL be evaluated and executed in arrival order through one shared dispatcher. Repeated delivery of the same request identity within the current session SHALL NOT execute or report a successful action twice.

#### Scenario: Two near-simultaneous requests
- **WHEN** two recognized profile requests arrive before the first finishes
- **THEN** the second is evaluated against playback and ability state after the first completes

#### Scenario: Repeated delivery
- **WHEN** a previously completed request is delivered again
- **THEN** its recorded outcome is returned without another playback change or success event

### Requirement: Explicit execution outcomes
Every dispatched request SHALL report success, denied, no-op or failure with its profile and action. Success SHALL mean the requested operation took effect; unavailable next/previous tracks SHALL be no-ops. Only successful actions SHALL produce a successful-action notification for ability state updates.

#### Scenario: End of queue
- **WHEN** next track is requested with no next item and no queue wrapping enabled
- **THEN** the outcome is no-op and no successful skip is reported

#### Scenario: Playback failure
- **WHEN** the playback backend rejects the request
- **THEN** failure feedback is shown and no successful-action notification is produced

### Requirement: Predefined ability extension point
The dispatcher SHALL support one pre-execution decision and one post-success notification for predefined player skills. With no ability implementation installed it SHALL allow all otherwise valid requests. It SHALL NOT expose user-authored rules or scripts.

#### Scenario: Stage 1 action
- **WHEN** a valid attributed request reaches the Stage 1 dispatcher
- **THEN** the ability check permits it without imposing a cooldown

#### Scenario: Future ability denial
- **WHEN** an installed ability implementation denies a request
- **THEN** playback is not invoked and denial feedback identifies the profile, action and reason

### Requirement: Playback adapter behavior
Combo actions SHALL control the existing playback session. Toggle play/pause SHALL use current playback state; seek actions SHALL move ten seconds and clamp to valid track bounds. The input labels SHALL NOT determine the action independently of the saved binding.

#### Scenario: Seek near the beginning
- **WHEN** seek backward ten seconds is requested at three seconds
- **THEN** playback seeks to zero

### Requirement: Unattributed system controls
Existing player transport controls, automatic queue advancement and Android media controls SHALL retain normal playback behavior without inventing a player identity. They SHALL NOT produce profile-success events. Profile abilities SHALL apply to attributed combo requests, not operate as an access-control boundary for all device controls.

#### Scenario: Notification skip
- **WHEN** the user skips using the Android media notification
- **THEN** normal playback changes occur without assigning the action to P1, P2 or P3
