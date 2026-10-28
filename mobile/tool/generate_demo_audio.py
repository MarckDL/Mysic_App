"""Genera el audio sintético original CC0 de prueba. Sin muestras externas."""
import hashlib
import math
from pathlib import Path
import struct
import wave

OUTPUT = Path(__file__).resolve().parents[1] / 'assets/audio/mysic-demo.wav'
SAMPLE_RATE = 22050
NOTES = [261.625565, 329.627557, 391.995436, 523.251131,
         391.995436, 329.627557, 293.664768, 261.625565] * 2


def generate():
    frames = bytearray()
    note_frames = SAMPLE_RATE // 2
    for frequency in NOTES:
        for index in range(note_frames):
            time = index / SAMPLE_RATE
            # Ataque/salida suaves y amplitud moderada; sin clipping.
            envelope = min(1, time / 0.02, (0.5 - time) / 0.05)
            sample = int(32767 * 0.16 * envelope * math.sin(2 * math.pi * frequency * time))
            frames.extend(struct.pack('<h', sample))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        audio.writeframes(frames)
    print(f'Generated {OUTPUT.name}; sha256={hashlib.sha256(OUTPUT.read_bytes()).hexdigest()}')


if __name__ == '__main__':
    generate()
