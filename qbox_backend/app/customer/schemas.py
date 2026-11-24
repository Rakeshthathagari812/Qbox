"""What the customer's history, expenses, lists and notes accept and return.
Money is whole paise (₹1 = 100)."""

import enum
from datetime import UTC, datetime, timedelta
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator, model_validator

from app.auth.schemas import needs
from app.models import EntryKind, ExpenseCategory, PageKind
from app.schemas import CamelModel
from app.udhaar.schemas import INDIA, MAX_ENTRY_PAISE, ClientRef

MAX_BUDGET_PAISE = 1_000_000_000  # ₹1 crore a month


class TransactionStatus(str, enum.Enum):
    PAID = "PAID"  # done (also every udhaar line)
    WAITING = "WAITING"  # paid by UPI, the shop has not confirmed yet
    NOT_CONFIRMED = "NOT_CONFIRMED"  # the shop says the UPI money did not come (or never answered)


class TransactionOut(CamelModel):
    # "entry-12" (a line in a shop's udhaar book), "payment-5" (a payment this
    # customer made that is not in any book they can see), or "own-7" (added by them).
    id: str
    # CREDIT = took udhaar, PAYMENT = paid.
    kind: EntryKind
    amount_paise: int
    at: datetime
    # Same for everything at one shop ("own" for what they added); the app's filter.
    shop_key: str
    shop_name: str
    book_id: int | None
    note: str | None
    # Paid by this customer from QBOX (real money moved, even if the shop later
    # deletes the line from its book).
    online: bool
    test_mode: bool
    status: TransactionStatus
    # The shop deleted this line from its book.
    deleted_at: datetime | None
    delete_reason: str | None
    # Added by the customer: QBOX cannot confirm it.
    own: bool = False
    scanned: bool = False
    upi_id: str | None = None
    # They said it is not the same payment as another one of that day.
    not_same: bool = False
    # They said it is: shown, but not counted.
    same: bool = False
    # Expenses (payments only; udhaar taken is counted when it is paid).
    category: ExpenseCategory | None = None
    hidden: bool = False  # left out of Expenses by the customer


class TransactionsOut(CamelModel):
    month: str  # "2026-11" (India time)
    months: list[str]  # months that have something, newest first
    transactions: list[TransactionOut]  # newest first
    budget_paise: int | None  # for a month


def _clean(value: str | None) -> str | None:
    return " ".join((value or "").split()) or None


class RecordIn(CamelModel):
    title: Annotated[str, Field(max_length=80), needs("Enter a name, like Tea stall"), AfterValidator(lambda v: _clean(v))]
    amount_paise: Annotated[int, Field(ge=100, le=MAX_ENTRY_PAISE)]
    category: ExpenseCategory
    spent_at: datetime
    note: Annotated[str | None, Field(max_length=200), AfterValidator(_clean)] = None
    # Paid in a UPI app after scanning a QR in QBOX.
    scanned: bool = False
    upi_id: Annotated[str | None, Field(max_length=330), AfterValidator(_clean)] = None
    client_ref: ClientRef

    @field_validator("spent_at")
    @classmethod
    def sensible_time(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            value = value.replace(tzinfo=INDIA)
        if value.year < 2000:
            raise ValueError("Choose a date after the year 2000")
        if value > datetime.now(UTC) + timedelta(days=1):
            raise ValueError("The date cannot be in the future")
        return value


class MarkIn(CamelModel):
    """The customer's choice about an expense."""

    category: ExpenseCategory | None = None  # empty = the usual one for that shop
    hidden: bool = False


class BudgetIn(CamelModel):
    month_paise: Annotated[int | None, Field(ge=100, le=MAX_BUDGET_PAISE)] = None  # empty = no budget


class BudgetOut(CamelModel):
    month_paise: int | None


# ---------- checklist & notes ----------

MAX_PAGE_ITEMS = 200
MAX_NOTE_CHARS = 10_000


def _one_line(value: str) -> str:
    return " ".join(value.replace("\x00", "").split())


class PageItem(CamelModel):
    ref: ClientRef
    text: Annotated[str, Field(max_length=120), AfterValidator(_one_line), needs("An item is empty")]
    qty: Annotated[str, Field(max_length=30), AfterValidator(_one_line)] = ""  # "2 kg"
    done: bool = False


class PageIn(CamelModel):
    kind: PageKind
    title: Annotated[str, Field(max_length=80), AfterValidator(_one_line)] = ""
    text: Annotated[str, Field(max_length=MAX_NOTE_CHARS), AfterValidator(lambda v: v.replace("\x00", ""))] = ""
    items: Annotated[list[PageItem], Field(max_length=MAX_PAGE_ITEMS)] = []
    pinned: bool = False
    base_version: Annotated[int, Field(ge=0)]  # 0 = new
    save_ref: ClientRef

    @model_validator(mode="after")
    def fits_its_kind(self):
        if self.kind is PageKind.LIST:
            if not self.title:
                raise ValueError("Enter a name for the list")
            if self.text:
                raise ValueError("A list has items, not text")
        else:
            if self.items:
                raise ValueError("A note has text, not items")
            if not self.title and not self.text.strip():
                raise ValueError("The note is empty")
        if len({i.ref for i in self.items}) != len(self.items):
            raise ValueError("Some details are missing or invalid")
        return self


class PageOut(CamelModel):
    ref: str
    kind: PageKind
    title: str
    text: str
    items: list[PageItem]
    pinned: bool
    version: int
    save_ref: str
    updated_at: datetime


class PagesOut(CamelModel):
    pages: list[PageOut]  # last changed first
