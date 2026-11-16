# Hadoken Player

Android local audio player built on [Troona](https://github.com/donfreddy/troona-music),
revision `3f233344a28328fa380b2e8ac0c81ab061259ff6`.

This baseline preserves Troona playback and library UI, uses Hadoken Android
identity, and disables upstream update offers. Profile combo controls are planned
for subsequent checkpoints.

See [baseline verification](docs/hadoken-baseline.md),
[upstream license](docs/upstream/troona-LICENSE),
[upstream README](docs/upstream/troona-README.md) and
[import inventory](docs/upstream/troona-import.json).

Build with a compatible JDK (tested with 21):

```powershell
./tool/build_android.ps1 -JdkDirectory '<path-to-jdk-21>'
```
