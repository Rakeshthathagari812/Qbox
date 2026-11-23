"""Speech-to-text and translation APIs, with a pretend QBOX AI server (no models)."""

import base64
import json

import httpx
import pytest

from app.config import get_settings
from app.language import service as language_service
from app.language.ai_client import AiClient, get_ai
from app.main import app
from tests.test_calendar import _account

AI_URL = "http://ai.test"
AI_KEY = "test-ai-key-that-is-long-enough-123"
WAV = base64.b64encode(b"RIFF" + b"\x00" * 400).decode()


class FakeAi:
    """Answers like the qbox_ai server, and records what it was sent."""

    def __init__(self):
        self.calls = 0
        self.health_calls = 0
        self.status = 200
        self.error_code = None
        self.ready = True
        self.down = False
        self.slow = False

    def __call__(self, request: httpx.Request) -> httpx.Response:
        if self.down:
            raise httpx.ConnectError("connection refused")
        if self.slow:
            raise httpx.ReadTimeout("too slow")
        assert request.headers["X-QBOX-AI-KEY"] == AI_KEY
        path = request.url.path
        if path == "/health":
            self.health_calls += 1
            return httpx.Response(200, json={"ready": self.ready})
        self.calls += 1
        if self.status != 200:
            return httpx.Response(self.status, json={"code": self.error_code or "ERROR", "message": "no"})
        body = json.loads(request.content)
        if path == "/translate":
            return httpx.Response(200, json={"text": f" [{body['source']}>{body['target']}] {body['text']} "})
        assert path == "/speech-to-text"
        assert body["samplingRate"] == 16000
        assert body["audio"] == WAV
        return httpx.Response(200, json={"text": " తేజ 500 ఇచ్చాడు "})


@pytest.fixture
def ai(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "ai_url", AI_URL)
    monkeypatch.setattr(settings, "ai_key", AI_KEY)
    language_service.forget_counts()
    fake = FakeAi()
    client = AiClient(transport=httpx.MockTransport(fake))
    app.dependency_overrides[get_ai] = lambda: client
    yield fake
    app.dependency_overrides.pop(get_ai, None)
    language_service.forget_counts()


def test_translate(client, ai):
    me = _account(client, "9876543210")
    response = client.post("/api/language/translate",
                           json={"text": " బియ్యం ఎంత? ", "source": "te", "target": "hi"}, headers=me)
    assert response.status_code == 200, response.text
    assert response.json() == {"text": "[te>hi] బియ్యం ఎంత?"}


def test_speech_to_text(client, ai):
    me = _account(client, "9876543210")
    response = client.post("/api/language/speech-to-text",
                           json={"audio": WAV, "language": "te", "samplingRate": 16000}, headers=me)
    assert response.status_code == 200, response.text
    assert response.json() == {"text": "తేజ 500 ఇచ్చాడు"}


def test_switched_off(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "ai_url", "")
    me = _account(client, "9876543210")
    assert client.get("/api/language/status", headers=me).json() == {"online": False}
    response = client.post("/api/language/translate",
                           json={"text": "hi", "source": "en", "target": "te"}, headers=me)
    assert response.status_code == 503
    assert response.json()["code"] == "LANGUAGE_OFF"


def test_status_follows_the_ai_server(client, ai):
    me = _account(client, "9876543210")
    assert client.get("/api/language/status", headers=me).json() == {"online": True}
    client.get("/api/language/status", headers=me)
    assert ai.health_calls == 1  # remembered for a short while


def test_status_when_models_are_still_loading(client, ai):
    ai.ready = False
    me = _account(client, "9876543210")
    assert client.get("/api/language/status", headers=me).json() == {"online": False}


def test_ai_server_not_running_means_off(client, ai):
    ai.down = True
    me = _account(client, "9876543210")
    assert client.get("/api/language/status", headers=me).json() == {"online": False}
    response = client.post("/api/language/translate",
                           json={"text": "hello", "source": "en", "target": "te"}, headers=me)
    assert response.status_code == 503
    assert response.json()["code"] == "LANGUAGE_OFF"  # the app then uses the phone's own


def test_needs_login(client, ai):
    assert client.post("/api/language/translate", json={"text": "a", "source": "en", "target": "te"}).status_code == 401
    assert client.post("/api/language/speech-to-text", json={"audio": WAV, "language": "te"}).status_code == 401
    assert client.get("/api/language/status").status_code == 401


def test_input_checks(client, ai):
    me = _account(client, "9876543210")
    cases = [
        ("/api/language/translate", {"text": "a", "source": "te", "target": "te"}, "Choose two different languages"),
        ("/api/language/translate", {"text": "   ", "source": "te", "target": "hi"}, "Enter something to translate"),
        ("/api/language/translate", {"text": "x" * 1001, "source": "te", "target": "hi"}, None),
        ("/api/language/translate", {"text": "a", "source": "fr", "target": "hi"}, None),
        ("/api/language/speech-to-text", {"audio": "not base64!" * 20, "language": "te"}, "The recording could not be read"),
        ("/api/language/speech-to-text", {"audio": WAV, "language": "te", "samplingRate": 4000}, None),
    ]
    for path, body, message in cases:
        response = client.post(path, json=body, headers=me)
        assert response.status_code == 400, body
        assert response.json()["code"] == "INVALID_INPUT"
        if message:
            assert response.json()["message"] == message
    assert ai.calls == 0  # nothing invalid reaches the AI server


def test_ai_problems_become_clear_errors(client, ai):
    me = _account(client, "9876543210")
    body = {"text": "hello", "source": "en", "target": "te"}

    ai.status = 500
    response = client.post("/api/language/translate", json=body, headers=me)
    assert response.status_code == 502
    assert response.json()["code"] == "LANGUAGE_FAILED"
    assert AI_KEY not in response.text

    ai.status = 503
    assert client.post("/api/language/translate", json=body, headers=me).json()["code"] == "LANGUAGE_OFF"

    ai.status = 400
    ai.error_code = "BAD_AUDIO"
    response = client.post("/api/language/speech-to-text", json={"audio": WAV, "language": "te"}, headers=me)
    assert response.json()["message"] == "The recording could not be read"

    ai.status = 200
    ai.slow = True
    assert client.post("/api/language/translate", json=body, headers=me).json()["code"] == "LANGUAGE_FAILED"


def test_unsupported_language(client, ai):
    me = _account(client, "9876543210")
    ai.status = 400
    ai.error_code = "NOT_SUPPORTED"
    response = client.post("/api/language/speech-to-text", json={"audio": WAV, "language": "en"}, headers=me)
    assert response.status_code == 400
    assert response.json()["code"] == "LANGUAGE_NOT_SUPPORTED"


def test_daily_limit_per_person(client, ai, monkeypatch):
    monkeypatch.setattr(get_settings(), "language_daily_limit", 2)
    me = _account(client, "9876543210")
    other = _account(client, "9123456780")
    body = {"text": "hello", "source": "en", "target": "hi"}
    for _ in range(2):
        assert client.post("/api/language/translate", json=body, headers=me).status_code == 200
    response = client.post("/api/language/translate", json=body, headers=me)
    assert response.status_code == 429
    assert response.json()["code"] == "LANGUAGE_LIMIT"
    # Someone else still has their own limit.
    assert client.post("/api/language/translate", json=body, headers=other).status_code == 200


def test_huge_requests_are_refused_before_reading(client):
    me = _account(client, "9876543210")
    big = b'{"audio": "' + b"A" * (5 * 1024 * 1024) + b'", "language": "te"}'
    response = client.post("/api/language/speech-to-text", content=big,
                           headers={**me, "Content-Type": "application/json"})
    assert response.status_code == 413
    assert response.json()["code"] == "TOO_LARGE"
    response = client.post("/api/language/translate", content=b"{}",
                           headers={**me, "Content-Length": "abc", "Content-Type": "application/json"})
    assert response.status_code in (400, 413)


def test_production_needs_a_private_ai_key():
    from app.config import DEV_AI_KEY, Settings, check_settings

    base = dict(app_env="production", jwt_secret="x" * 40, otp_expose=False, payment_secret_key="p" * 40)
    with pytest.raises(ValueError, match="QBOX_AI_KEY"):
        check_settings(Settings(**base, ai_key=DEV_AI_KEY))
    check_settings(Settings(**base, ai_key="y" * 40))
    check_settings(Settings(**base, ai_url=""))  # switched off: no key needed
