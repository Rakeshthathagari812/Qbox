"""Limits how many login / OTP / PIN-reset requests one device (IP address) can make.

Each account already locks after wrong PINs, but someone could try ONE easy PIN
on thousands of different numbers. Counting wrong tries per address stops that.
People on mobile data share addresses, so right logins are hardly limited.

Counted in memory: fine for one server process (a proxy such as Nginx or
Cloudflare should also limit per IP when going live).
"""

import threading
import time
from collections import deque

from fastapi import Request

from app.config import get_settings
from app.errors import ApiError

_WINDOW_SECONDS = 600
_LOOKUP_WINDOW_SECONDS = 3600
LOOKUPS_PER_HOUR = 20
PHOTOS_PER_HOUR = 30
_seen: dict[str, deque[float]] = {}
_lock = threading.Lock()


def limit_auth_requests(request: Request) -> None:
    settings = get_settings()
    ip = request.client.host if request.client else "unknown"
    request.state.ip = ip
    _limit(f"ip:{ip}", settings.auth_requests_per_ip_10min)
    if settings.auth_wrong_per_ip_10min > 0:
        wait = _count(f"wrong:{ip}", settings.auth_wrong_per_ip_10min, _WINDOW_SECONDS, add=False)
        if wait:
            raise _too_many(wait)


def wrong_try(request: Request) -> None:
    """A wrong PIN, code or number was sent from this address."""
    if get_settings().auth_wrong_per_ip_10min > 0:
        _count(f"wrong:{request.state.ip}", get_settings().auth_wrong_per_ip_10min, _WINDOW_SECONDS)


def limit_code(request: Request) -> None:
    """A new code costs an SMS."""
    _limit(f"code:{request.state.ip}", get_settings().auth_codes_per_ip_10min)


def limit_mobile(mobile: str) -> None:
    """One number, from anywhere."""
    _limit(f"mobile:{mobile}", get_settings().auth_requests_per_mobile_10min)


def _limit(key: str, limit: int) -> None:
    if limit <= 0:
        return
    wait = _count(key, limit, _WINDOW_SECONDS)
    if wait:
        raise _too_many(wait)


def _too_many(wait: int) -> ApiError:
    return ApiError(429, "TOO_MANY_REQUESTS", f"Too many attempts. Please try again in {wait} minutes")


def limit_lookups(user_id: int) -> None:
    """Finding a shop by its number: limited per account, so nobody can try
    thousands of numbers to collect shops."""
    wait = _count(f"lookup:{user_id}", LOOKUPS_PER_HOUR, _LOOKUP_WINDOW_SECONDS)
    if wait:
        raise ApiError(429, "TOO_MANY_LOOKUPS", f"Too many numbers tried. Please try again in {wait} minutes")


def limit_photos(user_id: int) -> None:
    wait = _count(f"photo:{user_id}", PHOTOS_PER_HOUR, _LOOKUP_WINDOW_SECONDS)
    if wait:
        raise ApiError(429, "TOO_MANY_PHOTOS", f"Too many photos. Please try again in {wait} minutes")


def _count(key: str, limit: int, window: int, add: bool = True) -> int:
    """Counts one request (or only looks). 0 = allowed; otherwise the minutes to wait."""
    now = time.monotonic()
    with _lock:
        times = _seen.setdefault(key, deque())
        while times and now - times[0] > window:
            times.popleft()
        if len(times) >= limit:
            return int(window - (now - times[0])) // 60 + 1
        if add:
            times.append(now)
        if len(_seen) > 50_000:  # never grows without end
            for old in [k for k, v in _seen.items() if not v or now - v[-1] > _LOOKUP_WINDOW_SECONDS]:
                del _seen[old]
        return 0


def forget() -> None:
    """Clears every count (used by tests)."""
    with _lock:
        _seen.clear()
