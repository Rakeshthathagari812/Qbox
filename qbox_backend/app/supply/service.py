"""The supplier's side of a shop's supplier account.

- A supplier sees only shops connected to their own account, and only what was
  written while connected. Anything else looks like a missing one (404).
- Balance = the opening balance agreed when connecting, plus goods, minus
  payments. Either side writes; what counts, and when, is in rules.py.
- A confirmed entry can no longer be deleted. Only who wrote it can delete it.
- Orders: the shop sends, the supplier accepts with prices (or rejects), then
  marks them sent; the shop receives the goods.
"""

from collections import defaultdict
from datetime import UTC, datetime

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import (
    Confirm,
    LinkStatus,
    OrderStatus,
    PayMethod,
    PayPlan,
    Role,
    ShopProfile,
    StockUnit,
    Supplier,
    SupplierEntry,
    SupplierEntryKind,
    SupplierEntryLine,
    SupplierOrder,
    SupplierOrderLine,
    SupplyLink,
    SupplyPay,
    User,
)
from app.suppliers import service as suppliers
from app.supply import counts, links, pay, products, rules
from app.supply.schemas import (
    AcceptOrderIn,
    RequestOut,
    SupplyEntryIn,
    SupplyEntryOut,
    SupplyHomeOut,
    SupplyLineOut,
    SupplyOrderOut,
    SupplyPaymentOut,
    SupplyPaymentsOut,
    SupplyShopDetailOut,
    SupplyShopOut,
)
from app.udhaar.schemas import INDIA
from app.users import photos

ENTRIES_SHOWN = 500
ORDERS_SHOWN = 200
PAYMENTS_SHOWN = 300
TO_ANSWER = {OrderStatus.SENT.value, OrderStatus.ACCEPTED.value}
OPEN_ORDERS = {OrderStatus.SENT.value, OrderStatus.ACCEPTED.value, OrderStatus.DISPATCHED.value}


# ---------- shops ----------


def home(db: Session, user: User) -> SupplyHomeOut:
    _require(user)
    found = db.scalars(
        select(SupplyLink)
        .where(SupplyLink.supplier_user_id == user.id,
               SupplyLink.status.in_([LinkStatus.ASKED.value, LinkStatus.ON.value, LinkStatus.ENDED.value]))
        .order_by(SupplyLink.id.desc())
    ).all()
    profiles = _profiles(db, found)
    asked = [x for x in found if x.status == LinkStatus.ASKED.value]
    agreed = [x for x in found if x.status != LinkStatus.ASKED.value]
    owed = suppliers.balances(db, [x.supplier_id for x in asked])
    shops = _shops(db, agreed, profiles)
    shops.sort(key=lambda s: (not s.connected, -s.balance_paise, s.shop_name.lower()))
    # A shop that connected again: its old balance is inside the new opening one.
    newest = {x.supplier_id: x.id for x in sorted(agreed, key=lambda x: x.id)}
    now = set(newest.values())
    return SupplyHomeOut(
        total_due_paise=sum(s.balance_paise for s in shops if s.balance_paise > 0 and s.link_id in now),
        requests=[
            RequestOut(**_shop(db, x, profiles), balance_paise=owed.get(x.supplier_id, 0), asked_at=x.asked_at)
            for x in asked
        ],
        shops=shops,
    )


def accept_shop(db: Session, user: User, link_id: int, balance_paise: int) -> SupplyShopOut:
    link = _link(db, user, link_id)
    links.accept(db, link, balance_paise, lambda: suppliers.balances(db, [link.supplier_id]).get(link.supplier_id, 0))
    return _shops(db, [link], _profiles(db, [link]))[0]


def decline_shop(db: Session, user: User, link_id: int, reason: str | None) -> None:
    links.decline(db, _link(db, user, link_id), reason)


def end_shop(db: Session, user: User, link_id: int) -> None:
    link = _link(db, user, link_id)
    links.lock(db, link.supplier_id)
    db.refresh(link)
    if link.status == LinkStatus.ON.value:
        links.end(db, link.supplier_id, by_shop=False)
    db.commit()


def shop(db: Session, user: User, link_id: int) -> SupplyShopDetailOut:
    link = _agreed(db, user, link_id)
    entries = db.scalars(
        select(SupplierEntry).where(SupplierEntry.link_id == link.id)
        .order_by(SupplierEntry.entry_at.desc(), SupplierEntry.id.desc()).limit(ENTRIES_SHOWN)
    ).all()
    orders_ = db.scalars(
        select(SupplierOrder).where(SupplierOrder.link_id == link.id)
        .order_by(SupplierOrder.created_at.desc(), SupplierOrder.id.desc()).limit(ORDERS_SHOWN)
    ).all()
    profiles = _profiles(db, [link])
    lines = _entry_lines(db, [e.id for e in entries])
    return SupplyShopDetailOut(
        shop=_shops(db, [link], profiles)[0],
        entries=[_entry_out(e, lines.get(e.id, [])) for e in entries],
        orders=_orders_out(db, orders_, {link.id: link}, profiles),
    )


# ---------- entries ----------


def add_entry(db: Session, user: User, link_id: int, body: SupplyEntryIn) -> SupplyEntryOut:
    """Goods given, or money received, written by the supplier. The shop answers."""
    link = _agreed(db, user, link_id)
    links.lock(db, link.supplier_id)
    db.refresh(link)
    if link.status != LinkStatus.ON.value:
        db.rollback()
        raise _disconnected()
    ref = f"s-{body.client_ref[:38]}"  # never mixed up with one the shop's phone made
    again = db.scalars(select(SupplierEntry).where(SupplierEntry.supplier_id == link.supplier_id,
                                                   SupplierEntry.client_ref == ref)).first()
    if again is not None:
        db.rollback()
        return _entry_out(again, _entry_lines(db, [again.id]).get(again.id, []))
    total = db.scalar(select(func.count()).select_from(SupplierEntry)
                      .where(SupplierEntry.supplier_id == link.supplier_id))
    if total >= suppliers.MAX_ENTRIES_PER_SUPPLIER:
        db.rollback()
        raise ApiError(400, "TOO_MANY_ENTRIES", "This shop has too many entries")
    payment = body.kind == SupplierEntryKind.PAYMENT
    entry = SupplierEntry(
        supplier_id=link.supplier_id, kind=body.kind.value, amount_paise=body.amount_paise, note=body.note,
        entry_at=body.entry_at, method=body.method.value if payment and body.method else None, client_ref=ref,
        link_id=link.id, confirm=Confirm.WAITING.value, by_supplier=True,
    )
    db.add(entry)
    db.flush()
    lines = [SupplierEntryLine(entry_id=entry.id, name=x.name, unit=x.unit.value, qty_milli=x.qty_milli,
                               cost_paise=x.cost_paise, catalog_code=x.catalog_code) for x in body.lines]
    db.add_all(lines)
    db.flush()
    counts.goods_out(db, user.id, lines, f"entry-{entry.id}", f"To {_shop_name(db, link.id)}")
    db.commit()
    return _entry_out(entry, lines)


def delete_entry(db: Session, user: User, entry_id: int, reason: str) -> SupplyEntryOut:
    """The supplier's own entry, until the shop confirms it. Kept, crossed out."""
    entry = _entry_of(db, user, entry_id, mine=True)
    lines = _entry_lines(db, [entry.id]).get(entry.id, [])
    if entry.confirm == Confirm.CONFIRMED.value:
        db.rollback()
        raise ApiError(409, "AGREED", "The shop confirmed this, so it cannot be deleted. Write a new one to correct it")
    if entry.deleted_at is None:
        entry.deleted_at = datetime.now(UTC)
        entry.delete_reason = reason.strip()
        counts.goods_back(db, lines, f"entry-{entry.id}", f"Deleted: {entry.delete_reason}")
    db.commit()
    return _entry_out(entry, lines)


def confirm_entry(db: Session, user: User, entry_id: int) -> SupplyEntryOut:
    """Yes, this is right. It can no longer be deleted by the shop."""
    entry = _entry_to_answer(db, user, entry_id)
    if entry.confirm != Confirm.CONFIRMED.value:
        entry.confirm = Confirm.CONFIRMED.value
        entry.dispute_reason = None
        entry.answered_at = datetime.now(UTC)
        # Goods given without an order leave the supplier's own count now.
        if entry.kind == SupplierEntryKind.PURCHASE.value and entry.order_id is None:
            counts.goods_out(db, user.id, _entry_lines(db, [entry.id]).get(entry.id, []), f"entry-{entry.id}",
                             f"To {_shop_name(db, entry.link_id)}")
    db.commit()
    return _entry_out(entry, _entry_lines(db, [entry.id]).get(entry.id, []))


def dispute_entry(db: Session, user: User, entry_id: int, reason: str) -> SupplyEntryOut:
    """Not right: the shop is told why, and can delete it and write it again."""
    entry = _entry_to_answer(db, user, entry_id)
    if entry.confirm == Confirm.CONFIRMED.value:
        db.rollback()
        raise ApiError(409, "ALREADY_CONFIRMED", "You already confirmed this. Please talk to the shop")
    entry.confirm = Confirm.DISPUTED.value
    entry.dispute_reason = reason.strip()
    entry.answered_at = datetime.now(UTC)
    db.commit()
    return _entry_out(entry, _entry_lines(db, [entry.id]).get(entry.id, []))


# ---------- payments ----------


def payments(db: Session, user: User) -> SupplyPaymentsOut:
    """What every shop paid, and what is still to come."""
    shops = home(db, user)
    mine = links_of(db, user)
    profiles = _profiles(db, list(mine.values()))
    rows = db.scalars(
        select(SupplierEntry)
        .where(SupplierEntry.link_id.in_(mine), SupplierEntry.kind == SupplierEntryKind.PAYMENT.value,
               SupplierEntry.deleted_at.is_(None))
        .order_by(SupplierEntry.entry_at.desc(), SupplierEntry.id.desc()).limit(PAYMENTS_SHOWN)
    ).all()
    month = datetime.now(INDIA).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    received = db.scalar(
        select(func.coalesce(func.sum(SupplierEntry.amount_paise), 0))
        .where(SupplierEntry.link_id.in_(mine), SupplierEntry.kind == SupplierEntryKind.PAYMENT.value,
               SupplierEntry.deleted_at.is_(None),
               or_(SupplierEntry.by_supplier, SupplierEntry.confirm == Confirm.CONFIRMED.value),
               SupplierEntry.entry_at >= month)
    )
    row = db.get(SupplyPay, user.id)
    out = []
    for entry in rows:
        link = mine[entry.link_id]
        p = profiles.get(link.shop_user_id)
        out.append(SupplyPaymentOut(**_entry_out(entry, []).model_dump(), link_id=link.id,
                                    shop_name=p.shop_name if p else "Shop",
                                    connected=link.status == LinkStatus.ON.value))
    return SupplyPaymentsOut(
        upi_id=row.upi_id if row else None,
        upi_name=row.upi_name if row else None,
        to_get_paise=shops.total_due_paise,
        received_month_paise=int(received),
        payments=out,
    )


# ---------- orders ----------


def orders(db: Session, user: User) -> list[SupplyOrderOut]:
    """Every shop's orders, newest first."""
    _require(user)
    mine = links_of(db, user)
    if not mine:
        return []
    rows = db.scalars(
        select(SupplierOrder).where(SupplierOrder.link_id.in_(mine))
        .order_by(SupplierOrder.created_at.desc(), SupplierOrder.id.desc()).limit(ORDERS_SHOWN)
    ).all()
    return _orders_out(db, rows, mine, _profiles(db, list(mine.values())))


def accept_order(db: Session, user: User, order_id: int, body: AcceptOrderIn) -> SupplyOrderOut:
    """What can be given, at what price, and the bill. Can be changed until sent."""
    order, link = _order_to_answer(db, user, order_id)
    _must_be(order, OrderStatus.SENT, OrderStatus.ACCEPTED)
    lines = {x.id: x for x in db.scalars(select(SupplierOrderLine).where(SupplierOrderLine.order_id == order.id))}
    if {x.id for x in body.lines} != set(lines) or len(body.lines) != len(lines):
        db.rollback()
        raise ApiError(400, "INVALID_INPUT", "Answer every item of the order")
    if not any(x.available for x in body.lines):
        db.rollback()
        raise ApiError(400, "INVALID_INPUT", "Nothing is available. Reject the order instead")
    for x in body.lines:
        lines[x.id].available = x.available
        lines[x.id].cost_paise = x.cost_paise if x.available else None
    order.status = OrderStatus.ACCEPTED.value
    order.total_paise = body.total_paise
    order.answer_note = body.note
    order.answered_at = datetime.now(UTC)
    db.commit()
    return _order_out(db, order, link)


def reject_order(db: Session, user: User, order_id: int, reason: str) -> SupplyOrderOut:
    order, link = _order_to_answer(db, user, order_id)
    if order.status != OrderStatus.REJECTED.value:
        _must_be(order, OrderStatus.SENT, OrderStatus.ACCEPTED)
        order.status = OrderStatus.REJECTED.value
        order.answer_note = reason.strip()
        order.total_paise = None
        order.answered_at = datetime.now(UTC)
    db.commit()
    return _order_out(db, order, link)


def dispatch_order(db: Session, user: User, order_id: int) -> SupplyOrderOut:
    """The goods are on the way."""
    order, link = _order_to_answer(db, user, order_id)
    if order.status != OrderStatus.DISPATCHED.value:
        _must_be(order, OrderStatus.ACCEPTED)
        order.status = OrderStatus.DISPATCHED.value
        order.dispatched_at = datetime.now(UTC)
        sent = db.scalars(select(SupplierOrderLine).where(SupplierOrderLine.order_id == order.id,
                                                          SupplierOrderLine.available))
        counts.goods_out(db, user.id, sent.all(), f"order-{order.id}", f"To {_shop_name(db, link.id)}")
    db.commit()
    return _order_out(db, order, link)


# ---------- helpers ----------


def _require(user: User) -> None:
    if Role.SUPPLIER.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def links_of(db: Session, user: User) -> dict[int, SupplyLink]:
    """Every connection, also ended ones."""
    rows = db.scalars(select(SupplyLink).where(SupplyLink.supplier_user_id == user.id,
                                               SupplyLink.status.in_([LinkStatus.ON.value, LinkStatus.ENDED.value])))
    return {x.id: x for x in rows}


def _link(db: Session, user: User, link_id: int) -> SupplyLink:
    _require(user)
    link = db.get(SupplyLink, link_id)
    if link is None or link.supplier_user_id != user.id:
        raise ApiError(404, "SHOP_NOT_FOUND", "This shop is not available")
    return link


def _agreed(db: Session, user: User, link_id: int) -> SupplyLink:
    link = _link(db, user, link_id)
    if link.status not in (LinkStatus.ON.value, LinkStatus.ENDED.value):
        raise ApiError(404, "SHOP_NOT_FOUND", "This shop is not available")
    return link


def _entry_to_answer(db: Session, user: User, entry_id: int) -> SupplierEntry:
    entry = _entry_of(db, user, entry_id, mine=False)
    if entry.deleted_at is not None:
        db.rollback()
        raise ApiError(409, "ENTRY_DELETED", "The shop deleted this entry")
    return entry


def _entry_of(db: Session, user: User, entry_id: int, mine: bool) -> SupplierEntry:
    """Locked. [mine] = written by the supplier."""
    _require(user)
    entry = db.get(SupplierEntry, entry_id)
    link = db.get(SupplyLink, entry.link_id) if entry and entry.link_id else None
    if link is None or link.supplier_user_id != user.id:
        raise ApiError(404, "ENTRY_NOT_FOUND", "This entry is not available")
    links.lock(db, entry.supplier_id)
    db.refresh(entry)
    db.refresh(link)
    if link.status != LinkStatus.ON.value:
        db.rollback()
        raise _disconnected()
    if entry.by_supplier != mine:
        db.rollback()
        raise ApiError(409, "NOT_YOURS", "The shop wrote this" if mine else "You wrote this. The shop answers it")
    return entry


def _order_to_answer(db: Session, user: User, order_id: int) -> tuple[SupplierOrder, SupplyLink]:
    _require(user)
    order = db.get(SupplierOrder, order_id)
    link = db.get(SupplyLink, order.link_id) if order and order.link_id else None
    if link is None or link.supplier_user_id != user.id:
        raise ApiError(404, "ORDER_NOT_FOUND", "This order is not available")
    links.lock(db, order.supplier_id)
    db.refresh(order)
    db.refresh(link)
    if link.status != LinkStatus.ON.value:
        db.rollback()
        raise _disconnected()
    return order, link


def _must_be(order: SupplierOrder, *allowed: OrderStatus) -> None:
    if order.status not in {s.value for s in allowed}:
        words = {
            OrderStatus.SENT.value: "Accept the order first",
            OrderStatus.CANCELLED.value: "The shop cancelled this order",
            OrderStatus.RECEIVED.value: "The shop already received this order",
        }
        raise ApiError(409, "ORDER_CLOSED", words.get(order.status, "This order can no longer be changed"))


def _disconnected() -> ApiError:
    return ApiError(409, "DISCONNECTED", "You are no longer connected with this shop")


def _profiles(db: Session, found: list[SupplyLink]) -> dict[int, ShopProfile]:
    ids = {x.shop_user_id for x in found}
    if not ids:
        return {}
    return {p.user_id: p for p in db.scalars(select(ShopProfile).where(ShopProfile.user_id.in_(ids)))}


def _shop_name(db: Session, link_id: int) -> str:
    link = db.get(SupplyLink, link_id)
    profile = db.get(ShopProfile, link.shop_user_id) if link else None
    return profile.shop_name if profile else "Shop"


def _shop(db: Session, link: SupplyLink, profiles: dict[int, ShopProfile]) -> dict:
    p = profiles.get(link.shop_user_id)
    return {
        "link_id": link.id,
        "shop_name": p.shop_name if p else "Shop",
        "shop_category": (p.shop_category_detail or p.shop_category) if p else None,
        "shop_address": p.address if p else None,
        "shop_phone": p.contact_number if p else None,
        "shop_photo": photos.ref_of(db, link.shop_user_id, Role.BUSINESS),
    }


def _shops(db: Session, found: list[SupplyLink], profiles: dict[int, ShopProfile]) -> list[SupplyShopOut]:
    if not found:
        return []
    ids = [x.id for x in found]
    balance = {x.id: x.opening_paise or 0 for x in found}
    waiting: dict[int, int] = defaultdict(int)
    last: dict[int, datetime] = {}
    rows = db.execute(
        select(SupplierEntry.link_id, SupplierEntry.kind, SupplierEntry.amount_paise, SupplierEntry.confirm,
               SupplierEntry.entry_at, SupplierEntry.by_supplier)
        .where(SupplierEntry.link_id.in_(ids), SupplierEntry.deleted_at.is_(None))
    ).all()
    for link_id, kind, amount, confirm, at, by_supplier in rows:
        if rules.counts(kind, confirm, by_supplier, for_shop=False):
            balance[link_id] += amount if kind == SupplierEntryKind.PURCHASE.value else -amount
        if confirm == Confirm.WAITING.value and not by_supplier:
            waiting[link_id] += 1
        if link_id not in last or at > last[link_id]:
            last[link_id] = at
    open_orders: dict[int, int] = defaultdict(int)
    for link_id in db.scalars(
        select(SupplierOrder.link_id).where(SupplierOrder.link_id.in_(ids), SupplierOrder.status.in_(OPEN_ORDERS))
    ):
        open_orders[link_id] += 1
    return [
        SupplyShopOut(
            **_shop(db, x, profiles),
            connected=x.status == LinkStatus.ON.value,
            connected_at=x.answered_at,
            ended_at=x.ended_at,
            opening_paise=x.opening_paise or 0,
            balance_paise=balance[x.id],
            last_entry_at=last.get(x.id),
            to_confirm=waiting[x.id] if x.status == LinkStatus.ON.value else 0,
            open_orders=open_orders[x.id] if x.status == LinkStatus.ON.value else 0,
        )
        for x in found
    ]


def _entry_lines(db: Session, ids: list[int]) -> dict[int, list[SupplierEntryLine]]:
    grouped: dict[int, list[SupplierEntryLine]] = defaultdict(list)
    if ids:
        for x in db.scalars(select(SupplierEntryLine).where(SupplierEntryLine.entry_id.in_(ids))
                            .order_by(SupplierEntryLine.id)):
            grouped[x.entry_id].append(x)
    return grouped


def _entry_out(entry: SupplierEntry, lines: list[SupplierEntryLine]) -> SupplyEntryOut:
    return SupplyEntryOut(
        id=entry.id,
        kind=SupplierEntryKind(entry.kind),
        amount_paise=entry.amount_paise,
        note=entry.note,
        entry_at=entry.entry_at,
        due_date=entry.due_date,
        method=PayMethod(entry.method) if entry.method else None,
        order_id=entry.order_id,
        lines=[_line_out(x) for x in lines],
        by_supplier=bool(entry.by_supplier),
        confirm=Confirm(entry.confirm or Confirm.WAITING.value),
        dispute_reason=entry.dispute_reason,
        deleted_at=entry.deleted_at,
        delete_reason=entry.delete_reason,
    )


def _have(db: Session, supplier_user_id: int) -> dict:
    """What the supplier has of each counted product, by id and by name and unit."""
    counted = [p for p in products.of_supplier(db, supplier_user_id) if p.counted]
    left = products.quantities(db, [p.id for p in counted])
    out: dict = {}
    for p in counted:
        out[p.id] = out[(p.name.lower(), p.unit)] = left.get(p.id, products.NONE).quantity
    return out


def _line_out(line, have: dict | None = None) -> SupplyLineOut:
    have = have or {}
    left = have.get(getattr(line, "product_id", None))
    return SupplyLineOut(id=line.id, name=line.name, unit=StockUnit(line.unit), qty_milli=line.qty_milli,
                         cost_paise=line.cost_paise, available=getattr(line, "available", True),
                         have_milli=left if left is not None else have.get((line.name.lower(), line.unit)))


def _order_out(db: Session, order: SupplierOrder, link: SupplyLink) -> SupplyOrderOut:
    return _orders_out(db, [order], {link.id: link}, _profiles(db, [link]))[0]


def _orders_out(db: Session, rows, found: dict[int, SupplyLink],
                profiles: dict[int, ShopProfile]) -> list[SupplyOrderOut]:
    lines: dict[int, list[SupplierOrderLine]] = defaultdict(list)
    if rows:
        for x in db.scalars(select(SupplierOrderLine).where(SupplierOrderLine.order_id.in_([o.id for o in rows]))
                            .order_by(SupplierOrderLine.id)):
            lines[x.order_id].append(x)
    paid = pay.for_orders(db, [o.id for o in rows])
    have = _have(db, next(iter(found.values())).supplier_user_id) if found else {}
    out = []
    for order in rows:
        link = found[order.link_id]
        p = profiles.get(link.shop_user_id)
        out.append(
            SupplyOrderOut(
                id=order.id,
                link_id=link.id,
                shop_name=p.shop_name if p else "Shop",
                shop_phone=p.contact_number if p else None,
                status=OrderStatus(order.status),
                note=order.note,
                lines=[_line_out(x, have if order.status in TO_ANSWER else {}) for x in lines[order.id]],
                total_paise=order.total_paise,
                answer_note=order.answer_note,
                created_at=order.created_at,
                answered_at=order.answered_at,
                dispatched_at=order.dispatched_at,
                received_at=order.received_at,
                connected=link.status == LinkStatus.ON.value,
                pay_plan=PayPlan(order.pay_plan) if order.pay_plan else None,
                pay_by=order.pay_by,
                paid_paise=paid[order.id].get(Confirm.CONFIRMED.value, 0),
                paying_paise=paid[order.id].get(Confirm.WAITING.value, 0),
            )
        )
    return out
