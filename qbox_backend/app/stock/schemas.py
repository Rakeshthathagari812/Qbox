"""What the stock APIs accept and return.

Quantities are whole thousandths of the item's unit ("milli"): 1.5 kg = 1500,
3 pieces = 3000. Money is whole paise (₹1 = 100).
"""

import re
from datetime import UTC, datetime, timedelta
from typing import Annotated

from pydantic import AfterValidator, Field, field_validator, model_validator

from app.auth.schemas import needs
from app.models import StockMoveKind, StockUnit
from app.schemas import CamelModel
from app.udhaar.schemas import INDIA, ClientRef

MAX_QTY_MILLI = 1_000_000_000  # 10 lakh units
MAX_PRICE_PAISE = 100_000_000  # ₹10 lakh per unit


def _catalog_code(value: str | None) -> str | None:
    if value is None:
        return None
    if not re.fullmatch(r"[a-z0-9_]{1,40}", value):
        raise ValueError("Some details are missing or invalid")
    return value


def _clean(value: str | None) -> str | None:
    value = " ".join((value or "").split())
    return value or None


ItemName = Annotated[str, Field(max_length=80), needs("Enter the item name"), AfterValidator(lambda v: " ".join(v.split()))]
Price = Annotated[int | None, Field(ge=0, le=MAX_PRICE_PAISE)]
Alert = Annotated[int | None, Field(ge=0, le=MAX_QTY_MILLI)]
Note = Annotated[str | None, Field(max_length=200), AfterValidator(_clean)]


class ItemIn(CamelModel):
    name: ItemName
    unit: StockUnit
    catalog_code: Annotated[str | None, AfterValidator(_catalog_code)] = None
    opening_milli: int = Field(default=0, ge=0, le=MAX_QTY_MILLI)  # stock already in the shop
    cost_paise: Price = None
    price_paise: Price = None
    alert_milli: Alert = None
    client_ref: ClientRef


class ItemsIn(CamelModel):
    """Several items at once (quick start from the ready list)."""

    items: Annotated[list[ItemIn], Field(min_length=1, max_length=200)]


class ItemChangeIn(CamelModel):
    """The unit cannot change: the history is counted in it."""

    name: ItemName
    cost_paise: Price = None
    price_paise: Price = None
    alert_milli: Alert = None


class MoveIn(CamelModel):
    kind: StockMoveKind
    # IN / OUT: how much (always positive). ADJUST: the change, + or -.
    qty_milli: int
    note: Note = None
    move_at: datetime
    client_ref: ClientRef

    @field_validator("move_at")
    @classmethod
    def _sensible_time(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            value = value.replace(tzinfo=INDIA)
        if value.year < 2000:
            raise ValueError("Choose a date after the year 2000")
        if value > datetime.now(UTC) + timedelta(days=1):
            raise ValueError("The date cannot be in the future")
        return value

    @model_validator(mode="after")
    def _quantity(self) -> "MoveIn":
        if abs(self.qty_milli) > MAX_QTY_MILLI:
            raise ValueError("This quantity is too large")
        if self.kind == StockMoveKind.ADJUST:
            if self.qty_milli == 0:
                raise ValueError("The count is already this")
            if not self.note:
                raise ValueError("Write why the count changed (damaged, expired, counted wrong)")
        elif self.qty_milli <= 0:
            raise ValueError("Enter a quantity")
        return self


class ItemOut(CamelModel):
    id: int
    name: str
    catalog_code: str | None
    unit: StockUnit
    quantity_milli: int  # can be below 0 if sales were written before purchases
    cost_paise: int | None
    price_paise: int | None
    alert_milli: int | None
    low: bool  # at or below the alert level
    value_paise: int | None  # quantity x buying price (empty without a buying price)
    last_move_at: datetime | None
    created_at: datetime


class PastItemOut(CamelModel):
    """An item the shop had before and removed: offered again in "Your items"."""

    name: str
    unit: StockUnit
    catalog_code: str | None


class StockOut(CamelModel):
    items: list[ItemOut]
    total_value_paise: int
    low_count: int
    past_items: list[PastItemOut] = []


class MoveOut(CamelModel):
    id: int
    item_id: int
    kind: StockMoveKind
    qty_milli: int
    note: str | None
    move_at: datetime
    client_ref: str


class ItemDetailOut(CamelModel):
    item: ItemOut
    moves: list[MoveOut]  # newest first
