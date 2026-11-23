"""Stock rules.

- A shop sees and changes only its own stock. Another shop's item looks
  exactly like a missing one (404).
- An item's quantity is always the sum of its moves; moves are never erased
  (a mistake is fixed with a correction, which needs a reason).
- Sending the same item or move twice (same client_ref, e.g. a retry after
  the phone was offline) keeps only one.
"""

from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import case, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import Role, StockItem, StockMove, StockMoveKind, StockUnit, User
from app.stock.schemas import (
    ItemChangeIn,
    ItemDetailOut,
    ItemIn,
    ItemOut,
    MoveIn,
    MoveOut,
    PastItemOut,
    StockOut,
)

MAX_ITEMS_PER_SHOP = 5000
MAX_MOVES_PER_ITEM = 50_000
MOVES_SHOWN = 500
PAST_ITEMS_SHOWN = 200


@dataclass
class _Stats:
    quantity: int = 0
    last_move_at: datetime | None = None


def get_stock(db: Session, user: User) -> StockOut:
    _require(user)
    items = db.scalars(
        select(StockItem).where(StockItem.shop_user_id == user.id, StockItem.archived_at.is_(None))
    ).all()
    stats = _stats(db, [i.id for i in items])
    out = sorted((_item_out(i, stats.get(i.id, _Stats())) for i in items), key=lambda i: i.name.lower())
    return StockOut(
        items=out,
        total_value_paise=sum(i.value_paise or 0 for i in out),
        low_count=sum(1 for i in out if i.low),
        past_items=_past_items(db, user, {i.name.lower() for i in items}),
    )


def _past_items(db: Session, user: User, live_names: set[str]) -> list[PastItemOut]:
    """Removed items whose name is not in stock now (newest first, one per name)."""
    removed = db.scalars(
        select(StockItem)
        .where(StockItem.shop_user_id == user.id, StockItem.archived_at.is_not(None))
        .order_by(StockItem.archived_at.desc())
        .limit(PAST_ITEMS_SHOWN * 2)
    ).all()
    out: list[PastItemOut] = []
    seen = set(live_names)
    for item in removed:
        key = item.name.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(PastItemOut(name=item.name, unit=StockUnit(item.unit), catalog_code=item.catalog_code))
        if len(out) >= PAST_ITEMS_SHOWN:
            break
    return out


def add_item(db: Session, user: User, body: ItemIn) -> ItemOut:
    _require(user)
    item = _add(db, user, body)
    try:
        db.commit()
    except IntegrityError:  # the same name or request at the same moment from another phone
        db.rollback()
        existing = _by_client_ref(db, user.id, body.client_ref)
        if existing is not None:
            return _detail_item(db, existing)
        raise _exists(body.name) from None
    return _detail_item(db, item)


def add_items(db: Session, user: User, bodies: list[ItemIn]) -> list[ItemOut]:
    """Quick start: many items at once. Names already in stock are skipped
    (their existing item is returned), so the list can be sent again safely."""
    _require(user)
    items: list[StockItem] = []
    seen: set[str] = set()
    for body in bodies:
        key = body.name.lower()
        if key in seen:
            continue
        seen.add(key)
        existing = _by_client_ref(db, user.id, body.client_ref) or _by_name(db, user.id, body.name)
        items.append(existing if existing is not None else _add(db, user, body))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Some items were added from another phone at the same time. "
                                         "Please try again") from None
    stats = _stats(db, [i.id for i in items])
    return [_item_out(i, stats.get(i.id, _Stats())) for i in items]


def get_item(db: Session, user: User, item_id: int) -> ItemDetailOut:
    item = _own_item(db, user, item_id)
    moves = db.scalars(
        select(StockMove)
        .where(StockMove.item_id == item.id)
        .order_by(StockMove.move_at.desc(), StockMove.id.desc())
        .limit(MOVES_SHOWN)
    ).all()
    return ItemDetailOut(item=_detail_item(db, item), moves=[_move_out(m) for m in moves])


def change_item(db: Session, user: User, item_id: int, body: ItemChangeIn) -> ItemOut:
    item = _own_item(db, user, item_id)
    if body.name.lower() != item.name.lower():
        other = _by_name(db, user.id, body.name)
        if other is not None and other.id != item.id:
            raise _exists(body.name)
    item.name = body.name
    item.cost_paise = body.cost_paise
    item.price_paise = body.price_paise
    item.alert_milli = body.alert_milli
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _exists(body.name) from None
    return _detail_item(db, item)


def archive_item(db: Session, user: User, item_id: int) -> ItemOut:
    """Removes an item from the stock list. Its history is kept."""
    item = _own_item(db, user, item_id)
    item.archived_at = datetime.now(UTC)
    db.commit()
    return _detail_item(db, item)


def add_move(db: Session, user: User, item_id: int, body: MoveIn) -> MoveOut:
    item = _own_item(db, user, item_id)
    existing = _move_by_ref(db, item.id, body.client_ref)
    if existing is not None:
        return _move_out(existing)
    count = db.scalar(select(func.count()).select_from(StockMove).where(StockMove.item_id == item.id))
    if count >= MAX_MOVES_PER_ITEM:
        raise ApiError(400, "TOO_MANY_MOVES", "This item has too many entries")
    move = StockMove(item_id=item.id, kind=body.kind.value, qty_milli=body.qty_milli, note=body.note,
                     move_at=body.move_at, client_ref=body.client_ref)
    db.add(move)
    try:
        db.commit()
    except IntegrityError:  # the same move arrived twice at the same moment
        db.rollback()
        return _move_out(_move_by_ref(db, item.id, body.client_ref))
    return _move_out(move)


# ---------- for other features (suppliers) ----------


def own_item(db: Session, user: User, item_id: int) -> StockItem:
    """An item in this shop's stock (404 for anything else)."""
    return _own_item(db, user, item_id)


def purchase_in(db: Session, user: User, item_id: int, qty_milli: int, note: str, move_at: datetime,
                client_ref: str) -> StockItem:
    """Stock bought from a supplier. Not committed: part of the purchase."""
    item = _own_item(db, user, item_id)
    if _move_by_ref(db, item.id, client_ref) is None:
        db.add(StockMove(item_id=item.id, kind=StockMoveKind.IN.value, qty_milli=qty_milli, note=note[:200],
                         move_at=move_at, client_ref=client_ref))
        db.flush()
    return item


def purchase_undo(db: Session, user: User, item_id: int | None, qty_milli: int, note: str, client_ref: str) -> None:
    """A deleted purchase takes its stock back out, with a correction (history
    stays). Skipped quietly if the item is gone. Not committed."""
    item = db.get(StockItem, item_id) if item_id else None
    if item is None or item.shop_user_id != user.id:
        return
    if _move_by_ref(db, item.id, client_ref) is None:
        db.add(StockMove(item_id=item.id, kind=StockMoveKind.ADJUST.value, qty_milli=-qty_milli, note=note[:200],
                         move_at=datetime.now(UTC), client_ref=client_ref))
        db.flush()


# ---------- helpers ----------


def _add(db: Session, user: User, body: ItemIn) -> StockItem:
    existing = _by_client_ref(db, user.id, body.client_ref)
    if existing is not None:
        return existing
    if _by_name(db, user.id, body.name) is not None:
        raise _exists(body.name)
    count = db.scalar(
        select(func.count()).select_from(StockItem)
        .where(StockItem.shop_user_id == user.id, StockItem.archived_at.is_(None))
    )
    if count >= MAX_ITEMS_PER_SHOP:
        raise ApiError(400, "TOO_MANY_ITEMS", f"Stock can hold up to {MAX_ITEMS_PER_SHOP} items")
    item = StockItem(
        shop_user_id=user.id,
        name=body.name,
        catalog_code=body.catalog_code,
        unit=body.unit.value,
        cost_paise=body.cost_paise,
        price_paise=body.price_paise,
        alert_milli=body.alert_milli,
        client_ref=body.client_ref,
    )
    db.add(item)
    db.flush()
    if body.opening_milli > 0:
        db.add(StockMove(item_id=item.id, kind=StockMoveKind.IN.value, qty_milli=body.opening_milli,
                         note="Opening stock", move_at=datetime.now(UTC), client_ref=f"opening-{item.id}"))
        db.flush()
    return item


def _require(user: User) -> None:
    if Role.BUSINESS.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def _own_item(db: Session, user: User, item_id: int) -> StockItem:
    _require(user)
    item = db.get(StockItem, item_id)
    if item is None or item.shop_user_id != user.id or item.archived_at is not None:
        raise ApiError(404, "ITEM_NOT_FOUND", "This item is not in your stock")
    return item


def _by_client_ref(db: Session, shop_user_id: int, client_ref: str) -> StockItem | None:
    return db.scalars(
        select(StockItem).where(StockItem.shop_user_id == shop_user_id, StockItem.client_ref == client_ref)
    ).first()


def _by_name(db: Session, shop_user_id: int, name: str) -> StockItem | None:
    return db.scalars(
        select(StockItem).where(
            StockItem.shop_user_id == shop_user_id,
            func.lower(StockItem.name) == name.lower(),
            StockItem.archived_at.is_(None),
        )
    ).first()


def _move_by_ref(db: Session, item_id: int, client_ref: str) -> StockMove | None:
    return db.scalars(
        select(StockMove).where(StockMove.item_id == item_id, StockMove.client_ref == client_ref)
    ).first()


def _exists(name: str) -> ApiError:
    return ApiError(409, "ITEM_EXISTS", f"{name} is already in your stock")


def _stats(db: Session, item_ids: list[int]) -> dict[int, _Stats]:
    """Quantity and last move per item, in one query."""
    if not item_ids:
        return {}
    signed = case((StockMove.kind == StockMoveKind.OUT.value, -StockMove.qty_milli), else_=StockMove.qty_milli)
    rows = db.execute(
        select(StockMove.item_id, func.sum(signed), func.max(StockMove.move_at))
        .where(StockMove.item_id.in_(item_ids))
        .group_by(StockMove.item_id)
    ).all()
    return {item_id: _Stats(int(quantity or 0), last) for item_id, quantity, last in rows}


def _detail_item(db: Session, item: StockItem) -> ItemOut:
    return _item_out(item, _stats(db, [item.id]).get(item.id, _Stats()))


def _item_out(item: StockItem, stats: _Stats) -> ItemOut:
    quantity = stats.quantity
    value = None
    if item.cost_paise is not None:
        value = round(max(quantity, 0) * item.cost_paise / 1000)
    return ItemOut(
        id=item.id,
        name=item.name,
        catalog_code=item.catalog_code,
        unit=StockUnit(item.unit),
        quantity_milli=quantity,
        cost_paise=item.cost_paise,
        price_paise=item.price_paise,
        alert_milli=item.alert_milli,
        low=item.alert_milli is not None and quantity <= item.alert_milli,
        value_paise=value,
        last_move_at=stats.last_move_at,
        created_at=item.created_at or datetime.now(UTC),
    )


def _move_out(move: StockMove) -> MoveOut:
    return MoveOut(
        id=move.id,
        item_id=move.item_id,
        kind=StockMoveKind(move.kind),
        qty_milli=move.qty_milli,
        note=move.note,
        move_at=move.move_at,
        client_ref=move.client_ref,
    )
