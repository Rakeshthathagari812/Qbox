"""Talks to the QBOX AI server (folder qbox_ai): AI4Bharat IndicConformer
speech-to-text and IndicTrans2 translation, running on our own machine.

No outside company sees what people say. Nothing they say is logged or stored
here; logs only ever hold status codes.
"""

import logging
import threading
import time

import httpx

from app.config import get_settings
from app.errors import ApiError

log = logging.getLogger("qbox.ai")

# Speech on a computer without a graphics card can take a few seconds.
_TIMEOUT = httpx.Timeout(25.0, connect=3.0)
_HEALTH_TIMEOUT = httpx.Timeout(3.0)
_HEALTH_CACHE_SECONDS = 30


def _off(message: str = "Online speech and translation are not set up yet") -> ApiError:
    return ApiError(503, "LANGUAGE_OFF", message)


def _failed() -> ApiError:
    return ApiError(502, "LANGUAGE_FAILED", "The QBOX language service did not answer. Please try again")


class AiClient:
    def __init__(self, transport: httpx.BaseTransport | None = None):
        self._http = httpx.Client(timeout=_TIMEOUT, transport=transport)
        self._health: tuple[float, bool] | None = None
        self._lock = threading.Lock()

    def translate(self, text: str, source: str, target: str) -> str:
        data = self._post("/translate", {"text": text, "source": source, "target": target})
        translated = data.get("text")
        if not isinstance(translated, str) or not translated.strip():
            raise _failed()
        return translated.strip()

    def speech_to_text(self, audio_base64: str, language: str, sampling_rate: int) -> str:
        """The words in a WAV recording. Empty text = nothing could be heard."""
        data = self._post("/speech-to-text",
                          {"audio": audio_base64, "language": language, "samplingRate": sampling_rate})
        heard = data.get("text")
        return heard.strip() if isinstance(heard, str) else ""

    def is_up(self) -> bool:
        """Is the AI server running with its models loaded? Remembered for 30 s."""
        settings = get_settings()
        if not settings.ai_on:
            return False
        with self._lock:
            cached = self._health
        if cached and time.monotonic() - cached[0] < _HEALTH_CACHE_SECONDS:
            return cached[1]
        try:
            response = self._http.get(f"{settings.ai_url.rstrip('/')}/health",
                                      headers=self._headers(), timeout=_HEALTH_TIMEOUT)
            up = response.status_code == 200 and response.json().get("ready") is True
        except (httpx.HTTPError, ValueError, AttributeError):
            up = False
        with self._lock:
            self._health = (time.monotonic(), up)
        return up

    def _headers(self) -> dict:
        return {"X-QBOX-AI-KEY": get_settings().ai_key}

    def _post(self, path: str, body: dict) -> dict:
        settings = get_settings()
        if not settings.ai_on:
            raise _off()
        try:
            response = self._http.post(f"{settings.ai_url.rstrip('/')}{path}", headers=self._headers(), json=body)
        except httpx.ConnectError:
            log.warning("QBOX AI server is not running (%s)", path)
            raise _off("The QBOX language service is not running right now") from None
        except httpx.HTTPError:
            log.warning("QBOX AI server call failed (%s)", path)
            raise _failed() from None

        try:
            data = response.json()
        except ValueError:
            data = {}
        if not isinstance(data, dict):
            data = {}
        if response.status_code >= 400:
            log.warning("QBOX AI server %s returned %s", path, response.status_code)
            code = data.get("code")
            if response.status_code == 400 and code == "NOT_SUPPORTED":
                raise ApiError(400, "LANGUAGE_NOT_SUPPORTED", "This language is not available online yet")
            if response.status_code == 400 and code == "BAD_AUDIO":
                raise ApiError(400, "INVALID_INPUT", "The recording could not be read")
            if response.status_code == 503:
                raise _off("The QBOX language service is starting. Try again in a minute")
            raise _failed()
        return data


_client: AiClient | None = None


def get_ai() -> AiClient:
    """One shared client (keeps connections open)."""
    global _client
    if _client is None:
        _client = AiClient()
    return _client
