"""What a supplier sells. Only the supplier changes it; only shops connected with
them see it (name, unit, price, available or not - never how much they have)."""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import case, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import Role, StockMoveKind, StockUnit, SupplyMove, SupplyProduct, User
from app.supply.schemas import ProductChangeIn, ProductIn, ProductOut

MAX_PRODUCTS = 2_000


@dataclass
class Left:
    quantity: int = 0
    last_move_at: datetime | None = None


NONE = Left()


def mine(db: Session, user: User) -> list[ProductOut]:
    _require(user)
    found = of_supplier(db, user.id)
    left = quantities(db, [p.id for p in found])
    return [out(p, left) for p in found]


def of_supplier(db: Session, supplier_user_id: int) -> list[SupplyProduct]:
    return list(db.scalars(
        select(SupplyProduct)
        .where(SupplyProduct.supplier_user_id == supplier_user_id, SupplyProduct.archived_at.is_(None))
        .order_by(func.lower(SupplyProduct.name), SupplyProduct.id)
    ))


def quantities(db: Session, product_ids: list[int]) -> dict[int, Left]:
    """What is left of each, from the moves."""
    if not product_ids:
        return {}
    signed = case((SupplyMove.kind == StockMoveKind.OUT.value, -SupplyMove.qty_milli), else_=SupplyMove.qty_milli)
    rows = db.execute(
        select(SupplyMove.product_id, func.sum(signed), func.max(SupplyMove.move_at))
        .where(SupplyMove.product_id.in_(product_ids)).group_by(SupplyMove.product_id)
    ).all()
    return {product_id: Left(int(quantity or 0), last) for product_id, quantity, last in rows}


def for_shops(db: Session, supplier_user_id: int) -> list[tuple[SupplyProduct, bool]]:
    """Each product, and whether a shop can order it. What they have comes first."""
    found = of_supplier(db, supplier_user_id)
    left = quantities(db, [p.id for p in found if p.counted])
    pairs = [(p, p.available and not (p.counted and left.get(p.id, NONE).quantity <= 0)) for p in found]
    return sorted(pairs, key=lambda x: not x[1])


def add(db: Session, user: User, bodies: list[ProductIn]) -> list[ProductOut]:
    """One or many (the ready list). Ones already there are returned as they
    are, so the list can be sent again safely."""
    _require(user)
    have = of_supplier(db, user.id)
    by_name = {(p.name.lower(), p.unit): p for p in have}
    by_ref = {p.client_ref: p for p in db.scalars(select(SupplyProduct).where(SupplyProduct.supplier_user_id == user.id))}
    made: list[SupplyProduct] = []
    count = len(have)
    for body in bodies:
        key = (body.name.lower(), body.unit.value)
        product = by_ref.get(body.client_ref) or by_name.get(key)
        if product is None:
            if count >= MAX_PRODUCTS:
                db.rollback()
                raise ApiError(400, "TOO_MANY_PRODUCTS", f"You can keep up to {MAX_PRODUCTS} products")
            product = SupplyProduct(supplier_user_id=user.id, name=body.name, catalog_code=body.catalog_code,
                                    unit=body.unit.value, price_paise=body.price_paise, available=body.available,
                                    client_ref=body.client_ref)
            db.add(product)
            by_name[key] = by_ref[body.client_ref] = product
            count += 1
        made.append(product)
    try:
        db.commit()
    except IntegrityError:  # added from another phone at the same moment
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    left = quantities(db, [p.id for p in made])
    return [out(p, left) for p in made]


def change(db: Session, user: User, product_id: int, body: ProductChangeIn) -> ProductOut:
    """The unit cannot change: orders are counted in it."""
    product = own(db, user, product_id)
    product.name = body.name
    product.price_paise = body.price_paise
    product.available = body.available
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "PRODUCT_EXISTS", f"{body.name} is already in your products") from None
    return out(product, quantities(db, [product.id]))


def remove(db: Session, user: User, product_id: int) -> None:
    product = own(db, user, product_id)
    product.archived_at = datetime.now(UTC)
    db.commit()


def out(p: SupplyProduct, left: Mapping[int, Left]) -> ProductOut:
    quantity = left.get(p.id, NONE).quantity
    return ProductOut(id=p.id, name=p.name, catalog_code=p.catalog_code, unit=StockUnit(p.unit),
                      price_paise=p.price_paise, available=p.available, counted=p.counted,
                      quantity_milli=quantity, alert_milli=p.alert_milli,
                      low=p.counted and (quantity <= 0 or (p.alert_milli is not None and quantity <= p.alert_milli)))


def own(db: Session, user: User, product_id: int) -> SupplyProduct:
    _require(user)
    product = db.get(SupplyProduct, product_id)
    if product is None or product.supplier_user_id != user.id or product.archived_at is not None:
        raise ApiError(404, "PRODUCT_NOT_FOUND", "This product is not in your list")
    return product


def _require(user: User) -> None:
    if Role.SUPPLIER.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")
