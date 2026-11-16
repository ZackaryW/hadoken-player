# Integration acceptance

## Mixer and application adapters

`2dabbb0` implements the production `MixAudioAdapter`, `SkillMixer`, capability adapter and composed session gain. The checkpoint passed 264 player/skill tests and clean analysis. One active mix is bounded to five minutes and speed/pitch 0.5–2×. Source-bound blends may reuse the primary; continuing blends keep their sources independent. Tests cover preparation cancellation, stale cleanup identities, disposal retry, current volume/speed restoration, pause/expiry without restart, source changes, native advancement, replacement and stop. Session-event tests cover ducking, interruption and headphone removal through the real session service and mixer.

## Android production-adapter capture

On 2026-11-16, built and installed `test/experiments/integrated_mixer_probe.dart` on the same emulator/backend recorded in `audio-feasibility.md`. This entry point uses the production `SkillAudioEffects`, `MixAudioAdapter`, `AudioHandlerImpl`, `AudioSessionService`, Android elapsed clock and actual just_audio decoders. It never reads/writes saved profiles. The capture collector now also issues system media pause and an emulator GSM call/accept/cancel sequence at marked phases.

Capture: `%TEMP%/hadoken-integrated-mixer-capture`, 2,604,194 mono PCM16 frames, 48 kHz. The existing analyzer uses timestamp-aligned phase windows. Commands follow `audio-feasibility.md`, substituting the integrated entry point and output directory. No sample-accurate synchronization claim is made.

| Check | Observed result |
| --- | --- |
| Blend | Peaks 438.34 Hz / 882.11 Hz; RMS 122.215 |
| Pitch 1.5× | Secondary peak 1330.42 Hz; original 880 Hz band amplitude 0.492 |
| Speed 1.5× | 5881 ms source progress / 4002 ms elapsed; captured pulse period 0.50 → 0.34 s |
| Shared pause | Both playback intents paused; output RMS 0.196 |
| Duck factor 0.2 | RMS 23.841 versus resumed 116.492; user volume subsequently changed to 0.4 and retained |
| Noise | Broadband 2–10 kHz RMS 14.019 versus blend 2.089 |
| Screen off | Android reported Dozing; both tones continued; the five-second secondary had been disposed at the 5.5-second observation while the primary kept playing |
| After expiry | Secondary 1320 Hz band amplitude 0.153; zero secondary players |
| Failed source | Capability returned failed; already prepared secondary disposed; primary continued |
| System pause | `cmd media_session dispatch pause` paused primary and secondary; RMS 0.175; resume restored both |
| Phone interruption | Emulator GSM incoming/accepted call paused primary and secondary; hang-up resumed both. Captured audio includes the system telephone sound, so silence/RMS is not used as the interruption assertion |
| Repeated cleanup | Three activation/revoke cycles with duplicate cleanup ended with zero secondary players |
| Stop | Primary stopped, zero secondary players, RMS 0.207 (capture noise floor); final disposal count zero |

Media-session inspection during screen-off mixing showed one active app session in the session stack, owned by `com.hadoken.player.dev`; no second handler/session was created for layers. The normal app APK was restored using install-replace, preserving app data.

## Cross-feature verification

`all_capabilities_test.dart` registers a test-only skill through normal definitions and executes manual activation through `PlayerActionDispatcher`. Its real adapters arm a listener, install effort-60 restrictions, override P2's combo, query songs, edit the next loop, mix audio and execute an effort-80 attributed skip. All seven effects apply; the source assignment remains locked. The P2 listener reports independent tie-block and competing-mix denials. An old catalog request is cancelled. A saved base edit survives the temporary overlay; exact-deadline navigation rebuilds the provisional loop before entering it, and expiry restores the latest base. Stop/restart removes transient effects; reopening storage retains only the base configuration. The production registry remains Skip Recovery only.

Full suite after integration: 888 tests passed. `flutter analyze --no-pub`: no issues after formatting fixes. The established `tool/build_android.ps1` debug build passed.

## Emulator UI acceptance

Inspected the actual Android emulator (1080×2400, 411×914 logical pixels). Ordinary playback advanced from Hadoken A to Hadoken B. Now Playing retained artwork and Player/Combo controls; Combo showed three circular inputs without overflow. Profiles showed only P1/P2/Add profile and bindings, compact Set/Clear rows and on-demand shared-prefix information. Saved P1 Skip Recovery was illuminated; P2 showed the gray tile with Owned by P1. Existing profiles, assignments and bindings were not edited.

Installed `test/experiments/macro_ui_probe.dart`, an entirely in-memory fixture with a registered manual-capable test definition. Inspected skill details → Configure macro → Set; recorded Forward tap and Backward tap; verified ordered notation, explicit Save and the saved focused editor; Back returned to the grid. No overflow or added explanatory paragraphs were observed. Existing widget tests additionally cover 360×640 and large text up to 2.0, hold notation, validation and non-executing recording/practice.

Rebuilt and restored the normal `lib/main.dart` APK with install-replace after the fixture. The Windows capture became stale during final restoration (activation failed); a direct emulator framebuffer capture independently verified the ordinary app home at 10:03 with Hadoken B and the original library. The installed app and final build output are the normal app, not a probe.
