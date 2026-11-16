"""Capture only emulator output for the device-only mixer probe."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
import wave


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--deps', required=True)
    parser.add_argument('--proto-root', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--emulator-state', required=True)
    parser.add_argument('--device', default='emulator-5554')
    parser.add_argument('--port', type=int, default=8554)
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    generated = output / 'generated'
    generated.mkdir(exist_ok=True)
    sys.path[:0] = [args.deps, str(generated)]
    from grpc_tools import protoc
    import grpc
    code = protoc.main(['protoc', '-I' + args.proto_root,
                        '-I' + str(Path(args.deps) / 'grpc_tools' / '_proto'),
                        '--python_out=' + str(generated), '--grpc_python_out=' + str(generated),
                        str(Path(args.proto_root) / 'emulator_controller.proto')])
    if code:
        raise RuntimeError('Could not compile installed emulator protocol')
    import emulator_controller_pb2 as pb
    import emulator_controller_pb2_grpc as rpc
    adb = ['adb', '-s', args.device]
    subprocess.run(adb + ['shell', 'am', 'force-stop', 'com.hadoken.player.dev'], check=True, capture_output=True)
    log = subprocess.Popen(adb + ['logcat', '-v', 'raw', '-T', '1', 'flutter:I', '*:S'],
                           stdout=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
    phases = []
    packets = []
    done = threading.Event()

    def observe():
        for line in log.stdout:
            if 'AUDIO_PROBE ' not in line:
                continue
            event = json.loads(line.split('AUDIO_PROBE ', 1)[1])
            phases.append(event)
            print(json.dumps(event), flush=True)
            if event['phase'] == 'request_system_pause':
                subprocess.run(adb + ['shell', 'cmd', 'media_session', 'dispatch', 'pause'], check=True, capture_output=True)
            if event['phase'] == 'request_call':
                subprocess.run(adb + ['emu', 'gsm', 'call', '5551234'], check=True, capture_output=True)
                subprocess.run(adb + ['emu', 'gsm', 'accept', '5551234'], check=True, capture_output=True)
            if event['phase'] == 'end_call':
                subprocess.run(adb + ['emu', 'gsm', 'cancel', '5551234'], check=True, capture_output=True)
            if event['phase'] == 'screen_off_mix':
                subprocess.run(adb + ['shell', 'input', 'keyevent', '223'], check=True, capture_output=True)
                power = subprocess.run(adb + ['shell', 'dumpsys', 'power'], check=True, capture_output=True, text=True).stdout
                event['powerState'] = [line.strip() for line in power.splitlines() if 'mWakefulness=' in line]
                sessions = subprocess.run(adb + ['shell', 'dumpsys', 'media_session'], check=True, capture_output=True, text=True).stdout
                (output / 'probe-media-session.txt').write_text(sessions, encoding='utf-8')
            if event['phase'] in ('done', 'failed'):
                done.set()
                stream.cancel()

    observer = threading.Thread(target=observe, daemon=True)
    observer.start()
    channel = grpc.insecure_channel('127.0.0.1:' + str(args.port))
    state = dict(line.split('=', 1) for line in Path(args.emulator_state).read_text().splitlines() if '=' in line)
    token = state.get('grpc.token')
    if not token:
        raise RuntimeError('Emulator did not publish local development credentials')
    stream = rpc.EmulatorControllerStub(channel).streamAudio(
        pb.AudioFormat(samplingRate=48000, channels=pb.AudioFormat.Mono,
                       format=pb.AudioFormat.AUD_FMT_S16), timeout=90,
        metadata=[('authorization', 'Bearer ' + token)])
    start = time.monotonic()
    subprocess.run(adb + ['shell', 'input', 'keyevent', '224'], check=True, capture_output=True)
    subprocess.run(adb + ['shell', 'am', 'start', '-n',
                          'com.hadoken.player.dev/com.donfreddy.troona.MainActivity'], check=True, capture_output=True)
    frame = 0
    try:
        with wave.open(str(output / 'probe.wav'), 'wb') as recording:
            recording.setnchannels(1)
            recording.setsampwidth(2)
            recording.setframerate(48000)
            for packet in stream:
                recording.writeframesraw(packet.audio)
                packets.append({'timestampUs': packet.timestamp, 'frame': frame, 'frames': len(packet.audio) // 2})
                frame += len(packet.audio) // 2
                if done.is_set() or time.monotonic() - start > 85:
                    break
    except grpc.RpcError:
        if not done.is_set():
            raise
    finally:
        stream.cancel()
        channel.close()
        log.terminate()
        log.wait(timeout=5)
        subprocess.run(adb + ['shell', 'input', 'keyevent', '224'], check=True, capture_output=True)
        (output / 'capture.json').write_text(json.dumps({'phases': phases, 'packets': packets}, indent=2), encoding='utf-8')
    if not phases or phases[-1]['phase'] != 'done':
        raise RuntimeError('Probe did not finish; inspect captured phase evidence')
    print(json.dumps({'seconds': frame / 48000, 'frames': frame}), flush=True)


if __name__ == '__main__':
    main()
