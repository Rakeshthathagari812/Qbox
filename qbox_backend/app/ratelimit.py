"""Limits how many login / OTP / PIN-reset requests one device (IP address) can make.

Each account already locks after wrong PINs, but someone could try ONE easy PIN
on thousands of different numbers. Counting per device stops that.

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
    limit = get_settings().auth_requests_per_ip_10min
    if limit <= 0:
        return
    ip = request.client.host if request.client else "unknown"
    wait = _count(ip, limit, _WINDOW_SECONDS)
    if wait:
        raise ApiError(429, "TOO_MANY_REQUESTS",
                       f"Too many attempts from this phone. Please try again in {wait} minutes")


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


def _count(key: str, limit: int, window: int) -> int:
    """Counts one request. 0 = allowed; otherwise the minutes to wait."""
    now = time.monotonic()
    with _lock:
        times = _seen.setdefault(key, deque())
        while times and now - times[0] > window:
            times.popleft()
        if len(times) >= limit:
            return int(window - (now - times[0])) // 60 + 1
        times.append(now)
        if len(_seen) > 50_000:  # never grows without end
            for old in [k for k, v in _seen.items() if not v or now - v[-1] > _LOOKUP_WINDOW_SECONDS]:
                del _seen[old]
        return 0


def forget() -> None:
    """Clears every count (used by tests)."""
    with _lock:
        _seen.clear()
