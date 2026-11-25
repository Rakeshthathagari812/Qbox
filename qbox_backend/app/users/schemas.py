"""What the app receives and may change about the logged-in user."""

import re
from typing import Annotated

from pydantic import AfterValidator, Field

from app.models import Role
from app.schemas import CamelModel


class ShopOut(CamelModel):
    qbox_id: str
    shop_name: str
    business_type: str
    business_type_detail: str | None
    shop_category: str
    shop_category_detail: str | None
    address: str
    contact_number: str
    photo: str | None = None  # its ref


class CustomerOut(CamelModel):
    qbox_id: str
    full_name: str
    mobile_number: str
    email: str | None
    address: str | None
    aadhaar_link_requested: bool
    photo: str | None = None


class SupplierOut(CamelModel):
    qbox_id: str
    supplier_name: str
    business_type: str
    business_type_detail: str | None
    products_supplied: str
    contact_number: str
    address: str
    photo: str | None = None


class MeOut(CamelModel):
    id: int
    mobile: str
    roles: list[Role]
    shop: ShopOut | None
    customer: CustomerOut | None
    supplier: SupplierOut | None


def _email(value: str | None) -> str | None:
    if value and value.strip() and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value.strip()):
        raise ValueError("Enter a valid email")
    return value


def _name(value: str) -> str:
    if not value.strip():
        raise ValueError("Enter your name")
    return value


Email = Annotated[str | None, Field(max_length=160), AfterValidator(_email)]


class CustomerEditIn(CamelModel):
    full_name: Annotated[str, Field(max_length=120), AfterValidator(_name)]
    email: Email = None
    address: Annotated[str | None, Field(max_length=300)] = None


class PhotoIn(CamelModel):
    jpeg: Annotated[str, Field(max_length=420_000)]  # base64


class PhotoOut(CamelModel):
    jpeg: str


class DeleteCheckOut(CamelModel):
    """Before deleting the account: what is still open."""

    you_owe_paise: int
    owed_to_you_paise: int
    payments_open: bool  # must be finished first


def _pin(value: str) -> str:
    if not re.fullmatch(r"[0-9]{4}", value):
        raise ValueError("Enter a 4-digit PIN")
    return value


class DeleteAccountIn(CamelModel):
    pin: Annotated[str, AfterValidator(_pin)]


class TokenOut(CamelModel):
    access_token: str
