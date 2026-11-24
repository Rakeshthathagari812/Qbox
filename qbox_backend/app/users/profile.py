"""Changing one's own details and PIN, and logging out everywhere.
The login number and QBOX IDs never change here."""

from sqlalchemy.orm import Session

from app.auth import service as auth
from app.auth.schemas import AddRoleIn, ShopIn, SupplierIn
from app.errors import ApiError
from app.models import Role, User
from app.security import check_secret, create_access_token, hash_secret
from app.users.schemas import CustomerEditIn, TokenOut


def edit_shop(db: Session, user: User, body: ShopIn) -> None:
    shop = _held(user, Role.BUSINESS, user.shop)
    auth.require_other_detail(body.business_type, body.business_type_detail, "Enter your business type")
    auth.require_other_detail(body.shop_category, body.shop_category_detail, "Enter your shop category")
    shop.shop_name = body.shop_name.strip()
    shop.business_type = body.business_type
    shop.business_type_detail = auth.other_detail(body.business_type, body.business_type_detail)
    shop.shop_category = body.shop_category
    shop.shop_category_detail = auth.other_detail(body.shop_category, body.shop_category_detail)
    shop.address = body.address.strip()
    shop.contact_number = body.contact_number
    db.commit()


def edit_customer(db: Session, user: User, body: CustomerEditIn) -> None:
    customer = _held(user, Role.CUSTOMER, user.customer)
    customer.full_name = body.full_name.strip()
    customer.email = auth.blank_to_none(body.email)
    customer.address = auth.blank_to_none(body.address)
    db.commit()


def edit_supplier(db: Session, user: User, body: SupplierIn) -> None:
    supplier = _held(user, Role.SUPPLIER, user.supplier)
    auth.require_other_detail(body.business_type, body.business_type_detail, "Enter your business type")
    supplier.supplier_name = body.supplier_name.strip()
    supplier.business_type = body.business_type
    supplier.business_type_detail = auth.other_detail(body.business_type, body.business_type_detail)
    supplier.products_supplied = body.products_supplied.strip()
    supplier.contact_number = body.contact_number
    supplier.address = body.address.strip()
    db.commit()


def add_role(db: Session, user: User, body: AddRoleIn) -> None:
    """One more role for the same account (needs the PIN). Asking again for a role
    they have, e.g. a retry after a lost answer, changes nothing."""
    auth.check_role_details(body)
    db.refresh(user, with_for_update=True)
    auth.check_pin(db, user, body.pin, ApiError(400, "WRONG_PIN", "The PIN is not right"))
    if body.role.value not in {r.role for r in user.roles}:
        auth.give_roles(user, body)
    db.commit()


def change_pin(db: Session, user: User, old_pin: str, new_pin: str) -> TokenOut:
    """Wrong old PINs count like wrong logins, so a borrowed phone cannot be used
    to guess it. Every other phone is logged out; this one gets a new token."""
    db.refresh(user, with_for_update=True)
    auth.check_pin(db, user, old_pin, ApiError(400, "WRONG_PIN", "The old PIN is not right"))
    if check_secret(new_pin, user.pin_hash):
        raise ApiError(400, "SAME_PIN", "The new PIN is the same as the old one")
    user.pin_hash = hash_secret(new_pin)
    user.token_version += 1
    db.commit()
    return TokenOut(access_token=create_access_token(user.id, user.token_version))


def logout_all(db: Session, user: User) -> None:
    db.refresh(user, with_for_update=True)
    user.token_version += 1
    db.commit()


def _held(user: User, role: Role, profile):
    if profile is None or role.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")
    return profile
