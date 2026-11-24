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


TYPES = {
    Role.CUSTOMER: [NoticeType.UDHAAR, NoticeType.PAYMENT, NoticeType.BUDGET],
    Role.BUSINESS: [NoticeType.PAYMENT, NoticeType.CUSTOMER, NoticeType.STOCK, NoticeType.SUPPLIER],
    Role.SUPPLIER: [],
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
