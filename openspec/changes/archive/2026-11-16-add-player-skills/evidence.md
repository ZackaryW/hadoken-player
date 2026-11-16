# Implementation evidence

## Catalog checkpoint
Skip Recovery has stable ID skip-recovery and a fixed ten-second duration. Assignments use a separate version-1 preferences document; unknown IDs remain visible but inactive. Only explicitly added profiles accept assignments. The repository publishes only after persistence succeeds.
Cooldown deadlines are transient to the current service/process session. Reloading assignments does not restore a deadline.
Four repository tests cover defaults, persistence, fixed metadata, unknown IDs, failed-write rollback, malformed entries and unadded profiles. Existing action tests verified the prerequisite contract before skill behavior changes.

## Policy checkpoint
The dispatcher owns one ordered queue for playback decisions, results and assignment edits. Skip Recovery uses a per-profile completion deadline; duplicate success IDs cannot extend it. Binding edits and renames keep the same identity, and only the affected cooling profile rejects assignment changes. Failures/no-ops never start recovery.
AndroidSkillClock queries SystemClock.elapsedRealtime at action and UI status boundaries. The Android implementation includes sleep and does not depend on wall time: https://developer.android.com/reference/android/os/SystemClock#elapsedRealtime(). No clock platform call is awaited during startup. Clock failure rejects action processing rather than guessing.
Twenty-nine skills plus existing dispatcher/adapter tests pass: exact boundary, independent players, queued requests/edits, duplicate delivery, rebinding/renaming, simulated background time, fresh process state, failed storage and platform channel errors. Actual Android lifecycle acceptance is tracked separately in task 4.2.

## UI and playback integration checkpoint
Player skills is a separate Settings destination. Existing profiles select a fixed Skip Recovery switch and Ready/Ready in Ns status; descriptions appear only through the info control. Widget tests cover persistence, unavailable IDs, save failures, active edit rejection, navigation/resume, no replay on expiration, Now Playing denial attribution and 360×640 at 2× text.
The saved-combo integration test exercises recording/practice isolation, unowned adapter controls, P2 success, P2 denial, P1 allowed, P2 allowed at ten seconds, queue-boundary no-op and adapter failure. It uses the actual recognition, dispatcher, skill policy and playback adapter with a deterministic audio-port double. No input binding or media data is changed by assignment.

## Final automated and Android acceptance — 2026-11-16
- Full suite: 783 tests passed. Analysis: no issues. Formatting: 409 files unchanged. Android debug build passed.
- Final APK SHA-256: 9A551582B6784041BC62FDDB18EDF9ACD44FB3E14619ECE0BC440414CB398590.
- Device: emulator-5554, Medium_Phone_API_36.1, Android API 36 x86_64. Existing two 30-second Hadoken A/B fixtures and saved P1 Forward-tap / P2 Forward-tap-Backward-hold bindings were retained.
- Assigned Skip Recovery to P2 in the separate skills screen. P2 skipped B to A; the next P2 attempt showed 8s remaining and kept A; P1 then skipped A to B within the cooldown.
- A subsequent P2 skip started recovery. Screen off for twelve seconds retained process 10915 and paused A without an extra transition; after wake P2 successfully skipped to B.
- With the skill assigned, playing B continued after opening Android Settings. After 32 seconds with mWakefulness=Asleep, metadata showed A playing at queue occurrence 1.
- Actual notification taps paused B at 10872ms, advanced to A while paused, then resumed A.
- Simulated incoming GSM call paused A at 842ms; cancellation resumed at 851ms with the same occurrence and queue.
- Force-stop/relaunch changed process ID from 10915 to 11912; P2 remained assigned and Ready. Final session is paused with repeat off, and the skills screen remains open.
- Screenshot: [Player skills](evidence/player-skills.png). Notification automation used screenshot-guided taps after UI hierarchy dumping could not reach an idle state; session metadata confirmed each outcome.
- Limits: emulator observations do not establish physical speaker output or manufacturer-specific power restrictions.
