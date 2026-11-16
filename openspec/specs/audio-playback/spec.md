# audio-playback Specification

## Purpose

Provide local audio playback and queue controls that remain available independently of the profile and combo screens, including Android background playback.

## Requirements

### Requirement: Local audio playback and transport
The application SHALL expose the local music library and support play/pause, next track, previous track, seeking and stop using one shared playback session.

#### Scenario: Control the current queue
- **WHEN** the user starts a local track and performs a valid next-track command with a following track available
- **THEN** playback advances once in the same queue and the visible now-playing state updates

#### Scenario: Unavailable media
- **WHEN** a selected file is inaccessible or a transport command cannot be performed
- **THEN** the application reports a failure or no-op without claiming a successful track change

### Requirement: Android background playback
Playback SHALL continue when the user switches apps or locks the screen during active playback, including automatic advancement through a queue. Force-stop, device shutdown and explicit stop are outside this continuation guarantee.

#### Scenario: Screen off across a track boundary
- **WHEN** the user locks the device while a queue with two playable local tracks is playing
- **THEN** the first track continues and the following track starts without reopening the app

#### Scenario: Returning from another app
- **WHEN** the user switches away during playback and later returns
- **THEN** playback has continued and the displayed track and position reflect the live session

### Requirement: System media controls and interruptions
Android media controls SHALL reflect the current track and support normal play/pause and track navigation. Audio interruptions and headphone disconnection SHALL follow the player's configured interruption behavior without losing the queue.

#### Scenario: Notification control
- **WHEN** the app is backgrounded and the user requests next track through system media controls
- **THEN** the session advances and updates system metadata

#### Scenario: Interrupted playback
- **WHEN** an audio interruption requires a pause
- **THEN** playback pauses and retains the queue and position for subsequent resumption

### Requirement: Profile screen independence
Opening profile settings, recording a binding or leaving the combo screen SHALL NOT replace, dispose or restart the active playback session.

#### Scenario: Editing while music plays
- **WHEN** music is playing and the user opens a profile and records a new binding
- **THEN** playback continues unchanged until a separate runtime playback action is requested
