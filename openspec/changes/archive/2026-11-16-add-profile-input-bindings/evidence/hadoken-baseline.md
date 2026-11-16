# Hadoken baseline verification

Date: 2026-11-11. Upstream: donfreddy/troona-music at
`3f233344a28328fa380b2e8ac0c81ab061259ff6` (see `upstream/troona-import.json`).

## Toolchain and checks

- Windows host, Flutter 3.47.9 stable, Dart 3.13.7.
- Gradle 8.14, Android Gradle Plugin 8.11.1, Kotlin 2.2.20.
- Gradle daemon uses Temurin 21.0.13. Android Studio's bundled Java 25 is
  incompatible with this Gradle version. A process-local override avoids changing
  the user's global Flutter configuration:

  ```powershell
  ./tool/build_android.ps1 -JdkDirectory 'C:\Users\ZackaryW\scoop\apps\temurin21-jdk\current'
  ```

- `flutter pub get`: passed; retained upstream locked versions and declared the
  existing UUID package as a direct dependency for queue revision tokens.
- `dart format --output=none --set-exit-if-changed lib test`: passed.
- `flutter analyze --no-pub`: passed, no issues.
- `flutter test --no-pub --reporter expanded`: **698 passed**, none skipped.
- Android debug APK build: passed. Initial build 317.4 seconds including SDK
  setup; repeat through `tool/build_android.ps1` passed in 18.9 seconds without
  incremental-cache errors. The APK was installed and launched successfully.

## Import compatibility fixes

Three tests assumed POSIX paths; they now use platform-independent comparisons.
The artwork stream test now waits for the emitted result, rather than assuming
disk I/O finishes within an event-queue pump. Isar tests use the Windows DLL
already supplied by the dependency, so database checks run on this host.

The playback-session crash-consistency test exposed colliding timestamp revisions
for different queue saves. Each changed queue now receives a UUID token; matching
queue/state revisions still support older integer revisions on read.

The initial Android build also exposed Kotlin incremental-cache failures when
the project and Pub cache are on different Windows drives. The build helper
disables incremental Kotlin compilation for its process and restores the caller's
environment afterward. Gradle may warn that AGP/Kotlin support will be removed
in a future Flutter release; no speculative dependency upgrades were made.

## Distribution identity

Hadoken uses Android application ID `com.hadoken.player` (debug/profile suffix
`.dev`) and labels `Hadoken Player` / `Hadoken Dev`. The native namespace and Dart
package remain upstream-compatible. The notification channel is Hadoken-owned.
The registered update controller is disabled even if a saved setting enables
checks; both update controls have been removed from Settings. A regression test
verifies no upstream fetch or release offer when disabled.

## Android playback matrix

Available environment: `Medium_Phone_API_36.1`, Android API 36, x86_64 emulator.
The emulator runs headless; playback state and media-session observations do not
establish physical speaker quality or vendor-specific battery behavior.

Generate two local 30-second tone files with
`python tool/generate_playback_fixtures.py <output-directory>` and copy them to
the emulator's Music directory. Test with both tracks in the queue.

| Check | Result |
| --- | --- |
| APK identity and Settings update controls | Passed: aapt reports `com.hadoken.player.dev`, label `Hadoken Dev`; Online Extras and Help and Feedback have no update controls |
| Foreground playback | Passed: Hadoken A playing, queue size 2, visible mini-player follows session |
| Continued playback after switching apps | Passed: Settings/home foregrounded, audio session remains playing; returning shows live track |
| Screen-off automatic next track | Passed: A at queue occurrence 0 before sleep; after 31 seconds, power Asleep and B playing at occurrence 1 |
| Media notification pause/resume/next | Passed: notification Play/Pause taps change session state; system previous/next dispatch advances A → B with metadata and queue retained |
| Audio interruption and recovery | Passed: emulator incoming call pauses A at 3977 ms; cancelling resumes A at 4498 ms, same occurrence and queue of 2 |

The baseline gate passed on this emulator. This does not replace later physical
device checks for speaker quality or manufacturer-specific background limits.
