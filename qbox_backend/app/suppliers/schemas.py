"""What the supplier APIs accept and return. Money is whole paise (₹1 = 100);
quantities are thousandths of the item's unit (1.5 kg = 1500)."""

import re
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator, model_validator

from app.auth.schemas import Mobile, Otp, needs
from app.models import Confirm, LinkStatus, OrderStatus, PayMethod, PayPlan, StockUnit, SupplierEntryKind
from app.schemas import CamelModel
from app.stock.schemas import MAX_PRICE_PAISE, MAX_QTY_MILLI, catalog_code_ok
from app.udhaar.schemas import INDIA, MAX_ENTRY_PAISE, ClientRef


def _mobile(value: str | None) -> str | None:
    digits = re.sub(r"[^0-9]", "", value or "")
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    if not digits:
        return None
    if not re.fullmatch(r"[6-9][0-9]{9}", digits):
        raise ValueError("Enter a valid 10-digit mobile number")
    return digits


def _clean(value: str | None) -> str | None:
    value = " ".join((value or "").split())
    return value or None


SupplierName = Annotated[str, Field(max_length=80), needs("Enter the supplier's name"),
                         AfterValidator(lambda v: " ".join(v.split()))]
OptionalMobile = Annotated[str | None, AfterValidator(_mobile)]
Amount = Annotated[int, Field(ge=1, le=MAX_ENTRY_PAISE)]
Note = Annotated[str | None, Field(max_length=200), AfterValidator(_clean)]


class SupplierIn(CamelModel):
    name: SupplierName
    mobile: OptionalMobile = None
    supplies: Annotated[str | None, Field(max_length=200), AfterValidator(_clean)] = None
    note: Annotated[str | None, Field(max_length=300), AfterValidator(_clean)] = None
    # The code the supplier read out (empty = added without connecting).
    otp: Otp | None = None
    client_ref: ClientRef


class SupplierCodeIn(CamelModel):
    """Adding a supplier, step 1: a code goes to their phone."""

    name: SupplierName
    mobile: Mobile


class SupplierCodeOut(CamelModel):
    mobile: str
    # What the message says the shop owes (negative = paid in advance).
    balance_paise: int
    expires_in_seconds: int
    resend_in_seconds: int
    dev_otp: str | None = None  # test mode only


class SupplierVerifyIn(CamelModel):
    otp: Otp


class SupplierChangeIn(CamelModel):
    name: SupplierName
    mobile: OptionalMobile = None
    supplies: Annotated[str | None, Field(max_length=200), AfterValidator(_clean)] = None
    note: Annotated[str | None, Field(max_length=300), AfterValidator(_clean)] = None


class NamedLine(CamelModel):
    """One item: a stock item, or a name and unit (which finds the shop's own
    item, or becomes a new one when the goods come)."""

    item_id: int | None = None
    name: Annotated[str | None, Field(max_length=80), AfterValidator(_clean)] = None
    unit: StockUnit | None = None
    catalog_code: Annotated[str | None, AfterValidator(catalog_code_ok)] = None
    qty_milli: int = Field(ge=1, le=MAX_QTY_MILLI)

    def chosen(self) -> list:
        return [self.item_id, self.name]

    def key(self) -> tuple:
        return *[str(v).lower() for v in self.chosen()], self.unit

    @model_validator(mode="after")
    def _one(self) -> "NamedLine":
        if sum(v is not None for v in self.chosen()) != 1 or (self.name is None) != (self.unit is None):
            raise ValueError("Some details are missing or invalid")
        return self


class LineIn(NamedLine):
    """One item bought."""

    cost_paise: Annotated[int | None, Field(ge=0, le=MAX_PRICE_PAISE)] = None  # per unit


def sensible_time(value: datetime) -> datetime:
    if value.tzinfo is None:
        value = value.replace(tzinfo=INDIA)
    if value.year < 2000:
        raise ValueError("Choose a date after the year 2000")
    if value > datetime.now(UTC) + timedelta(days=1):
        raise ValueError("The date cannot be in the future")
    return value


class EntryIn(CamelModel):
    kind: SupplierEntryKind
    amount_paise: Amount
    note: Note = None
    entry_at: datetime
    # Purchases on credit: pay by this date (a reminder rings on the phone).
    due_date: date | None = None
    # Payments (and purchases paid on the spot): how it was paid.
    method: PayMethod | None = None
    # A purchase paid on the spot: a payment of the same amount is added too.
    paid_now: bool = False
    # Purchases: the items bought; each is added to stock.
    lines: Annotated[list[LineIn], Field(max_length=100)] = []
    # Payments: the order it pays for.
    order_id: int | None = None
    client_ref: ClientRef

    @field_validator("entry_at")
    @classmethod
    def _time(cls, value: datetime) -> datetime:
        return sensible_time(value)

    @model_validator(mode="after")
    def _rules(self) -> "EntryIn":
        if self.kind == SupplierEntryKind.PAYMENT:
            if self.lines or self.paid_now or self.due_date:
                raise ValueError("A payment has no items or due date")
        elif self.order_id is not None:
            raise ValueError("Some details are missing or invalid")
        if self.due_date and self.paid_now:
            raise ValueError("A purchase paid now has no due date")
        if len({line.key() for line in self.lines}) != len(self.lines):
            raise ValueError("Each item can be added once")
        return self


class DeleteIn(CamelModel):
    reason: Annotated[str, Field(max_length=200), needs("Write why this entry is being deleted")]


class OrderLineIn(NamedLine):
    """One item ordered: also from the supplier's products."""

    product_id: int | None = None

    def chosen(self) -> list:
        return [self.item_id, self.name, self.product_id]


class ReceiveLineIn(LineIn):
    """One item that came: also a line of the order."""

    order_line_id: int | None = None

    def chosen(self) -> list:
        return [self.item_id, self.name, self.order_line_id]


class OrderIn(CamelModel):
    lines: Annotated[list[OrderLineIn], Field(min_length=1, max_length=100)]
    note: Note = None
    # To a connected supplier: how it will be paid.
    pay_plan: PayPlan | None = None
    pay_by: date | None = None
    client_ref: ClientRef

    @model_validator(mode="after")
    def _rules(self) -> "OrderIn":
        if self.pay_by and self.pay_plan != PayPlan.LATER:
            raise ValueError("Only an order paid later has a date")
        if len({line.key() for line in self.lines}) != len(self.lines):
            raise ValueError("Each item can be added once")
        return self


class ReceiveIn(CamelModel):
    """The goods of an order came: recorded as a purchase (stock goes up)."""

    amount_paise: Amount
    lines: Annotated[list[ReceiveLineIn], Field(max_length=100)]  # what actually came
    paid_now: bool = False
    method: PayMethod | None = None
    due_date: date | None = None
    note: Note = None
    client_ref: ClientRef


class LineOut(CamelModel):
    id: int
    item_id: int | None
    product_id: int | None = None  # orders: from the supplier's products
    name: str
    unit: StockUnit
    qty_milli: int
    cost_paise: int | None = None
    available: bool = True  # orders: the supplier has it


class EntryOut(CamelModel):
    id: int
    supplier_id: int
    kind: SupplierEntryKind
    amount_paise: int
    note: str | None
    entry_at: datetime
    due_date: date | None
    method: PayMethod | None
    order_id: int | None
    lines: list[LineOut]
    client_ref: str
    by_supplier: bool  # the supplier wrote it: the shop answers
    # Shared with a connected supplier: the other side's answer. Empty = not shared.
    confirm: Confirm | None
    dispute_reason: str | None
    deleted_at: datetime | None
    delete_reason: str | None


class OrderOut(CamelModel):
    id: int
    supplier_id: int
    status: OrderStatus
    note: str | None
    lines: list[LineOut]
    created_at: datetime
    received_at: datetime | None
    # Sent in QBOX to a connected supplier, and their answer.
    shared: bool
    total_paise: int | None
    answer_note: str | None
    pay_plan: PayPlan | None
    pay_by: date | None
    paid_paise: int  # counted
    paying_paise: int  # waiting for the supplier to confirm


class SupplierLinkOut(CamelModel):
    """This supplier's connection with their QBOX account (the newest one)."""

    status: LinkStatus
    reason: str | None  # why they said no
    since: datetime


class SupplierOut(CamelModel):
    id: int
    name: str
    mobile: str | None
    supplies: str | None
    note: str | None
    # Positive = the shop owes the supplier. Negative = paid in advance.
    balance_paise: int
    last_entry_at: datetime | None
    # The earliest pay-by date of purchases not yet paid off (payments cover the oldest first).
    next_due: date | None
    overdue: bool
    open_orders: int
    verified: bool  # the number was checked with a code
    takes_upi: bool  # connected, and they added a UPI ID
    to_confirm: int  # entries they wrote, waiting for the shop
    link: SupplierLinkOut | None


class SupplierProductOut(CamelModel):
    """Something a connected supplier sells."""

    id: int
    name: str
    catalog_code: str | None
    unit: StockUnit
    price_paise: int | None
    available: bool


class SupplierPayOut(CamelModel):
    """Where a connected supplier takes money."""

    name: str
    upi_id: str | None


class SuppliersOut(CamelModel):
    total_due_paise: int
    suppliers: list[SupplierOut]


class SupplierDetailOut(CamelModel):
    supplier: SupplierOut
    entries: list[EntryOut]  # newest first, deleted ones included (crossed out in the app)
    orders: list[OrderOut]  # newest first
