from app.models import Role, User
from app.users.schemas import CustomerOut, MeOut, ShopOut, SupplierOut

_ROLE_ORDER = [Role.BUSINESS, Role.CUSTOMER, Role.SUPPLIER]


def to_me(user: User) -> MeOut:
    """What the app may see about a user. The PIN hash and lock details never leave the server."""
    held = {r.role for r in user.roles}
    return MeOut(
        id=user.id,
        mobile=user.mobile,
        roles=[role for role in _ROLE_ORDER if role.value in held],
        shop=ShopOut.model_validate(user.shop, from_attributes=True) if user.shop else None,
        customer=CustomerOut.model_validate(user.customer, from_attributes=True) if user.customer else None,
        supplier=SupplierOut.model_validate(user.supplier, from_attributes=True) if user.supplier else None,
    )
