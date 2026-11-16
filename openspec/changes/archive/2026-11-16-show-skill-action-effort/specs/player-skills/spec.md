## ADDED Requirements

### Requirement: Visible skill action effort
On-demand skill details SHALL display the code-defined effort beside each mentioned action or restriction. Manual-capable skills SHALL also show their activation effort. Numbers SHALL reflect the corresponding runtime declarations and SHALL remain read-only. Details SHALL remain concise and usable with large text without crowding assignment tiles.

#### Scenario: Inspect recovery effort
- **WHEN** a player opens Skip Recovery details
- **THEN** each skip and block-skip mention shows effort 50 alongside its label, separately from the ten-second duration

#### Scenario: Inspect activation effort
- **WHEN** a manual-capable skill declares activation effort 80
- **THEN** its details show Activate (80) without offering an effort editor

#### Scenario: Large text details
- **WHEN** skill details are displayed at 360 by 640 logical pixels with text scaling 2.0
- **THEN** action labels and numbers remain readable and the dialog actions remain reachable without overflow
