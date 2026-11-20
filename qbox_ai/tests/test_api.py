"""The AI server's API, with pretend models (no downloads needed)."""

import base64
import io
import wave

import pytest
from fastapi.testclient import TestClient

from ai_server.audio import BadAudio, read_wav
from ai_server.config import get_settings
from ai_server.languages import SPEECH, NotSupported, translation_direction
from ai_server.main import app
from ai_server.models import ModelMissing

KEY = {"X-QBOX-AI-KEY": get_settings().key}


def make_wav(seconds=0.5, rate=16000, channels=1, width=2) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(width)
        wav.setframerate(rate)
        wav.writeframes(b"\x10\x00" * int(seconds * rate) * channels * (width // 2 or 1))
    return buffer.getvalue()


class FakeModels:
    def __init__(self):
        self.ready = True
        self.error = None
        self.heard = []

    def installed(self):
        return {"en-indic": True, "indic-en": True, "indic-indic": True, "speech": True}

    def translate(self, text, source, target):
        if self.error:
            raise self.error
        translation_direction(source, target)
        return f"[{source}>{target}] {text}"

    def speech_to_text(self, wav, language):
        if self.error:
            raise self.error
        if language not in SPEECH:
            raise NotSupported()
        read_wav(wav)
        self.heard.append(language)
        return "తేజ 500 ఇచ్చాడు"


@pytest.fixture
def fake():
    models = FakeModels()
    app.state.models = models
    with TestClient(app) as client:
        client.models = models
        yield client
    app.state.models = None


def test_translate(fake):
    response = fake.post("/translate", json={"text": " rice price? ", "source": "en", "target": "te"}, headers=KEY)
    assert response.status_code == 200, response.text
    assert response.json() == {"text": "[en>te] rice price?"}


def test_speech_to_text(fake):
    audio = base64.b64encode(make_wav()).decode()
    response = fake.post("/speech-to-text", json={"audio": audio, "language": "te", "samplingRate": 16000},
                         headers=KEY)
    assert response.status_code == 200, response.text
    assert response.json() == {"text": "తేజ 500 ఇచ్చాడు"}


def test_every_call_needs_the_key(fake):
    body = {"text": "a", "source": "en", "target": "te"}
    assert fake.post("/translate", json=body).status_code == 401
    assert fake.post("/translate", json=body, headers={"X-QBOX-AI-KEY": "wrong"}).status_code == 401
    assert fake.get("/health").status_code == 401
    assert fake.get("/health", headers=KEY).json()["ready"] is True


def test_no_api_pages(fake):
    assert fake.get("/docs").status_code == 404
    assert fake.get("/openapi.json").status_code == 404


def test_english_speech_is_not_supported(fake):
    audio = base64.b64encode(make_wav()).decode()
    response = fake.post("/speech-to-text", json={"audio": audio, "language": "en"}, headers=KEY)
    assert response.status_code == 400
    assert response.json()["code"] == "NOT_SUPPORTED"


def test_bad_recordings(fake):
    for audio in ["not base64!" * 20, base64.b64encode(b"RIFF" + b"\x00" * 200).decode()]:
        response = fake.post("/speech-to-text", json={"audio": audio, "language": "te"}, headers=KEY)
        assert response.status_code == 400
        assert response.json()["code"] == "BAD_AUDIO"


def test_still_loading(fake):
    fake.models.ready = False
    response = fake.post("/translate", json={"text": "a", "source": "en", "target": "te"}, headers=KEY)
    assert response.status_code == 503
    assert fake.get("/health", headers=KEY).json()["ready"] is False


def test_model_problems(fake):
    body = {"text": "a", "source": "en", "target": "te"}
    fake.models.error = ModelMissing("en-indic")
    assert fake.post("/translate", json=body, headers=KEY).status_code == 503
    fake.models.error = RuntimeError("secret words")
    response = fake.post("/translate", json=body, headers=KEY)
    assert response.status_code == 500
    assert "secret" not in response.text


def test_input_checks(fake):
    for body in [
        {"text": "", "source": "en", "target": "te"},
        {"text": "x" * 1001, "source": "en", "target": "te"},
        {"text": "a", "source": "fr", "target": "te"},
    ]:
        assert fake.post("/translate", json=body, headers=KEY).status_code == 400
    assert fake.post("/translate", json={"text": "a", "source": "te", "target": "te"},
                     headers=KEY).json()["code"] == "NOT_SUPPORTED"


def test_read_wav():
    samples, rate = read_wav(make_wav(seconds=1, rate=16000))
    assert rate == 16000 and samples.shape == (16000,) and abs(samples[0] - 16 / 32768) < 1e-6
    stereo, _ = read_wav(make_wav(seconds=1, channels=2))
    assert stereo.shape == (16000,)
    with pytest.raises(BadAudio):
        read_wav(b"nonsense")
    with pytest.raises(BadAudio):
        read_wav(make_wav(seconds=0))
    with pytest.raises(BadAudio):
        read_wav(make_wav(seconds=61))


def test_recording_clean_up():
    import numpy as np

    from ai_server.audio import clean

    rate = 16000
    silence = np.zeros(rate, dtype=np.float32) + 0.01  # 1 s of near-silence (with a hum offset)
    voice = (0.1 * np.sin(np.linspace(0, 400 * np.pi, rate))).astype(np.float32)  # 1 s, soft
    out = clean(np.concatenate([silence, voice, silence]), rate)
    assert 1.0 <= out.size / rate <= 1.5  # the silence before and after is cut, a little kept
    assert 0.65 <= float(np.abs(out).max()) <= 0.71  # the soft voice is made louder, not clipped
    assert abs(float(out.mean())) < 0.01  # no hum offset
    loud = (0.9 * np.sin(np.linspace(0, 400 * np.pi, rate))).astype(np.float32)
    assert float(np.abs(clean(loud, rate)).max()) <= 0.91  # a loud voice is left as it is


def test_directions():
    assert translation_direction("en", "te") == "en-indic"
    assert translation_direction("ta", "en") == "indic-en"
    assert translation_direction("te", "hi") == "indic-indic"
    for pair in [("en", "en"), ("fr", "te")]:
        with pytest.raises(NotSupported):
            translation_direction(*pair)
