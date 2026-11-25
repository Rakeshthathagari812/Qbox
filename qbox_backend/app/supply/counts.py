"""The supplier's own stock of what they sell.

- Counting is optional, per product. What is left is always the sum of the moves,
  which are never erased (a wrong count is corrected with a new one).
- Goods sent for an order, or given without one and confirmed, go out by
  themselves, once.
- Shops never see how much there is: a counted product at 0 is "not available".
"""

from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import StockMoveKind, SupplyMove, SupplyProduct, User
from app.supply import products
from app.supply.schemas import CountKind, ProductMoveIn, ProductMoveOut, ProductStockIn, ProductStockOut

MOVES_SHOWN = 300
MAX_MOVES = 50_000


def get(db: Session, user: User, product_id: int) -> ProductStockOut:
    return _out(db, products.own(db, user, product_id))


def add(db: Session, user: User, product_id: int, body: ProductMoveIn) -> ProductStockOut:
    """Stock in, out, or "I counted, and there is this much". Starts the counting."""
    product = products.own(db, user, product_id)
    db.execute(select(SupplyProduct.id).where(SupplyProduct.id == product.id).with_for_update())
    db.refresh(product)
    again = db.scalars(
        select(SupplyMove).where(SupplyMove.product_id == product.id, SupplyMove.client_ref == body.client_ref)
    ).first()
    if again is not None:
        db.rollback()
        return _out(db, product)
    moves = db.scalar(select(func.count()).select_from(SupplyMove).where(SupplyMove.product_id == product.id))
    if moves >= MAX_MOVES:
        db.rollback()
        raise ApiError(400, "TOO_MANY_MOVES", "This product has too many entries")
    kind, qty, note = StockMoveKind.ADJUST, body.qty_milli, body.note
    if body.kind == CountKind.COUNT:
        qty -= products.quantities(db, [product.id]).get(product.id, products.NONE).quantity
        note = note or ("Counted" if moves else "First count")
    else:
        kind = StockMoveKind.IN if body.kind == CountKind.IN else StockMoveKind.OUT
    if qty:
        db.add(SupplyMove(product_id=product.id, kind=kind.value, qty_milli=qty, note=note,
                          move_at=datetime.now(UTC), client_ref=body.client_ref))
    product.counted = True
    try:
        db.commit()
    except IntegrityError:  # the same entry arrived twice at the same moment
        db.rollback()
    return _out(db, product)


def change(db: Session, user: User, product_id: int, body: ProductStockIn) -> ProductStockOut:
    """Stop counting, and when to warn. The history stays."""
    product = products.own(db, user, product_id)
    product.counted = body.counted
    product.alert_milli = body.alert_milli
    db.commit()
    return _out(db, product)


def goods_out(db: Session, supplier_user_id: int, lines, ref: str, note: str) -> None:
    """Goods that left (order or entry lines: name, unit, how much). Only counted
    products. [ref] is the same for a retry, so they leave once. Not committed."""
    mine = [p for p in products.of_supplier(db, supplier_user_id) if p.counted]
    by_id = {p.id: p for p in mine}
    by_name = {(p.name.lower(), p.unit): p for p in mine}
    for line in lines:
        product = by_id.get(getattr(line, "product_id", None)) or by_name.get((line.name.lower(), line.unit))
        if product is None:
            continue
        client_ref = f"{ref}-{line.id}"
        have = db.scalars(select(SupplyMove.id).where(SupplyMove.product_id == product.id,
                                                      SupplyMove.client_ref == client_ref)).first()
        if have is None:
            db.add(SupplyMove(product_id=product.id, kind=StockMoveKind.OUT.value, qty_milli=line.qty_milli,
                              note=note[:200], move_at=datetime.now(UTC), client_ref=client_ref))
    db.flush()


def goods_back(db: Session, lines, ref: str, note: str) -> None:
    """Goods that left and did not: what went out for them comes back, once. Not
    committed."""
    for line in lines:
        move = db.scalars(select(SupplyMove).where(SupplyMove.client_ref == f"{ref}-{line.id}",
                                                   SupplyMove.kind == StockMoveKind.OUT.value)).first()
        back = f"back-{ref}-{line.id}"
        if move is None or db.scalars(select(SupplyMove.id).where(SupplyMove.product_id == move.product_id,
                                                                  SupplyMove.client_ref == back)).first() is not None:
            continue
        db.add(SupplyMove(product_id=move.product_id, kind=StockMoveKind.IN.value, qty_milli=move.qty_milli,
                          note=note[:200], move_at=datetime.now(UTC), client_ref=back))
    db.flush()


def _out(db: Session, product: SupplyProduct) -> ProductStockOut:
    moves = db.scalars(
        select(SupplyMove).where(SupplyMove.product_id == product.id)
        .order_by(SupplyMove.move_at.desc(), SupplyMove.id.desc()).limit(MOVES_SHOWN)
    ).all()
    return ProductStockOut(
        product=products.out(product, products.quantities(db, [product.id])),
        moves=[ProductMoveOut(id=m.id, kind=StockMoveKind(m.kind), qty_milli=m.qty_milli, note=m.note, move_at=m.move_at)
               for m in moves],
    )
