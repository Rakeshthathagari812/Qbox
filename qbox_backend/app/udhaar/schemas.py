"""What the udhaar APIs accept and return. Money is always whole paise (₹1 = 100)."""

import re
from datetime import UTC, datetime, timedelta, timezone
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator

from app.auth.schemas import Mobile, Otp, needs
from app.models import Dispute, EntryKind
from app.schemas import CamelModel

MAX_ENTRY_PAISE = 100_000_000  # ₹10,00,000 in one entry
MAX_LIMIT_PAISE = 1_000_000_000  # ₹1 crore credit limit
INDIA = timezone(timedelta(hours=5, minutes=30))


def _client_ref(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9-]{8,40}", value or ""):
        raise ValueError("Some details are missing or invalid")
    return value


CustomerName = Annotated[str, Field(max_length=80), needs("Enter customer name")]
CreditLimit = Annotated[int | None, Field(ge=100, le=MAX_LIMIT_PAISE)]  # at least ₹1
ClientRef = Annotated[str, AfterValidator(_client_ref)]


class InviteIn(CamelModel):
    """Step 1 of adding a customer: send the OTP to their phone."""

    name: CustomerName
    mobile: Mobile


class InviteOut(CamelModel):
    mobile: str
    expires_in_seconds: int
    resend_in_seconds: int
    dev_otp: str | None = None  # test mode only


class AddCustomerIn(CamelModel):
    """Step 2: the code the customer read out, plus their details."""

    name: CustomerName
    mobile: Mobile
    otp: Otp
    credit_limit_paise: CreditLimit = None


class NumberInviteIn(CamelModel):
    """Change a customer's number, step 1: send a code to the new number."""

    mobile: Mobile


class ChangeNumberIn(CamelModel):
    """Step 2: the code the customer read out from the new number."""

    mobile: Mobile
    otp: Otp


class CustomerChangeIn(CamelModel):
    name: CustomerName
    credit_limit_paise: CreditLimit = None


class CustomerOut(CamelModel):
    id: int
    name: str
    mobile: str
    credit_limit_paise: int | None
    # Positive = the customer owes the shop. Negative = paid in advance.
    balance_paise: int
    last_entry_at: datetime | None
    # Since when the money has been pending (last payment, or first udhaar if
    # never paid). Empty when nothing is pending. Used for "overdue" alerts.
    owing_since: datetime | None
    # "This is not me" status, and when the customer reported it.
    dispute: Dispute
    disputed_at: datetime | None
    verified_at: datetime
    added_at: datetime


class BookOut(CamelModel):
    total_pending_paise: int
    customers: list[CustomerOut]


class EntryIn(CamelModel):
    kind: EntryKind
    amount_paise: int = Field(ge=1, le=MAX_ENTRY_PAISE)
    note: str | None = Field(default=None, max_length=200)
    entry_at: datetime
    client_ref: ClientRef

    @field_validator("entry_at")
    @classmethod
    def sensible_time(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            value = value.replace(tzinfo=INDIA)
        if value.year < 2000:
            raise ValueError("Choose a date after the year 2000")
        if value > datetime.now(UTC) + timedelta(days=1):
            raise ValueError("The date cannot be in the future")
        return value


class EntryOut(CamelModel):
    id: int
    customer_id: int
    kind: EntryKind
    amount_paise: int
    note: str | None
    entry_at: datetime
    client_ref: str
    deleted_at: datetime | None
    delete_reason: str | None


class DeleteEntryIn(CamelModel):
    reason: Annotated[str, Field(max_length=200), needs("Write why this entry is being deleted")]


class CustomerDetailOut(CamelModel):
    customer: CustomerOut
    entries: list[EntryOut]  # newest first, deleted ones included (crossed out in the app)


class MyBookOut(CamelModel):
    closed: bool = False  # the shop left QBOX: only to look at
    """One shop's udhaar book, as the customer sees it."""

    book_id: int
    shop_name: str
    shop_phone: str | None
    shop_category: str | None
    shop_address: str | None
    shop_photo: str | None
    balance_paise: int
    last_entry_at: datetime | None
    dispute: Dispute
    # When the customer's number was checked with a code at this shop.
    verified_at: datetime


class MyBookDetailOut(CamelModel):
    book: MyBookOut
    entries: list[EntryOut]
