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

### Requirement: Current and future loop queue targets
Skill queue edits SHALL support the current loop, a selected future loop and a range of future loops within the current playback session. Loops and song occurrences SHALL have stable identities. Future edits SHALL NOT change the current loop. Queue replacement SHALL invalidate plans belonging to the replaced session. Scheduling a future edit SHALL NOT itself enable repeat or force playback to continue.

#### Scenario: Edit only the current loop
- **WHEN** a skill adds or removes a song occurrence in the current loop
- **THEN** that loop changes and later loops retain their baseline unless explicitly targeted

#### Scenario: Edit a selected future loop
- **WHEN** a skill inserts a song into loop N+2 while loop N is playing
- **THEN** loops N and N+1 remain unchanged and the insertion is included when N+2 begins

#### Scenario: Edit a future range
- **WHEN** a skill removes a chosen occurrence from loops N+1 through N+3
- **THEN** those loops apply the edit and N+4 returns to the baseline unless another effect applies

#### Scenario: Replace the queue
- **WHEN** a new album or playlist replaces the playback session before scheduled edits run
- **THEN** old session plans cannot mutate the replacement queue

#### Scenario: Revoke an edit after preloading
- **WHEN** a future-loop plan expires or is revoked after that loop is preloaded but before playback enters it
- **THEN** the unstarted loop is rebuilt without that plan and the current loop remains unchanged

### Requirement: Deterministic loop queue mutations
Queue insertions and removals SHALL validate their target session, loop revision and occurrence identities and execute in order with playback transitions. Duplicate tracks SHALL remain distinct occurrences. Removing the playing occurrence SHALL advance once to a surviving successor or stop if none remains, preserving pause state. Stale operations SHALL report a conflict or no-op without editing another occurrence.

#### Scenario: Remove one duplicate
- **WHEN** a loop contains the same track twice and a skill removes one occurrence
- **THEN** only the selected occurrence is removed

#### Scenario: Remove the final playing occurrence
- **WHEN** a skill removes the only remaining occurrence in the current loop
- **THEN** playback stops without a phantom next-track success or an empty-loop spin

#### Scenario: Compete with an automatic boundary
- **WHEN** a queue edit races with forward advancement into the next loop
- **THEN** it is applied exactly once to its identified loop or rejected as stale, never retargeted silently

### Requirement: Temporary audio mixing capabilities
Skills SHALL be able to add a noise layer and blend two local songs with code-defined gains, start offsets, speed and pitch parameters for a bounded duration. These effects SHALL be temporary layers over the shared session, not destructive edits to source files. Unsupported parameters and unavailable media SHALL return explicit outcomes. The API SHALL expose backend support before activation.

#### Scenario: Noise overlay
- **WHEN** a supported skill starts a noise layer during music playback
- **THEN** the music and noise are audible together until the effect expires or is revoked

#### Scenario: Blend two songs
- **WHEN** a supported skill requests a two-song blend with valid offsets and transformation parameters
- **THEN** both songs contribute to the output with the requested parameters and are released or restored at the effect's end

#### Scenario: Failed source preparation
- **WHEN** a mix source cannot be loaded
- **THEN** the mix fails explicitly, partially prepared layers are disposed and ordinary playback remains controllable

### Requirement: Coordinated mix lifecycle
Every mix layer SHALL participate in the existing session's pause, resume, master volume, ducking, interruption, headphone-disconnect and stop behavior. System media controls SHALL represent one session. Bounded effects SHALL expire while backgrounded; paused or interrupted audio SHALL NOT restart merely because an effect expires. Queue replacement SHALL cancel source-bound mixes and release their resources.

#### Scenario: Background mix
- **WHEN** a mix is active and the screen is locked
- **THEN** the mix continues within the existing playback service and ends at its elapsed-time deadline

#### Scenario: Pause and interruption
- **WHEN** a system pause, qualifying interruption or headphone disconnection pauses the session
- **THEN** all audible layers pause together and follow the configured resumption policy

#### Scenario: Expire while paused
- **WHEN** an effect expires during a pause
- **THEN** its layers are cleaned up while the primary playback remains paused

#### Scenario: Stop all audio
- **WHEN** the session is stopped during a two-song mix
- **THEN** every layer stops and no secondary audio or duplicate media notification remains
