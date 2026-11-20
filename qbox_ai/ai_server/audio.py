"""Reads the phone's WAV recording into numbers the speech model can use."""

import io
import wave

import numpy as np

TARGET_RATE = 16000
MAX_SECONDS = 60


class BadAudio(Exception):
    pass


def read_wav(data: bytes) -> tuple[np.ndarray, int]:
    """16-bit PCM WAV -> (mono float samples between -1 and 1, sample rate)."""
    try:
        with wave.open(io.BytesIO(data)) as wav:
            channels = wav.getnchannels()
            width = wav.getsampwidth()
            rate = wav.getframerate()
            frames = wav.readframes(wav.getnframes())
    except (wave.Error, EOFError, ValueError) as error:
        raise BadAudio(str(error)) from None
    if width != 2 or channels < 1 or not 8000 <= rate <= 48000:
        raise BadAudio("only 16-bit PCM WAV is accepted")
    samples = np.frombuffer(frames[: len(frames) - len(frames) % (2 * channels)], dtype="<i2")
    if samples.size == 0:
        raise BadAudio("empty recording")
    samples = samples.astype(np.float32) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    if samples.size > MAX_SECONDS * rate:
        raise BadAudio("recording too long")
    return samples, rate


def clean(samples: np.ndarray, rate: int) -> np.ndarray:
    """Gets a phone recording ready for the speech model:
    removes the hum offset, cuts the silence before and after the words
    (keeping a little), and makes a quiet voice louder."""
    samples = samples - float(samples.mean())
    frame = max(1, int(0.02 * rate))  # 20 ms pieces
    count = samples.size // frame
    if count > 10:
        loudness = np.sqrt((samples[: count * frame].reshape(count, frame) ** 2).mean(axis=1))
        threshold = max(float(loudness.max()) * 0.05, 1e-4)
        speaking = np.flatnonzero(loudness > threshold)
        if speaking.size:
            keep = 10  # 200 ms either side
            start = max(0, int(speaking[0]) - keep) * frame
            end = min(count, int(speaking[-1]) + keep + 1) * frame
            samples = samples[start:end]
            samples = samples - float(samples.mean())
    peak = float(np.abs(samples).max()) if samples.size else 0.0
    if 0 < peak < 0.5:
        samples = samples * (0.7 / peak)  # soft voice: louder, never clipped
    return samples.astype(np.float32)
