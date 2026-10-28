"""Comprueba el asset real empaquetado, sin plugins ni acceso a red."""
from pathlib import Path
import struct
import unittest
import wave


class DemoAudioTest(unittest.TestCase):
    def test_pcm_format_duration_and_non_silent_signal(self):
        path = Path(__file__).resolve().parents[1] / 'assets/audio/mysic-demo.wav'
        with wave.open(str(path), 'rb') as audio:
            self.assertEqual(audio.getnchannels(), 1)
            self.assertEqual(audio.getsampwidth(), 2)
            self.assertEqual(audio.getframerate(), 22050)
            self.assertEqual(audio.getnframes(), 8 * 22050)
            raw = audio.readframes(audio.getnframes())
        samples = struct.unpack('<' + 'h' * (len(raw) // 2), raw)
        self.assertGreater(max(samples), 1000)
        self.assertLess(max(abs(sample) for sample in samples), 6000)


if __name__ == '__main__':
    unittest.main()
