"""Supplier rules.

- A shop sees and changes only its own suppliers. Another shop's supplier,
  entry or order looks exactly like a missing one (404).
- The balance (what the shop owes) is always calculated from the entries;
  deleted entries do not count, and entries are never erased.
- A purchase's items are added to stock (through the stock rules), and its
  buying price becomes the item's buying price. Deleting the purchase takes
  that stock back out with a correction, so stock history stays complete.
- The same entry or order sent twice (same client_ref) is kept once.
"""

from collections import defaultdict
from datetime import UTC, date, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import (
    OrderStatus,
    PayMethod,
    Role,
    StockUnit,
    Supplier,
    SupplierEntry,
    SupplierEntryKind,
    SupplierEntryLine,
    SupplierOrder,
    SupplierOrderLine,
    User,
)
from app.stock import service as stock
from app.suppliers.schemas import (
    EntryIn,
    EntryOut,
    LineIn,
    LineOut,
    OrderIn,
    OrderOut,
    ReceiveIn,
    SupplierChangeIn,
    SupplierDetailOut,
    SupplierIn,
    SupplierOut,
    SuppliersOut,
)
from app.udhaar.schemas import INDIA

MAX_SUPPLIERS_PER_SHOP = 2000
MAX_ENTRIES_PER_SUPPLIER = 20_000
ENTRIES_SHOWN = 500
ORDERS_SHOWN = 100


class _Account:
    """A supplier's balance and dates, worked out from the entries."""

    def __init__(self) -> None:
        self.balance = 0
        self.last_entry_at: datetime | None = None
        self.next_due: date | None = None
        self.open_orders = 0


# ---------- suppliers ----------


def get_suppliers(db: Session, user: User) -> SuppliersOut:
    _require(user)
    suppliers = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == user.id, Supplier.archived_at.is_(None))
    ).all()
    accounts = _accounts(db, [s.id for s in suppliers])
    out = [_supplier_out(s, accounts.get(s.id, _Account())) for s in suppliers]
    out.sort(key=lambda s: (-s.balance_paise, s.name.lower()))
    return SuppliersOut(total_due_paise=sum(s.balance_paise for s in out if s.balance_paise > 0), suppliers=out)


def add_supplier(db: Session, user: User, body: SupplierIn) -> SupplierOut:
    _require(user)
    existing = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == user.id, Supplier.client_ref == body.client_ref)
    ).first()
    if existing is not None:
        return _detail_supplier(db, existing)
    _check_name(db, user, body.name)
    count = db.scalar(
        select(func.count()).select_from(Supplier)
        .where(Supplier.shop_user_id == user.id, Supplier.archived_at.is_(None))
    )
    if count >= MAX_SUPPLIERS_PER_SHOP:
        raise ApiError(400, "TOO_MANY_SUPPLIERS", f"You can keep up to {MAX_SUPPLIERS_PER_SHOP} suppliers")
    supplier = Supplier(shop_user_id=user.id, name=body.name, mobile=body.mobile, supplies=body.supplies,
                        note=body.note, client_ref=body.client_ref)
    db.add(supplier)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _exists(body.name) from None
    return _detail_supplier(db, supplier)


def get_supplier(db: Session, user: User, supplier_id: int) -> SupplierDetailOut:
    supplier = _own_supplier(db, user, supplier_id)
    entries = db.scalars(
        select(SupplierEntry)
        .where(SupplierEntry.supplier_id == supplier.id)
        .order_by(SupplierEntry.entry_at.desc(), SupplierEntry.id.desc())
        .limit(ENTRIES_SHOWN)
    ).all()
    orders = db.scalars(
        select(SupplierOrder)
        .where(SupplierOrder.supplier_id == supplier.id)
        .order_by(SupplierOrder.created_at.desc(), SupplierOrder.id.desc())
        .limit(ORDERS_SHOWN)
    ).all()
    entry_lines = _lines(db, SupplierEntryLine, SupplierEntryLine.entry_id, [e.id for e in entries])
    order_lines = _lines(db, SupplierOrderLine, SupplierOrderLine.order_id, [o.id for o in orders])
    return SupplierDetailOut(
        supplier=_detail_supplier(db, supplier),
        entries=[_entry_out(e, entry_lines.get(e.id, [])) for e in entries],
        orders=[_order_out(o, order_lines.get(o.id, [])) for o in orders],
    )


def change_supplier(db: Session, user: User, supplier_id: int, body: SupplierChangeIn) -> SupplierOut:
    supplier = _own_supplier(db, user, supplier_id)
    if body.name.lower() != supplier.name.lower():
        _check_name(db, user, body.name)
    supplier.name = body.name
    supplier.mobile = body.mobile
    supplier.supplies = body.supplies
    supplier.note = body.note
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _exists(body.name) from None
    return _detail_supplier(db, supplier)


def archive_supplier(db: Session, user: User, supplier_id: int) -> SupplierOut:
    """Removes a supplier from the list. Their account history is kept."""
    supplier = _own_supplier(db, user, supplier_id)
    supplier.archived_at = datetime.now(UTC)
    db.commit()
    return _detail_supplier(db, supplier)


# ---------- the account: purchases and payments ----------


def add_entry(db: Session, user: User, supplier_id: int, body: EntryIn) -> EntryOut:
    supplier = _own_supplier(db, user, supplier_id)
    existing = _entry_by_ref(db, supplier.id, body.client_ref)
    if existing is not None:
        return _entry_out(existing, _lines_of(db, existing.id))
    count = db.scalar(
        select(func.count()).select_from(SupplierEntry).where(SupplierEntry.supplier_id == supplier.id)
    )
    if count >= MAX_ENTRIES_PER_SUPPLIER:
        raise ApiError(400, "TOO_MANY_ENTRIES", "This supplier has too many entries")
    entry = _record(db, user, supplier, body.kind, body.amount_paise, body.note, body.entry_at, body.due_date,
                    body.method, body.lines, body.client_ref, paid_now=body.paid_now)
    try:
        db.commit()
    except IntegrityError:  # the same entry arrived twice at the same moment
        db.rollback()
        entry = _entry_by_ref(db, supplier.id, body.client_ref)
        if entry is None:
            raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _entry_out(entry, _lines_of(db, entry.id))


def delete_entry(db: Session, user: User, entry_id: int, reason: str) -> EntryOut:
    """Marks an entry deleted (kept, with the reason). A deleted purchase takes
    its items back out of stock."""
    _require(user)
    entry = db.get(SupplierEntry, entry_id)
    supplier = db.get(Supplier, entry.supplier_id) if entry else None
    if entry is None or supplier is None or supplier.shop_user_id != user.id:
        raise ApiError(404, "ENTRY_NOT_FOUND", "This entry no longer exists")
    lines = _lines_of(db, entry.id)
    if entry.deleted_at is None:
        entry.deleted_at = datetime.now(UTC)
        entry.delete_reason = reason.strip()
        for line in lines:
            stock.purchase_undo(db, user, line.item_id, line.qty_milli,
                                f"Purchase from {supplier.name} deleted: {entry.delete_reason}",
                                f"undo-{entry.id}-{line.id}")
        db.commit()
    return _entry_out(entry, lines)


# ---------- orders ----------


def add_order(db: Session, user: User, supplier_id: int, body: OrderIn) -> OrderOut:
    supplier = _own_supplier(db, user, supplier_id)
    existing = db.scalars(
        select(SupplierOrder).where(SupplierOrder.supplier_id == supplier.id,
                                    SupplierOrder.client_ref == body.client_ref)
    ).first()
    if existing is not None:
        return _order_out(existing, _order_lines_of(db, existing.id))
    order = SupplierOrder(supplier_id=supplier.id, status=OrderStatus.SENT.value, note=body.note,
                          client_ref=body.client_ref)
    db.add(order)
    db.flush()
    for line in body.lines:
        item = stock.own_item(db, user, line.item_id)
        db.add(SupplierOrderLine(order_id=order.id, item_id=item.id, name=item.name, unit=item.unit,
                                 qty_milli=line.qty_milli))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _order_out(order, _order_lines_of(db, order.id))


def receive_order(db: Session, user: User, order_id: int, body: ReceiveIn) -> OrderOut:
    """The goods came: a purchase with what actually came (stock goes up)."""
    order, supplier = _own_order(db, user, order_id)
    if order.status == OrderStatus.RECEIVED.value:
        return _order_out(order, _order_lines_of(db, order.id))
    if order.status != OrderStatus.SENT.value:
        raise ApiError(409, "ORDER_CLOSED", "This order was cancelled")
    if body.due_date and body.paid_now:
        raise ApiError(400, "INVALID_INPUT", "A purchase paid now has no due date")
    if len({line.item_id for line in body.lines}) != len(body.lines):
        raise ApiError(400, "INVALID_INPUT", "Each item can be added once")
    now = datetime.now(UTC)
    _record(db, user, supplier, SupplierEntryKind.PURCHASE, body.amount_paise, body.note or "Order received", now,
            body.due_date, body.method, body.lines, body.client_ref, paid_now=body.paid_now, order_id=order.id)
    order.status = OrderStatus.RECEIVED.value
    order.received_at = now
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _order_out(order, _order_lines_of(db, order.id))


def cancel_order(db: Session, user: User, order_id: int) -> OrderOut:
    order, _ = _own_order(db, user, order_id)
    if order.status == OrderStatus.SENT.value:
        order.status = OrderStatus.CANCELLED.value
        db.commit()
    return _order_out(order, _order_lines_of(db, order.id))


# ---------- helpers ----------


def _record(db: Session, user: User, supplier: Supplier, kind: SupplierEntryKind, amount: int, note: str | None,
            entry_at: datetime, due_date: date | None, method: PayMethod | None, lines: list[LineIn],
            client_ref: str, paid_now: bool = False, order_id: int | None = None) -> SupplierEntry:
    """Adds the entry (not committed). Purchase items go into stock; a purchase
    paid on the spot gets its payment too."""
    is_purchase = kind == SupplierEntryKind.PURCHASE
    entry = SupplierEntry(
        supplier_id=supplier.id,
        kind=kind.value,
        amount_paise=amount,
        note=note,
        entry_at=entry_at,
        due_date=due_date if is_purchase and not paid_now else None,
        method=method.value if method and not is_purchase else None,
        order_id=order_id,
        client_ref=client_ref,
    )
    db.add(entry)
    db.flush()
    for line in lines if is_purchase else []:
        item = stock.purchase_in(db, user, line.item_id, line.qty_milli, f"From {supplier.name}", entry_at,
                                 f"purchase-{entry.id}-{line.item_id}")
        if line.cost_paise is not None:
            item.cost_paise = line.cost_paise  # the latest buying price
        db.add(SupplierEntryLine(entry_id=entry.id, item_id=item.id, name=item.name, unit=item.unit,
                                 qty_milli=line.qty_milli, cost_paise=line.cost_paise))
    if is_purchase and paid_now:
        db.add(SupplierEntry(supplier_id=supplier.id, kind=SupplierEntryKind.PAYMENT.value, amount_paise=amount,
                             note="Paid on purchase", entry_at=entry_at,
                             method=(method or PayMethod.CASH).value, client_ref=f"{client_ref[:34]}-paid"))
    db.flush()
    return entry


def _require(user: User) -> None:
    if Role.BUSINESS.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def _own_supplier(db: Session, user: User, supplier_id: int) -> Supplier:
    _require(user)
    supplier = db.get(Supplier, supplier_id)
    if supplier is None or supplier.shop_user_id != user.id or supplier.archived_at is not None:
        raise ApiError(404, "SUPPLIER_NOT_FOUND", "This supplier is not in your list")
    return supplier


def _own_order(db: Session, user: User, order_id: int) -> tuple[SupplierOrder, Supplier]:
    _require(user)
    order = db.get(SupplierOrder, order_id)
    supplier = db.get(Supplier, order.supplier_id) if order else None
    if order is None or supplier is None or supplier.shop_user_id != user.id:
        raise ApiError(404, "ORDER_NOT_FOUND", "This order is not available")
    return order, supplier


def _check_name(db: Session, user: User, name: str) -> None:
    taken = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == user.id, func.lower(Supplier.name) == name.lower(),
                               Supplier.archived_at.is_(None))
    ).first()
    if taken is not None:
        raise _exists(name)


def _exists(name: str) -> ApiError:
    return ApiError(409, "SUPPLIER_EXISTS", f"{name} is already in your supplier list")


def _entry_by_ref(db: Session, supplier_id: int, client_ref: str) -> SupplierEntry | None:
    return db.scalars(
        select(SupplierEntry).where(SupplierEntry.supplier_id == supplier_id, SupplierEntry.client_ref == client_ref)
    ).first()


def _lines(db: Session, table, key, ids: list[int]) -> dict[int, list]:
    if not ids:
        return {}
    grouped: dict[int, list] = defaultdict(list)
    for line in db.scalars(select(table).where(key.in_(ids)).order_by(table.id)).all():
        grouped[getattr(line, key.key)].append(line)
    return grouped


def _lines_of(db: Session, entry_id: int) -> list[SupplierEntryLine]:
    return _lines(db, SupplierEntryLine, SupplierEntryLine.entry_id, [entry_id]).get(entry_id, [])


def _order_lines_of(db: Session, order_id: int) -> list[SupplierOrderLine]:
    return _lines(db, SupplierOrderLine, SupplierOrderLine.order_id, [order_id]).get(order_id, [])


def _accounts(db: Session, supplier_ids: list[int]) -> dict[int, _Account]:
    """Balance, last entry, next pay-by date and open orders per supplier.
    Payments pay off the oldest purchases first."""
    if not supplier_ids:
        return {}
    accounts: dict[int, _Account] = defaultdict(_Account)
    rows = db.execute(
        select(SupplierEntry.supplier_id, SupplierEntry.kind, SupplierEntry.amount_paise, SupplierEntry.entry_at,
               SupplierEntry.due_date)
        .where(SupplierEntry.supplier_id.in_(supplier_ids), SupplierEntry.deleted_at.is_(None))
        .order_by(SupplierEntry.entry_at, SupplierEntry.id)
    ).all()
    purchases: dict[int, list[tuple[int, date | None]]] = defaultdict(list)
    paid: dict[int, int] = defaultdict(int)
    for supplier_id, kind, amount, entry_at, due in rows:
        account = accounts[supplier_id]
        if kind == SupplierEntryKind.PURCHASE.value:
            account.balance += amount
            purchases[supplier_id].append((amount, due))
        else:
            account.balance -= amount
            paid[supplier_id] += amount
        if account.last_entry_at is None or entry_at > account.last_entry_at:
            account.last_entry_at = entry_at
    for supplier_id, items in purchases.items():
        left = paid[supplier_id]
        dues = []
        for amount, due in items:
            covered = min(left, amount)
            left -= covered
            if covered < amount and due is not None:
                dues.append(due)
        accounts[supplier_id].next_due = min(dues) if dues else None
    for supplier_id, count in db.execute(
        select(SupplierOrder.supplier_id, func.count())
        .where(SupplierOrder.supplier_id.in_(supplier_ids), SupplierOrder.status == OrderStatus.SENT.value)
        .group_by(SupplierOrder.supplier_id)
    ).all():
        accounts[supplier_id].open_orders = count
    return dict(accounts)


def _detail_supplier(db: Session, supplier: Supplier) -> SupplierOut:
    return _supplier_out(supplier, _accounts(db, [supplier.id]).get(supplier.id, _Account()))


def _supplier_out(supplier: Supplier, account: _Account) -> SupplierOut:
    today = datetime.now(INDIA).date()
    return SupplierOut(
        id=supplier.id,
        name=supplier.name,
        mobile=supplier.mobile,
        supplies=supplier.supplies,
        note=supplier.note,
        balance_paise=account.balance,
        last_entry_at=account.last_entry_at,
        next_due=account.next_due,
        overdue=account.next_due is not None and account.next_due < today,
        open_orders=account.open_orders,
    )


def _line_out(line) -> LineOut:
    return LineOut(item_id=line.item_id, name=line.name, unit=StockUnit(line.unit), qty_milli=line.qty_milli,
                   cost_paise=getattr(line, "cost_paise", None))


def _entry_out(entry: SupplierEntry, lines: list[SupplierEntryLine]) -> EntryOut:
    return EntryOut(
        id=entry.id,
        supplier_id=entry.supplier_id,
        kind=SupplierEntryKind(entry.kind),
        amount_paise=entry.amount_paise,
        note=entry.note,
        entry_at=entry.entry_at,
        due_date=entry.due_date,
        method=PayMethod(entry.method) if entry.method else None,
        order_id=entry.order_id,
        lines=[_line_out(line) for line in lines],
        client_ref=entry.client_ref,
        deleted_at=entry.deleted_at,
        delete_reason=entry.delete_reason,
    )


def _order_out(order: SupplierOrder, lines: list[SupplierOrderLine]) -> OrderOut:
    return OrderOut(
        id=order.id,
        supplier_id=order.supplier_id,
        status=OrderStatus(order.status),
        note=order.note,
        lines=[_line_out(line) for line in lines],
        created_at=order.created_at or datetime.now(UTC),
        received_at=order.received_at,
    )
