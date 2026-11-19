"""What the app receives about the logged-in user."""

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


class CustomerOut(CamelModel):
    qbox_id: str
    full_name: str
    mobile_number: str
    email: str | None
    address: str | None
    aadhaar_link_requested: bool


class SupplierOut(CamelModel):
    qbox_id: str
    supplier_name: str
    business_type: str
    business_type_detail: str | None
    products_supplied: str
    contact_number: str
    address: str


class MeOut(CamelModel):
    id: int
    mobile: str
    roles: list[Role]
    shop: ShopOut | None
    customer: CustomerOut | None
    supplier: SupplierOut | None
