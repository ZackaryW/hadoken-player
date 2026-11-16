# Android audio feasibility — task 5.1

Verified on 2026-11-16 against emulator-5554 (Android 16 / API 36), emulator 37.2.13.0 build 16740729. Installed dependencies: just_audio 0.10.5, audio_service 0.18.18, audio_session 0.2.2. The probe uses one AudioService handler, local generated WAV files and secondary players with independent audio-session activation disabled.

## Reproduction

- Build `test/experiments/mixer_probe.dart` using `flutter build apk --debug --target test/experiments/mixer_probe.dart`, with the same JDK/GRADLE_OPTS as `tool/build_android.ps1`.
- Preserve the ordinary APK, then `adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`. No app-data clearing.
- Start the emulator's existing local development endpoint with `adb -s emulator-5554 emu grpc 8554`.
- Isolated capture dependencies under `%TEMP%/hadoken-audio-probe-deps`: grpcio/grpcio-tools 1.85.1, protobuf 7.36.2, numpy. No project or system Python dependency changes.
- Run `python test/experiments/capture_emulator_audio.py --deps <temporary dependencies> --proto-root <Android SDK>/emulator/lib --emulator-state <temporary avd>/running/pid_16884.ini --output <temporary capture>`.
- Run `python test/experiments/analyze_probe_audio.py <temporary capture> --deps <temporary dependencies>`.
- The collector uses the emulator's published development credential without printing or saving it, captures emulator output (not the host microphone), sleeps the device at the marked phase, and cancels capture at probe completion.
- Restore the ordinary APK with `adb install -r`. This was completed; saved profiles and skill assignments were not edited by the probe.

## Measured evidence

Verified capture: `%TEMP%/hadoken-audio-probe-verified`, 2,191,974 mono PCM16 frames at 48 kHz. The collector completed successfully. Frames omit some idle periods, so phase selection uses emulator capture timestamps rather than concatenated WAV time. Spectral peaks use a Hann window; emulator resampling introduces small frequency drift. This is evidence of mixing and transforms, not sample-accurate synchronization.

| Phase | Measured output |
| --- | --- |
| Two-song blend | Peaks at 438.23 Hz and 882.17 Hz, amplitudes 91.95 and 46.139 PCM units; RMS 122.794 |
| Secondary pitch 1.5× | Secondary peak 1328.56 Hz (amplitude 55.375); original 880 Hz band amplitude 0.465; primary remains near 440 Hz |
| Secondary speed 1.5× | Source advances 7505 ms in 5003 ms; captured pulse period changes from 0.50 s to 0.34 s |
| Pause both | Both player states false; RMS 0.188 versus blend 122.794 |
| Duck both to one-fifth gain | RMS 24.439, approximately one-fifth of the full-gain blend |
| Noise overlay | 2–10 kHz broadband RMS 20.981 versus blend 1.864, while the primary tone remains present |
| Screen off | `dumpsys power` reported `mWakefulness=Dozing` / 3 after sleep; mixing continued |
| Five-second background expiry | Expiry callback 5007.8 ms after phase start; primary still playing; layer count one; 1320 Hz band falls to amplitude 0.038 |
| Failed source | Invalid WAV path rejected; prepared player disposed; one primary layer continues |
| Stop / teardown | Captured RMS 0.0; primary playing false; final layer count zero |

`dumpsys media_session` during screen-off mixing reported one session in the stack, owned by `com.hadoken.player.dev`.

## Result and limits

The installed Android stack supports the planned noise/two-song mixer, speed/pitch changes, coordinated transport/gain and elapsed-time expiry under its playback service. Proceed with production adapter integration. This feasibility probe manually coordinates its players; it does not complete production integration, real app interruption acceptance, or task 5.4. Those remain separately tracked.
