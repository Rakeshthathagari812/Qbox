from sqlalchemy import select
from sqlalchemy.orm import object_session

from app.models import ProfilePhoto, Role, User
from app.users.schemas import CustomerOut, MeOut, ShopOut, SupplierOut

_ROLE_ORDER = [Role.BUSINESS, Role.CUSTOMER, Role.SUPPLIER]


def to_me(user: User) -> MeOut:
    """What the app may see about a user. The PIN hash and lock details never leave the server."""
    held = {r.role for r in user.roles}
    rows = object_session(user).execute(select(ProfilePhoto.role, ProfilePhoto.ref).where(ProfilePhoto.user_id == user.id))
    photos = {role: ref for role, ref in rows}
    return MeOut(
        id=user.id,
        mobile=user.mobile,
        roles=[role for role in _ROLE_ORDER if role.value in held],
        shop=_profile(ShopOut, user.shop, photos.get(Role.BUSINESS.value)),
        customer=_profile(CustomerOut, user.customer, photos.get(Role.CUSTOMER.value)),
        supplier=_profile(SupplierOut, user.supplier, photos.get(Role.SUPPLIER.value)),
    )


def _profile(kind, row, photo: str | None):
    return kind.model_validate(row, from_attributes=True).model_copy(update={"photo": photo}) if row else None
