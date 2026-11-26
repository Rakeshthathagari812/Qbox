"""Speech-to-text and translation rules: the daily limit per person, then the
QBOX AI server does the work (through ai_client).

The limit is counted in memory: fine for one server process. If QBOX ever runs
several backend processes, move the count to the database.
"""

import threading
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date

from app.config import get_settings
from app.errors import ApiError
from app.language.ai_client import AiClient
from app.models import User

# user id -> (day, requests that day)
_used: dict[int, tuple[date, int]] = {}
_used_lock = threading.Lock()


def count_request(user: User) -> None:
    """Each person has a daily limit, so one user cannot keep the AI server busy for everyone."""
    limit = get_settings().language_daily_limit
    today = date.today()
    with _used_lock:
        day, count = _used.get(user.id, (today, 0))
        if day != today:
            count = 0
        if count >= limit:
            raise ApiError(429, "LANGUAGE_LIMIT",
                           "Daily limit for online speech and translation reached. "
                           "QBOX will use the phone's own until tomorrow")
        _used[user.id] = (today, count + 1)


def forget_counts() -> None:
    """Clears every count (used by tests)."""
    with _used_lock:
        _used.clear()


_now = 0
_now_lock = threading.Lock()


@contextmanager
def _a_place() -> Iterator[None]:
    """Only so many at the same moment: the rest of QBOX must stay quick."""
    global _now
    with _now_lock:
        if _now >= get_settings().language_at_once:
            # The app then uses the phone's own speech and translation.
            raise ApiError(503, "LANGUAGE_OFF", "Online speech is very busy right now. Please try again")
        _now += 1
    try:
        yield
    finally:
        with _now_lock:
            _now -= 1


def is_online(ai: AiClient) -> bool:
    return ai.is_up()


def translate(user: User, ai: AiClient, text: str, source: str, target: str, fast: bool = False) -> str:
    with _a_place():
        count_request(user)
        return ai.translate(text.strip(), source, target, fast)


def speech_to_text(user: User, ai: AiClient, audio_base64: str, language: str, sampling_rate: int) -> str:
    with _a_place():
        count_request(user)
        return ai.speech_to_text(audio_base64, language, sampling_rate)
