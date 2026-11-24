"""What the payment APIs accept and return. Money is always whole paise (₹1 = 100)."""

import enum
import re
from datetime import date, datetime
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator

from app.auth.schemas import Mobile
from app.models import PaymentSource, PaymentStatus
from app.schemas import CamelModel
from app.udhaar.schemas import MAX_ENTRY_PAISE, ClientRef

Amount = Annotated[int, Field(ge=100, le=MAX_ENTRY_PAISE)]  # ₹1 to ₹10 lakh
Note = Annotated[str | None, Field(max_length=100)]


def _upi_id(value: str | None) -> str | None:
    value = (value or "").strip()
    if not value:
        return None
    if len(value) > 60 or not re.fullmatch(r"[A-Za-z0-9._-]{2,50}@[A-Za-z0-9]{2,30}", value):
        raise ValueError("Enter a UPI ID like shopname@okaxis")
    return value


def _clean_name(value: str | None) -> str | None:
    value = " ".join((value or "").split())
    return value[:60] or None


class UpiIn(CamelModel):
    """The shop's own UPI ID (empty = remove it) and the name UPI apps show."""

    upi_id: Annotated[str | None, AfterValidator(_upi_id)] = None
    upi_name: Annotated[str | None, Field(max_length=60), AfterValidator(_clean_name)] = None


class RazorpayKeysIn(CamelModel):
    key_id: str
    key_secret: str

    @field_validator("key_id")
    @classmethod
    def _key_id(cls, value: str) -> str:
        value = value.strip()
        if not re.fullmatch(r"rzp_(test|live)_[A-Za-z0-9]{8,30}", value):
            raise ValueError("The Key ID starts with rzp_test_ or rzp_live_. Copy it again from Razorpay")
        return value

    @field_validator("key_secret")
    @classmethod
    def _key_secret(cls, value: str) -> str:
        value = value.strip()
        if not re.fullmatch(r"[A-Za-z0-9]{12,64}", value):
            raise ValueError("The Key Secret does not look right. Copy it again from Razorpay")
        return value


class PaymentSettingsOut(CamelModel):
    upi_id: str | None
    upi_name: str | None
    # The shop's own Razorpay account is connected.
    razorpay_connected: bool
    razorpay_key_hint: str | None  # rzp_test_••••1234
    # Payments are confirmed by themselves (Razorpay), with "₹250 received".
    automatic: bool
    # Pretend money only (Razorpay test keys).
    test_mode: bool
    # Using QBOX's test account on the development PC (the shop has not connected its own).
    using_test_account: bool


class CollectIn(CamelModel):
    amount_paise: Amount
    note: Note = None
    # Collecting udhaar from this customer: a PAYMENT entry is added once paid.
    udhaar_customer_id: int | None = None
    client_ref: ClientRef


class PaymentOut(CamelModel):
    id: int
    source: PaymentSource
    status: PaymentStatus
    amount_paise: int
    note: str | None
    udhaar_customer_id: int | None
    # The udhaar customer's name, or the customer who paid (Pay to Shop).
    customer_name: str | None
    payer_vpa: str | None
    method: str | None
    # A Razorpay QR picture (QR Codes) or a payment page to show as a QR (Payment Links).
    qr_image_url: str | None
    pay_url: str | None
    test_mode: bool
    expires_at: datetime | None
    paid_at: datetime | None
    # UPI (Pay to Shop): when the customer said they paid; the shop confirms.
    claimed_at: datetime | None = None
    created_at: datetime


class PaymentsDayOut(CamelModel):
    day: date
    total_paise: int
    count: int
    payments: list[PaymentOut]  # paid that day, newest first
    # UPI payments customers say they made, waiting for the shop's answer.
    to_confirm: list[PaymentOut] = []


class UdhaarPayIn(CamelModel):
    amount_paise: Amount
    client_ref: ClientRef


class UdhaarPayOut(CamelModel):
    """Everything the app needs to open Razorpay's payment screen."""

    payment: PaymentOut
    key_id: str  # Razorpay's public key (the secret never leaves the server)
    order_id: str
    shop_name: str
    contact: str


class VerifyIn(CamelModel):
    """What Razorpay's payment screen returned to the app."""

    razorpay_payment_id: Annotated[str, Field(min_length=5, max_length=40)]
    razorpay_order_id: Annotated[str, Field(min_length=5, max_length=40)]
    razorpay_signature: Annotated[str, Field(min_length=10, max_length=200)]


class PayMethodChoice(str, enum.Enum):
    ONLINE = "ONLINE"  # Razorpay's payment screen, confirmed by itself
    UPI = "UPI"  # the shop's own UPI ID, confirmed by the shop


class FindShopIn(CamelModel):
    mobile: Mobile


class ScanShopIn(CamelModel):
    code: Annotated[str, Field(pattern=r"^[a-z2-7]{16}$")]


class ShopQrOut(CamelModel):
    shop_name: str
    data: str  # what the QR holds
    works_in_upi_apps: bool  # the shop has a UPI ID, so PhonePe / GPay can read it too


class PayShopOut(CamelModel):
    """A shop the customer can pay."""

    ref: str  # sent back when paying
    shop_name: str
    shop_category: str | None
    shop_photo: str | None
    book_id: int | None
    due_paise: int  # udhaar owed there (paid separately)
    online: bool
    test_mode: bool  # online payments are pretend money
    upi: bool


class UnfinishedOut(CamelModel):
    payment: PaymentOut
    shop_name: str


class PayShopsOut(CamelModel):
    shops: list[PayShopOut]
    unfinished: list[UnfinishedOut]  # opened a UPI app, "did you pay?" not answered


class ShopPayIn(CamelModel):
    ref: Annotated[str, Field(pattern=r"^((book|paid):[0-9]{1,15}|mobile:[6-9][0-9]{9}|code:[a-z2-7]{16})$")]
    amount_paise: Amount
    note: Note = None
    method: PayMethodChoice
    client_ref: ClientRef


class ShopPayOut(CamelModel):
    """Everything the app needs to open Razorpay's screen, or a UPI app."""

    payment: PaymentOut
    shop_name: str
    contact: str
    key_id: str | None
    order_id: str | None
    upi_id: str | None
    upi_name: str | None
