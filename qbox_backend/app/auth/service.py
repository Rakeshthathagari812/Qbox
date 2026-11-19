"""Sign up, log in and reset PIN: the business rules."""

import math
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import otp
from app.auth.schemas import AuthOut, RegisterIn, SendOtpOut, VerifyOtpOut
from app.config import get_settings
from app.errors import ApiError
from app.models import CustomerProfile, OtpPurpose, Role, ShopProfile, SupplierProfile, User, UserRole
from app.security import (
    DUMMY_HASH,
    check_secret,
    create_access_token,
    create_verification_token,
    hash_secret,
    read_verification,
)
from app.users.service import to_me

# Must match otherOption in the app's registration_options.dart.
OTHER = "Other"
WRONG_LOGIN = "Mobile number or PIN does not match"
ALREADY_REGISTERED = "This mobile number is already registered. Please log in"
NOT_FOUND = "No QBOX account found for this mobile number"


def _find_user(db: Session, mobile: str, lock: bool = False) -> User | None:
    query = select(User).where(User.mobile == mobile)
    if lock:
        # Parallel logins for one account wait their turn, so the
        # wrong-PIN counter cannot be skipped by sending many at once.
        query = query.with_for_update()
    return db.scalars(query).first()


def send_otp(db: Session, mobile: str, purpose: OtpPurpose) -> SendOtpOut:
    registered = _find_user(db, mobile) is not None
    if purpose == OtpPurpose.SIGNUP and registered:
        raise ApiError(409, "MOBILE_REGISTERED", ALREADY_REGISTERED)
    if purpose == OtpPurpose.RESET_PIN and not registered:
        raise ApiError(404, "MOBILE_NOT_FOUND", NOT_FOUND)

    settings = get_settings()
    code = otp.send_otp(db, mobile, purpose)
    return SendOtpOut(
        mobile=mobile,
        expires_in_seconds=settings.otp_expiry_seconds,
        resend_in_seconds=settings.otp_resend_seconds,
        dev_otp=code if settings.otp_expose else None,
    )


def verify_otp(db: Session, mobile: str, purpose: OtpPurpose, code: str) -> VerifyOtpOut:
    otp_id = otp.verify_otp(db, mobile, purpose, code)
    return VerifyOtpOut(
        verification_token=create_verification_token(mobile, purpose, otp_id),
        expires_in_seconds=get_settings().verification_token_minutes * 60,
    )


def register(db: Session, body: RegisterIn) -> AuthOut:
    mobile, otp_id = read_verification(body.verification_token, OtpPurpose.SIGNUP)
    if _find_user(db, mobile) is not None:
        raise ApiError(409, "MOBILE_REGISTERED", ALREADY_REGISTERED)
    _check_role_details(body)
    otp.use_verification(db, otp_id, mobile, OtpPurpose.SIGNUP)

    user = User(mobile=mobile, pin_hash=hash_secret(body.pin))
    db.add(user)
    try:
        db.flush()  # gives the new user its id, needed for the QBOX IDs below
    except IntegrityError:
        # The same number finished signing up a moment ago in another request.
        db.rollback()
        raise ApiError(409, "MOBILE_REGISTERED", ALREADY_REGISTERED) from None

    user.roles = [UserRole(role=role.value) for role in body.roles]
    if Role.BUSINESS in body.roles:
        s = body.shop
        user.shop = ShopProfile(
            qbox_id=Role.BUSINESS.qbox_id(user.id),
            shop_name=s.shop_name.strip(),
            business_type=s.business_type,
            business_type_detail=_detail(s.business_type, s.business_type_detail),
            shop_category=s.shop_category,
            shop_category_detail=_detail(s.shop_category, s.shop_category_detail),
            address=s.address.strip(),
            contact_number=s.contact_number,
        )
    if Role.CUSTOMER in body.roles:
        c = body.customer
        user.customer = CustomerProfile(
            qbox_id=Role.CUSTOMER.qbox_id(user.id),
            full_name=c.full_name.strip(),
            mobile_number=c.mobile_number,
            email=_blank_to_none(c.email),
            address=_blank_to_none(c.address),
            aadhaar_link_requested=c.aadhaar_link_requested,
        )
    if Role.SUPPLIER in body.roles:
        s = body.supplier
        user.supplier = SupplierProfile(
            qbox_id=Role.SUPPLIER.qbox_id(user.id),
            supplier_name=s.supplier_name.strip(),
            business_type=s.business_type,
            business_type_detail=_detail(s.business_type, s.business_type_detail),
            products_supplied=s.products_supplied.strip(),
            contact_number=s.contact_number,
            address=s.address.strip(),
        )
    db.commit()  # the account, its profiles and the used-up token are saved together, or not at all
    return AuthOut(access_token=create_access_token(user.id, user.token_version), user=to_me(user))


def login(db: Session, mobile: str, pin: str) -> AuthOut:
    settings = get_settings()
    user = _find_user(db, mobile, lock=True)
    if user is None:
        check_secret(pin, DUMMY_HASH)  # same wait as a real check, so unknown numbers are not revealed
        raise ApiError(401, "LOGIN_FAILED", WRONG_LOGIN)

    now = datetime.now(UTC)
    if user.locked_until is not None and user.locked_until > now:
        raise _locked(math.ceil((user.locked_until - now).total_seconds() / 60))

    if not check_secret(pin, user.pin_hash):
        user.failed_login_attempts += 1
        if user.failed_login_attempts % settings.login_max_failed_attempts == 0:
            first_lock = user.failed_login_attempts == settings.login_max_failed_attempts
            minutes = settings.login_lock_minutes if first_lock else settings.login_long_lock_minutes
            user.locked_until = now + timedelta(minutes=minutes)
            db.commit()
            raise _locked(minutes)
        db.commit()
        raise ApiError(401, "LOGIN_FAILED", WRONG_LOGIN)

    user.failed_login_attempts = 0
    user.locked_until = None
    db.commit()
    return AuthOut(access_token=create_access_token(user.id, user.token_version), user=to_me(user))


def reset_pin(db: Session, verification_token: str, new_pin: str) -> None:
    mobile, otp_id = read_verification(verification_token, OtpPurpose.RESET_PIN)
    user = _find_user(db, mobile, lock=True)
    if user is None:
        raise ApiError(404, "MOBILE_NOT_FOUND", NOT_FOUND)
    otp.use_verification(db, otp_id, mobile, OtpPurpose.RESET_PIN)
    user.pin_hash = hash_secret(new_pin)
    user.failed_login_attempts = 0
    user.locked_until = None
    user.token_version += 1  # logs out every phone that was logged in with the old PIN
    db.commit()


def _locked(minutes: int) -> ApiError:
    minutes = max(1, minutes)
    if minutes >= 120:
        wait = f"{math.ceil(minutes / 60)} hours"
    else:
        wait = "1 minute" if minutes == 1 else f"{minutes} minutes"
    return ApiError(423, "ACCOUNT_LOCKED", f"Too many wrong PINs. Try again in {wait} or reset your PIN")


def _check_role_details(body: RegisterIn) -> None:
    if Role.BUSINESS in body.roles:
        if body.shop is None:
            raise _invalid("Please fill in your shop details")
        _require_other_detail(body.shop.business_type, body.shop.business_type_detail, "Enter your business type")
        _require_other_detail(body.shop.shop_category, body.shop.shop_category_detail, "Enter your shop category")
    if Role.CUSTOMER in body.roles and body.customer is None:
        raise _invalid("Please fill in your customer details")
    if Role.SUPPLIER in body.roles:
        if body.supplier is None:
            raise _invalid("Please fill in your supplier details")
        _require_other_detail(body.supplier.business_type, body.supplier.business_type_detail,
                              "Enter your business type")


def _require_other_detail(choice: str, detail: str | None, message: str) -> None:
    if choice == OTHER and not (detail and detail.strip()):
        raise _invalid(message)


def _detail(choice: str, detail: str | None) -> str | None:
    """The typed-in detail is kept only when "Other" was chosen."""
    return _blank_to_none(detail) if choice == OTHER else None


def _blank_to_none(value: str | None) -> str | None:
    return value.strip() if value and value.strip() else None


def _invalid(message: str) -> ApiError:
    return ApiError(400, "INVALID_INPUT", message)
