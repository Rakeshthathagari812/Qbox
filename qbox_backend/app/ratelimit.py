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
_seen: dict[str, deque[float]] = {}
_lock = threading.Lock()


def limit_auth_requests(request: Request) -> None:
    limit = get_settings().auth_requests_per_ip_10min
    if limit <= 0:
        return
    ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    with _lock:
        times = _seen.setdefault(ip, deque())
        while times and now - times[0] > _WINDOW_SECONDS:
            times.popleft()
        if len(times) >= limit:
            wait = int(_WINDOW_SECONDS - (now - times[0])) // 60 + 1
            raise ApiError(429, "TOO_MANY_REQUESTS",
                           f"Too many attempts from this phone. Please try again in {wait} minutes")
        times.append(now)
        if len(_seen) > 50_000:  # never grows without end
            for key in [k for k, v in _seen.items() if not v or now - v[-1] > _WINDOW_SECONDS]:
                del _seen[key]


def forget() -> None:
    """Clears every count (used by tests)."""
    with _lock:
        _seen.clear()
