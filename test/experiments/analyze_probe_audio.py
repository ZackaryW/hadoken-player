"""Measure generated tones in emulator capture; no host microphone input."""
import argparse
from array import array
import json
import math
from pathlib import Path
import wave
import sys


def amplitude(samples, frequency, rate):
    coefficient = 2 * math.cos(2 * math.pi * frequency / rate)
    previous = before = 0.0
    for sample in samples:
        value = sample + coefficient * previous - before
        before, previous = previous, value
    power = previous * previous + before * before - coefficient * previous * before
    return 2 * math.sqrt(max(0, power)) / len(samples) if samples else 0


def pulse_period(samples, rate):
    size = rate // 50
    envelope = [amplitude(samples[i:i + size], 880, rate) for i in range(0, len(samples) - size, size)]
    if len(envelope) < 70:
        return None
    mean = sum(envelope) / len(envelope)
    values = [x - mean for x in envelope]
    scores = {}
    for lag in range(10, 36):
        products = sum(values[i] * values[i + lag] for i in range(len(values) - lag))
        norm = math.sqrt(sum(x*x for x in values[:-lag]) * sum(x*x for x in values[lag:]))
        scores[lag] = products / norm if norm else 0
    maximum = max(scores.values())
    peaks = [lag for lag in range(11, 35) if scores[lag] >= scores[lag-1] and scores[lag] >= scores[lag+1] and scores[lag] > maximum * 0.8]
    return min(peaks) / 50 if peaks else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('capture')
    parser.add_argument('--deps')
    args = parser.parse_args()
    if args.deps:
        sys.path.insert(0, args.deps)
    import numpy as np
    directory = Path(args.capture)
    capture = json.loads((directory / 'capture.json').read_text())
    with wave.open(str(directory / 'probe.wav')) as source:
        rate = source.getframerate()
        samples = array('h', source.readframes(source.getnframes()))
    measurements = {}
    phases = capture['phases']
    packets = capture['packets']
    for i, event in enumerate(phases[:-1]):
        end = phases[i+1]['wallUs'] - 400000
        begin = event['wallUs'] + 600000
        selected = [p for p in packets if begin <= p['timestampUs'] < end]
        if not selected:
            measurements[event['phase']] = {'frames': 0, 'rms': 0}
            continue
        values = samples[selected[0]['frame']:selected[-1]['frame'] + selected[-1]['frames']]
        tones = {str(f): amplitude(values, f, rate) for f in [440, 880, 1320]}
        rms = math.sqrt(sum(float(v) * v for v in values) / len(values))
        window = np.hanning(len(values))
        spectrum = np.abs(np.fft.rfft(np.array(values, dtype=float) * window))
        frequencies = np.fft.rfftfreq(len(values), 1 / rate)
        peaks = {}
        for target in [440, 880, 1320]:
            band = np.flatnonzero((frequencies >= target - 15) & (frequencies <= target + 15))
            index = band[np.argmax(spectrum[band])]
            peaks[str(target)] = {'hz': round(float(frequencies[index]), 2), 'amplitude': round(float(2 * spectrum[index] / window.sum()), 3)}
        noise_band = (frequencies >= 2000) & (frequencies <= 10000)
        broadband = math.sqrt(float(2 * np.sum(spectrum[noise_band] ** 2) / (len(values) * np.sum(window ** 2))))
        measurements[event['phase']] = {
            'frames': len(values), 'rms': round(rms, 3),
            'amplitudes': {k: round(v, 3) for k, v in tones.items()},
            'spectralPeaks': peaks,
            'broadbandRms2000To10000Hz': round(broadband, 3),
            'residualRms': round(math.sqrt(max(0, rms*rms - sum(v*v/2 for v in tones.values()))), 3),
            'pulsePeriodSeconds': pulse_period(values, rate),
        }
    result = {'sampleRate': rate, 'measurements': measurements,
              'events': [p for p in phases if p['phase'] in ['speed_measured', 'screen_off_expired', 'failed_source_cleaned', 'stopped', 'done']]}
    (directory / 'measurements.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
