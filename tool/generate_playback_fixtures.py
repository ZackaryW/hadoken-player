"""Create two local, non-copyrighted 30-second tones for Android playback checks."""
import math
from pathlib import Path
import struct
import sys
import wave

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
for name, frequency in (("Hadoken A", 440), ("Hadoken B", 660)):
    with wave.open(str(output / f"{name}.wav"), "wb") as track:
        track.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
        track.writeframes(b"".join(
            struct.pack("<h", int(2000 * math.sin(2 * math.pi * frequency * i / 22050)))
            for i in range(22050 * 30)
        ))
