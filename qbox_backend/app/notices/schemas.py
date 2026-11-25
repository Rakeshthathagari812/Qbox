"""What the bell shows. The app writes the words (from the kind), so they can be
shown in other languages later."""

import enum
from datetime import datetime
from typing import Annotated

from pydantic import Field

from app.models import Role
from app.schemas import CamelModel


class NoticeType(str, enum.Enum):
    """What can be switched off."""

    UDHAAR = "UDHAAR"
    PAYMENT = "PAYMENT"
    BUDGET = "BUDGET"
    CUSTOMER = "CUSTOMER"
    STOCK = "STOCK"
    SUPPLIER = "SUPPLIER"
    ORDER = "ORDER"
    LEDGER = "LEDGER"


TYPES = {
    Role.CUSTOMER: [NoticeType.UDHAAR, NoticeType.PAYMENT, NoticeType.BUDGET],
    Role.BUSINESS: [NoticeType.PAYMENT, NoticeType.CUSTOMER, NoticeType.STOCK, NoticeType.SUPPLIER],
    Role.SUPPLIER: [NoticeType.ORDER, NoticeType.LEDGER, NoticeType.STOCK],
}


class NoticeKind(str, enum.Enum):
    # Customer. name = the shop.
    ADDED = "ADDED"  # added to its udhaar book
    CREDIT = "CREDIT"  # wrote udhaar
    RECORDED = "RECORDED"  # wrote a payment
    DELETED = "DELETED"  # deleted a line (note = why)
    NUMBER_KEPT = "NUMBER_KEPT"  # "this is not me": the shop says it is
    NUMBER_REMOVED = "NUMBER_REMOVED"  # ... the shop agrees
    RECEIVED = "RECEIVED"  # a UPI payment: the shop got it
    NOT_RECEIVED = "NOT_RECEIVED"
    BUDGET_NEAR = "BUDGET_NEAR"  # 80% spent; amount = spent so far
    BUDGET_OVER = "BUDGET_OVER"
    # Shop. name = the customer, item or supplier.
    PAID_ONLINE = "PAID_ONLINE"
    SAYS_PAID = "SAYS_PAID"  # by UPI: the shop must check
    NOT_ME = "NOT_ME"  # "this is not my number": the shop must check
    LOW_STOCK = "LOW_STOCK"  # note = what is left, "2000 KG" (thousandths and the unit)
    SUPPLIER_DUE = "SUPPLIER_DUE"  # today or earlier; amount = owed
    # Shop, about a connected supplier (name).
    CONNECTED = "CONNECTED"
    NOT_CONNECTED = "NOT_CONNECTED"  # they said no (note = why)
    SUPPLIER_LEFT = "SUPPLIER_LEFT"
    ORDER_ACCEPTED = "ORDER_ACCEPTED"  # amount = their bill
    ORDER_REJECTED = "ORDER_REJECTED"
    ORDER_SENT = "ORDER_SENT"  # on the way
    MONEY_CONFIRMED = "MONEY_CONFIRMED"  # they got the payment
    NOT_RIGHT = "NOT_RIGHT"  # they say an entry is not right (note = why)
    THEY_GAVE = "THEY_GAVE"  # they wrote goods: the shop must check
    THEY_GOT = "THEY_GOT"  # they wrote a payment they got
    THEY_DELETED = "THEY_DELETED"  # ... and deleted one (note = why)
    # Supplier, about a connected shop (name).
    WANTS_TO_CONNECT = "WANTS_TO_CONNECT"
    SHOP_LEFT = "SHOP_LEFT"
    NEW_ORDER = "NEW_ORDER"
    ORDER_CANCELLED = "ORDER_CANCELLED"
    ORDER_RECEIVED = "ORDER_RECEIVED"
    CONFIRM_PURCHASE = "CONFIRM_PURCHASE"
    CONFIRM_PAYMENT = "CONFIRM_PAYMENT"
    ENTRY_DELETED = "ENTRY_DELETED"
    SHOP_AGREED = "SHOP_AGREED"  # confirmed what the supplier wrote
    SHOP_NOT_RIGHT = "SHOP_NOT_RIGHT"  # ... says it is not right (note = why)
    PRODUCT_LOW = "PRODUCT_LOW"  # their own count; note = what is left


class NoticeOut(CamelModel):
    id: str
    kind: NoticeKind
    type: NoticeType
    name: str
    amount_paise: int | None
    note: str | None
    test_mode: bool  # pretend money
    at: datetime
    unread: bool


class NoticesOut(CamelModel):
    unread: int
    off: list[NoticeType]
    notices: list[NoticeOut]  # newest first


class UnreadOut(CamelModel):
    unread: int


class ReadIn(CamelModel):
    role: Role
    id: Annotated[str | None, Field(max_length=60)] = None  # empty = all


class OffIn(CamelModel):
    role: Role
    off: list[NoticeType]
