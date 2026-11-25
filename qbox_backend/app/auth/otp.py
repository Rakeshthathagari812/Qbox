"""Creating, sending and checking 6-digit OTPs. Codes are stored only as hashes."""

import secrets
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.auth.sms import send_sms
from app.config import get_settings
from app.errors import ApiError
from app.models import OtpCode, OtpPurpose
from app.security import check_secret, hash_secret

# OTP rows older than this are deleted (they are only needed for the hourly limit).
_KEEP_FOR = timedelta(days=1)
_BY_SHOPS = (OtpPurpose.UDHAAR_ADD.value, OtpPurpose.SUPPLIER_ADD.value)


def _latest(
    db: Session, mobile: str, purpose: OtpPurpose, requested_by: int | None = None, lock: bool = False
) -> OtpCode | None:
    query = (
        select(OtpCode)
        .where(OtpCode.mobile == mobile, OtpCode.purpose == purpose.value)
        .order_by(OtpCode.created_at.desc(), OtpCode.id.desc())
        .limit(1)
    )
    if requested_by is not None:
        # A shop's code works only for that shop, even if two shops ask at once.
        query = query.where(OtpCode.requested_by == requested_by)
    if lock:
        # Makes parallel requests for the same OTP wait their turn, so
        # firing many guesses at once cannot get past the attempt limit.
        query = query.with_for_update()
    return db.scalars(query).first()


def send_otp(
    db: Session,
    mobile: str,
    purpose: OtpPurpose,
    requested_by: int | None = None,
    message: Callable[[str, int], str] | None = None,
    detail: str | None = None,
) -> str:
    """Sends a new OTP and returns the code (only shown to the app in test mode).
    [message] builds the SMS text from (code, minutes valid); [detail] is what it
    says the code is for (see verify_otp)."""
    settings = get_settings()
    now = datetime.now(UTC)

    last = _latest(db, mobile, purpose, requested_by)
    if last is not None:
        waited = (now - last.created_at).total_seconds()
        if waited < settings.otp_resend_seconds:
            left = int(settings.otp_resend_seconds - waited) or 1
            raise ApiError(429, "OTP_TOO_SOON", f"Please wait {left} seconds before asking for a new OTP")

    # Login codes and codes shops ask for have separate hourly limits, so shops
    # can never stop a person from getting their own login OTP.
    by_shops = OtpCode.purpose.in_(_BY_SHOPS)
    sent_last_hour = db.scalar(
        select(func.count())
        .select_from(OtpCode)
        .where(
            OtpCode.mobile == mobile,
            OtpCode.created_at > now - timedelta(hours=1),
            by_shops if purpose.value in _BY_SHOPS else ~by_shops,
        )
    )
    if sent_last_hour >= settings.otp_max_per_hour:
        raise ApiError(429, "OTP_LIMIT", "Too many OTPs for this number. Please try again after an hour")

    db.execute(delete(OtpCode).where(OtpCode.mobile == mobile, OtpCode.created_at < now - _KEEP_FOR))
    code = f"{secrets.randbelow(1_000_000):06d}"
    db.add(OtpCode(
        mobile=mobile,
        purpose=purpose.value,
        code_hash=hash_secret(code),
        requested_by=requested_by,
        detail=detail,
        created_at=now,
        expires_at=now + timedelta(seconds=settings.otp_expiry_seconds),
    ))
    db.commit()

    minutes = settings.otp_expiry_seconds // 60
    text = message(code, minutes) if message else (
        f"{code} is your QBOX OTP. It is valid for {minutes} minutes. Do not share it with anyone."
    )
    send_sms(mobile, text)
    return code


def verify_otp(
    db: Session, mobile: str, purpose: OtpPurpose, code: str, requested_by: int | None = None,
    detail: str | None = None,
) -> int:
    """Checks the most recent OTP for this mobile and purpose and uses it up if correct.
    Returns the OTP's id, which goes into the verification token. With [detail],
    it must be what the message said when it was sent."""
    settings = get_settings()
    otp = _latest(db, mobile, purpose, requested_by, lock=True)
    if otp is None or otp.consumed_at is not None:
        raise ApiError(400, "OTP_NOT_FOUND", "Please send the OTP first")
    if otp.expires_at < datetime.now(UTC):
        raise ApiError(400, "OTP_EXPIRED", "This OTP has expired. Please request a new one")
    if otp.attempts >= settings.otp_max_attempts:
        raise ApiError(429, "OTP_TOO_MANY_ATTEMPTS", "Too many wrong attempts. Please request a new OTP")
    if not check_secret(code, otp.code_hash):
        otp.attempts += 1
        db.commit()
        raise ApiError(400, "OTP_WRONG", "Wrong OTP. Please check and try again")
    otp.consumed_at = datetime.now(UTC)
    db.commit()
    if otp.detail != detail:
        raise ApiError(409, "CODE_OUTDATED", "The amount changed after the code was sent. Please send a new code")
    return otp.id


def use_verification(db: Session, otp_id: int, mobile: str, purpose: OtpPurpose) -> None:
    """Marks a verification token as used. The caller commits it together with
    the change the token allowed, so a failed sign-up does not use it up."""
    otp = db.scalars(
        select(OtpCode)
        .where(OtpCode.id == otp_id, OtpCode.mobile == mobile, OtpCode.purpose == purpose.value)
        .with_for_update()
    ).first()
    if otp is None or otp.consumed_at is None or otp.token_used_at is not None:
        raise ApiError(401, "TOKEN_USED", "This verification was already used. Please verify your mobile again")
    otp.token_used_at = datetime.now(UTC)
