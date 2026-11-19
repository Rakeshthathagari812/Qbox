"""Hashing (PINs, OTPs) and login tokens (JWT).

Two kinds of tokens:
- verification token: proves a mobile number passed OTP; works once, to sign up or reset the PIN
- access token: proves the user is logged in; sent with every request after login
"""

from datetime import UTC, datetime, timedelta

import bcrypt
import jwt

from app.config import get_settings
from app.errors import ApiError
from app.models import OtpPurpose

_ALGORITHM = "HS256"
_REQUIRED_CLAIMS = ["exp", "iat", "sub", "typ"]

# Checked against when a mobile number has no account, so a wrong login takes
# the same time either way and does not reveal which numbers are registered.
DUMMY_HASH = bcrypt.hashpw(b"not-a-real-pin", bcrypt.gensalt()).decode()


def hash_secret(value: str) -> str:
    """One-way scramble. The original can never be read back."""
    return bcrypt.hashpw(value.encode(), bcrypt.gensalt()).decode()


def check_secret(value: str, hashed: str) -> bool:
    return bcrypt.checkpw(value.encode(), hashed.encode())


def create_verification_token(mobile: str, purpose: OtpPurpose, otp_id: int) -> str:
    minutes = get_settings().verification_token_minutes
    claims = {"sub": mobile, "typ": "verify", "purpose": purpose.value, "oid": otp_id}
    return _encode(claims, timedelta(minutes=minutes))


def create_access_token(user_id: int, token_version: int) -> str:
    days = get_settings().access_token_days
    return _encode({"sub": str(user_id), "typ": "access", "ver": token_version}, timedelta(days=days))


def read_verification(token: str, purpose: OtpPurpose) -> tuple[str, int]:
    """Returns (mobile, id of the OTP it came from)."""
    claims = _decode(token, "verify")
    if claims.get("purpose") != purpose.value or not isinstance(claims.get("oid"), int):
        raise ApiError(401, "TOKEN_INVALID",
                       "This verification is not valid for this step. Please verify your mobile again")
    return claims["sub"], claims["oid"]


def read_access(token: str) -> tuple[int, int]:
    """Returns (user id, token version)."""
    claims = _decode(token, "access")
    try:
        return int(claims["sub"]), int(claims.get("ver", -1))
    except (TypeError, ValueError):
        raise ApiError(401, "TOKEN_INVALID", "Session is not valid. Please log in again") from None


def _encode(claims: dict, life: timedelta) -> str:
    now = datetime.now(UTC)
    payload = {**claims, "iat": now, "exp": now + life}
    return jwt.encode(payload, get_settings().jwt_secret, algorithm=_ALGORITHM)


def _decode(token: str, expected_type: str) -> dict:
    try:
        claims = jwt.decode(token, get_settings().jwt_secret, algorithms=[_ALGORITHM],
                            options={"require": _REQUIRED_CLAIMS})
    except jwt.PyJWTError:
        raise ApiError(401, "TOKEN_INVALID", "Your session has expired. Please try again") from None
    if claims.get("typ") != expected_type:
        raise ApiError(401, "TOKEN_INVALID", "Session is not valid. Please log in again")
    return claims
