# Formal verification: add-profile-input-bindings

Date: 2026-11-16. Reviewed the current implementation, all four delta specifications, proposal, design, 23 task descriptions and existing device evidence.

| Dimension | Result |
| --- | --- |
| Completeness | 23/23 tasks; 25/25 requirements mapped |
| Correctness | 52 scenarios reviewed against code, automated coverage and recorded Android acceptance |
| Coherence | Feature boundaries, single audio port, shared clock/classifier, serialized dispatch and focused UI match the design |

The review found a timing-observation gap: completed down/up and gap measurements were discarded. Fixed in e20a577 with immutable bounded match observations and tests for timing, cancellation and mismatch-prefix truncation. Profile/UI follow-ups are committed in 84709f1.

Final automated checks: 764 tests passed; analysis clean; formatting clean (396 files); Android debug APK built successfully. Timing-observation changes do not alter playback dispatch. The previously recorded API 36 emulator background, screen-off, notification and interruption matrix remains the device evidence; it was not rerun solely for this data-retention fix.

No unresolved critical issues, warnings or skipped verification dimensions. Ready to synchronize and archive. Physical speaker output and manufacturer-specific battery restrictions remain outside the recorded emulator evidence, not claimed as tested.

## audio-playback

Implementation: lib/features/player/domain/ports/audio_service_port.dart; lib/features/player/data/adapters/just_audio_adapter.dart; lib/services/audio/.

Evidence: test/unit/player/; evidence/hadoken-verification.md Android acceptance matrix.

- Local audio playback and transport: implementation present and scenario behavior reviewed.
- Android background playback: implementation present and scenario behavior reviewed.
- System media controls and interruptions: implementation present and scenario behavior reviewed.
- Profile screen independence: implementation present and scenario behavior reviewed.

Scenarios reviewed: Control the current queue; Unavailable media; Screen off across a track boundary; Returning from another app; Notification control; Interrupted playback; Editing while music plays.

## input-recognition

Implementation: lib/features/input_bindings/domain/combo_input.dart; lib/features/input_bindings/presentation/combo_widgets.dart; lib/features/profiles/presentation/binding_recorder.dart.

Evidence: test/unit/input_bindings/combo_input_test.dart; test/widget/profiles/profile_controls_test.dart.

- Three buttons and six stroke types: implementation present and scenario behavior reviewed.
- Shared recognition timing: implementation present and scenario behavior reviewed.
- Set records one to five strokes: implementation present and scenario behavior reviewed.
- Fighting-game combination display: implementation present and scenario behavior reviewed.
- Longest completed combination: implementation present and scenario behavior reviewed.
- Safe cancellation and sequential input: implementation present and scenario behavior reviewed.
- Recording and practice are non-executing: implementation present and scenario behavior reviewed.

Scenarios reviewed: Long hold is one stroke; Short press; Threshold boundary; Clock adjustment; Timing settings change; Record and save; Recording limits; Review without an automatic save; Read a mixed combination; Longer player's combination wins; Shorter combination after timeout; Exact gap deadline; Mismatching continuation; No completed match; App leaves the foreground; Two buttons held together; Practice a skip.

## player-actions

Implementation: lib/features/player_actions/domain/action_dispatcher.dart; lib/features/player_actions/data/playback_commands_adapter.dart; lib/features/player_actions/profile_controls.dart.

Evidence: test/unit/player_actions/action_dispatcher_test.dart; playback_commands_adapter_test.dart; profile_controls_test.dart.

- Attributed action requests: implementation present and scenario behavior reviewed.
- Serialized single execution: implementation present and scenario behavior reviewed.
- Explicit execution outcomes: implementation present and scenario behavior reviewed.
- Predefined ability extension point: implementation present and scenario behavior reviewed.
- Playback adapter behavior: implementation present and scenario behavior reviewed.
- Unattributed system controls: implementation present and scenario behavior reviewed.

Scenarios reviewed: Different commands for the same action; Two near-simultaneous requests; Repeated delivery; End of queue; Playback failure; Stage 1 action; Future ability denial; Seek near the beginning; Notification skip.

## player-profiles

Implementation: lib/features/profiles/domain/; lib/features/profiles/presentation/; lib/features/input_bindings/presentation/now_playing_combo_controls.dart; lib/core/router/app_router.dart.

Evidence: test/unit/profiles/profile_repository_test.dart; test/widget/profiles/; test/widget/player/full_player_layout_test.dart.

- Up to three explicitly added profiles: implementation present and scenario behavior reviewed.
- Action binding configuration: implementation present and scenario behavior reviewed.
- Complete-combination exclusivity: implementation present and scenario behavior reviewed.
- Atomic and valid configuration: implementation present and scenario behavior reviewed.
- Ownership follows the combination: implementation present and scenario behavior reviewed.
- Discoverable Now Playing combo controls: implementation present and scenario behavior reviewed.
- Focused profile configuration: implementation present and scenario behavior reviewed.
- Compact binding rows: implementation present and scenario behavior reviewed.

Scenarios reviewed: Start with one player; Add a player; Reopen a configured profile; Profile limit; Replace a binding; Cancel an edit; Cross-profile duplicate; Shared prefix is allowed; Same-profile duplicate; Competing saves; Invalid saved data; Another player's combo from the profile screen; Use combos without finding a settings subpage; Return to ordinary playback controls; Small screen layout; Edit a profile without unrelated settings; Change shared timing separately; Review a shared-prefix binding; Clear a bound action.
