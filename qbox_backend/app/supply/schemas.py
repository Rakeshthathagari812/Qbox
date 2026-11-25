"""What the supplier-side APIs accept and return. Money is whole paise (₹1 = 100);
quantities are thousandths of the item's unit (1.5 kg = 1500)."""

import enum
from datetime import date, datetime
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator, model_validator

from app.auth.schemas import needs
from app.models import Confirm, OrderStatus, PayMethod, PayPlan, StockMoveKind, StockUnit, SupplierEntryKind
from app.schemas import CamelModel
from app.stock.schemas import MAX_PRICE_PAISE, MAX_QTY_MILLI, Alert, ItemName, Price, catalog_code_ok
from app.suppliers.schemas import Amount, Note, sensible_time
from app.udhaar.schemas import ClientRef


class ShopOut(CamelModel):
    """A shop, as its supplier sees it."""

    link_id: int
    shop_name: str
    shop_category: str | None
    shop_address: str | None
    shop_phone: str | None
    shop_photo: str | None


class RequestOut(ShopOut):
    """A shop asking to connect. [balance_paise] = what it says it owes now."""

    balance_paise: int
    asked_at: datetime


class SupplyShopOut(ShopOut):
    connected: bool  # false = disconnected: the account stays readable
    connected_at: datetime
    ended_at: datetime | None
    opening_paise: int
    # Positive = the shop owes this supplier. A payment counts once confirmed.
    balance_paise: int
    last_entry_at: datetime | None
    to_confirm: int
    open_orders: int


class SupplyHomeOut(CamelModel):
    total_due_paise: int
    requests: list[RequestOut]
    shops: list[SupplyShopOut]


class SupplyLineOut(CamelModel):
    id: int
    name: str
    unit: StockUnit
    qty_milli: int
    cost_paise: int | None
    available: bool = True
    have_milli: int | None = None  # orders to answer: what the supplier has, if counted


class SupplyEntryOut(CamelModel):
    id: int
    kind: SupplierEntryKind
    amount_paise: int
    note: str | None
    entry_at: datetime
    due_date: date | None
    method: PayMethod | None
    order_id: int | None
    lines: list[SupplyLineOut]
    by_supplier: bool  # written by the supplier: the shop answers
    confirm: Confirm
    dispute_reason: str | None
    deleted_at: datetime | None
    delete_reason: str | None


class SupplyOrderOut(CamelModel):
    id: int
    link_id: int
    shop_name: str
    shop_phone: str | None
    status: OrderStatus
    note: str | None
    lines: list[SupplyLineOut]
    total_paise: int | None
    answer_note: str | None
    created_at: datetime
    answered_at: datetime | None
    dispatched_at: datetime | None
    received_at: datetime | None
    # Still connected: it can be answered.
    connected: bool
    pay_plan: PayPlan | None  # how the shop will pay
    pay_by: date | None
    paid_paise: int  # confirmed
    paying_paise: int  # the shop says it paid; to be confirmed


class SupplyShopDetailOut(CamelModel):
    shop: SupplyShopOut
    entries: list[SupplyEntryOut]  # newest first, deleted ones included
    orders: list[SupplyOrderOut]


class SupplyPaymentOut(SupplyEntryOut):
    """A payment from one of the shops."""

    link_id: int
    shop_name: str
    connected: bool  # it can still be answered


class SupplyPaymentsOut(CamelModel):
    upi_id: str | None
    upi_name: str | None
    to_get_paise: int
    received_month_paise: int  # confirmed, this month
    payments: list[SupplyPaymentOut]  # newest first


class AcceptShopIn(CamelModel):
    """Yes, and the amount they were shown."""

    balance_paise: int


class GivenLineIn(CamelModel):
    """One item given to a shop."""

    name: ItemName
    unit: StockUnit
    catalog_code: Annotated[str | None, AfterValidator(catalog_code_ok)] = None
    qty_milli: int = Field(ge=1, le=MAX_QTY_MILLI)
    cost_paise: Price = None  # per unit


class SupplyEntryIn(CamelModel):
    """Goods given, or money received, written by the supplier."""

    kind: SupplierEntryKind
    amount_paise: Amount
    note: Note = None
    entry_at: datetime
    method: PayMethod | None = None  # payments
    lines: Annotated[list[GivenLineIn], Field(max_length=100)] = []  # goods
    client_ref: ClientRef

    @field_validator("entry_at")
    @classmethod
    def _time(cls, value: datetime) -> datetime:
        return sensible_time(value)

    @model_validator(mode="after")
    def _rules(self) -> "SupplyEntryIn":
        if self.kind == SupplierEntryKind.PAYMENT and self.lines:
            raise ValueError("A payment has no items")
        if len({(x.name.lower(), x.unit) for x in self.lines}) != len(self.lines):
            raise ValueError("Each item can be added once")
        return self


class ReasonIn(CamelModel):
    reason: Annotated[str, Field(max_length=200), needs("Write why")]


class OptionalReasonIn(CamelModel):
    reason: Note = None


class AnswerLineIn(CamelModel):
    id: int
    available: bool = True
    cost_paise: Annotated[int | None, Field(ge=0, le=MAX_PRICE_PAISE)] = None  # per unit


class AcceptOrderIn(CamelModel):
    lines: Annotated[list[AnswerLineIn], Field(max_length=100)]
    total_paise: Amount
    note: Note = None


# ---------- products ----------


class ProductChangeIn(CamelModel):
    name: ItemName
    price_paise: Price = None  # per unit
    available: bool = True


class ProductIn(ProductChangeIn):
    unit: StockUnit
    catalog_code: Annotated[str | None, AfterValidator(catalog_code_ok)] = None
    client_ref: ClientRef


class ProductsIn(CamelModel):
    products: Annotated[list[ProductIn], Field(min_length=1, max_length=200)]


class ProductOut(CamelModel):
    id: int
    name: str
    catalog_code: str | None
    unit: StockUnit
    price_paise: int | None
    available: bool
    # The supplier's own count (only they see it).
    counted: bool
    quantity_milli: int
    alert_milli: int | None
    low: bool


# ---------- the supplier's own stock ----------


class CountKind(str, enum.Enum):
    IN = "IN"
    OUT = "OUT"
    COUNT = "COUNT"  # "there is this much now"


class ProductMoveIn(CamelModel):
    kind: CountKind
    qty_milli: int = Field(ge=0, le=MAX_QTY_MILLI)
    note: Note = None
    client_ref: ClientRef

    @model_validator(mode="after")
    def _some(self) -> "ProductMoveIn":
        if self.qty_milli == 0 and self.kind != CountKind.COUNT:
            raise ValueError("Enter a quantity")
        return self


class ProductMoveOut(CamelModel):
    id: int
    kind: StockMoveKind
    qty_milli: int  # ADJUST: the change, + or -
    note: str | None
    move_at: datetime


class ProductStockIn(CamelModel):
    counted: bool
    alert_milli: Alert = None


class ProductStockOut(CamelModel):
    product: ProductOut
    moves: list[ProductMoveOut]  # newest first


# ---------- reports ----------


class ReportShopOut(CamelModel):
    shop_name: str
    given_paise: int
    received_paise: int
    to_get_paise: int  # now
    connected: bool


class ReportProductOut(CamelModel):
    name: str
    unit: StockUnit
    qty_milli: int
    amount_paise: int | None  # empty = no prices written


class ReportOut(CamelModel):
    """Between two days, both included. [to_get_paise] is now."""

    given_paise: int
    received_paise: int
    waiting_paise: int  # payments the supplier has not answered
    to_get_paise: int
    orders: dict[OrderStatus, int]
    shops: list[ReportShopOut]
    products: list[ReportProductOut]
