# Hadoken Player

A local audio player with P1–P3 profiles and customizable tap/hold combos.

Open Now Playing and choose **Combo** beside **Player**. The gamepad button
opens profile setup directly. Choose a player and use **Set**
beside an action. Three buttons (Forward, Pause, Backward) accept taps and holds
in sequences of up to five strokes. Saved combos have one owner across players;
shared prefixes are supported. The separate combo pad offers Practice without
changing music; profile setup is also available under Settings.

For a Windows Android build, use a compatible JDK (tested with 21):

```powershell
./tool/build_android.ps1 -JdkDirectory '<path-to-jdk-21>'
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

Built on [Troona](https://github.com/donfreddy/troona-music), revision
`3f233344a28328fa380b2e8ac0c81ab061259ff6`. Troona's Flutter package name is
retained during integration. Its MIT copyright and license are preserved in
[the upstream license](docs/upstream/troona-LICENSE); the original project guide
is in [the upstream README](docs/upstream/troona-README.md).

The [import inventory](docs/upstream/troona-import.json) records all 566 upstream
files and their original SHA-256 hashes. README, LICENSE and ignore rules were
retained separately so importing the application preserved this repository's
identity and OpenSpec planning. Subsequent integration edits may differ from
those original hashes.
