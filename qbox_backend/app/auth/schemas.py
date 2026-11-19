"""The JSON bodies the auth APIs accept and return, with the checks
and the messages the app shows when something is wrong."""

import re
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator

from app.models import OtpPurpose, Role
from app.schemas import CamelModel
from app.users.schemas import MeOut

MOBILE_MESSAGE = "Enter a 10-digit mobile number"


def _matches(pattern: str, message: str) -> AfterValidator:
    def check(value: str) -> str:
        if not re.fullmatch(pattern, value or ""):
            raise ValueError(message)
        return value

    return AfterValidator(check)


def needs(message: str) -> AfterValidator:
    """The field must not be blank; [message] is shown when it is."""

    def check(value: str) -> str:
        if not value or not value.strip():
            raise ValueError(message)
        return value

    return AfterValidator(check)


def _not_easy_to_guess(pin: str) -> str:
    """Refuses repeats like 0000 or 7777 and runs like 1234 or 9876."""
    digits = [int(c) for c in pin]
    steps = {b - a for a, b in zip(digits, digits[1:])}
    if steps in ({0}, {1}, {-1}):
        raise ValueError("This PIN is too easy to guess. Choose a different PIN")
    return pin


# [0-9] rather than \d: in Python \d also matches other scripts' digits (like ९).
Mobile = Annotated[str, _matches(r"[6-9][0-9]{9}", MOBILE_MESSAGE)]
Pin = Annotated[str, _matches(r"[0-9]{4}", "Enter a 4-digit PIN")]
NewPin = Annotated[Pin, AfterValidator(_not_easy_to_guess)]
Otp = Annotated[str, _matches(r"[0-9]{6}", "Enter the 6-digit OTP")]
VerificationToken = Annotated[str, Field(max_length=2000), needs("Please verify your mobile number first")]
Optional120 = Annotated[str | None, Field(max_length=120)]


class SendOtpIn(CamelModel):
    mobile: Mobile
    purpose: OtpPurpose


class SendOtpOut(CamelModel):
    mobile: str
    expires_in_seconds: int
    resend_in_seconds: int
    # Filled only in test mode, so the app can show the code.
    dev_otp: str | None = None


class VerifyOtpIn(CamelModel):
    mobile: Mobile
    purpose: OtpPurpose
    otp: Otp


class VerifyOtpOut(CamelModel):
    verification_token: str
    expires_in_seconds: int


class ShopIn(CamelModel):
    shop_name: Annotated[str, Field(max_length=120), needs("Enter shop name")]
    business_type: Annotated[str, Field(max_length=60), needs("Select business type")]
    business_type_detail: Optional120 = None
    shop_category: Annotated[str, Field(max_length=60), needs("Select category")]
    shop_category_detail: Optional120 = None
    address: Annotated[str, Field(max_length=300), needs("Enter shop address")]
    contact_number: Mobile


class CustomerIn(CamelModel):
    full_name: Annotated[str, Field(max_length=120), needs("Enter your name")]
    mobile_number: Mobile
    email: str | None = Field(default=None, max_length=160)
    address: str | None = Field(default=None, max_length=300)
    aadhaar_link_requested: bool = False

    @field_validator("email")
    @classmethod
    def email_looks_valid(cls, value: str | None) -> str | None:
        if value and value.strip() and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value.strip()):
            raise ValueError("Enter a valid email")
        return value


class SupplierIn(CamelModel):
    supplier_name: Annotated[str, Field(max_length=120), needs("Enter supplier name")]
    business_type: Annotated[str, Field(max_length=60), needs("Select business type")]
    business_type_detail: Optional120 = None
    products_supplied: Annotated[str, Field(max_length=300), needs("Enter products supplied")]
    contact_number: Mobile
    address: Annotated[str, Field(max_length=300), needs("Enter address")]


class RegisterIn(CamelModel):
    verification_token: VerificationToken
    pin: NewPin
    roles: Annotated[set[Role], Field(min_length=1)]
    shop: ShopIn | None = None
    customer: CustomerIn | None = None
    supplier: SupplierIn | None = None


class LoginIn(CamelModel):
    mobile: Mobile
    pin: Pin


class ResetPinIn(CamelModel):
    verification_token: VerificationToken
    new_pin: NewPin


class AuthOut(CamelModel):
    access_token: str
    user: MeOut
