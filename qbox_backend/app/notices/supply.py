"""The bell between shops and their connected suppliers. Read from the records
themselves, like the rest of the bell (see service.py)."""

from datetime import UTC, datetime

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import (
    Confirm,
    LinkStatus,
    OrderStatus,
    ShopProfile,
    Supplier,
    SupplierEntry,
    SupplierEntryKind,
    SupplierOrder,
    SupplyLink,
    User,
)
from app.notices.schemas import NoticeKind, NoticeOut, NoticeType
from app.supply import products

MAX_ROWS = 200


def for_shop(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """What this shop's suppliers answered."""
    out: list[NoticeOut] = []

    def add(ref: str, kind: NoticeKind, name: str, at: datetime, amount: int | None = None,
            note: str | None = None) -> None:
        out.append(_notice(ref, kind, NoticeType.SUPPLIER, name, at, amount, note))

    rows = db.execute(
        select(SupplyLink, Supplier.name).join(Supplier, Supplier.id == SupplyLink.supplier_id)
        .where(SupplyLink.shop_user_id == user.id, or_(SupplyLink.answered_at >= since, SupplyLink.ended_at >= since))
        .order_by(SupplyLink.id.desc()).limit(MAX_ROWS)
    ).all()
    for link, name in rows:
        if link.answered_at and link.answered_at >= since:
            said_no = link.status == LinkStatus.DECLINED.value
            add(f"link-{link.id}", NoticeKind.NOT_CONNECTED if said_no else NoticeKind.CONNECTED, name,
                link.answered_at, None, link.decline_reason if said_no else None)
        if link.status == LinkStatus.ENDED.value and link.ended_by_shop is False and link.ended_at >= since:
            add(f"left-{link.id}", NoticeKind.SUPPLIER_LEFT, name, link.ended_at)

    rows = db.execute(
        select(SupplierOrder, Supplier.name).join(Supplier, Supplier.id == SupplierOrder.supplier_id)
        .where(Supplier.shop_user_id == user.id, SupplierOrder.link_id.is_not(None), SupplierOrder.answered_at >= since)
        .order_by(SupplierOrder.id.desc()).limit(MAX_ROWS)
    ).all()
    for order, name in rows:
        if order.status == OrderStatus.REJECTED.value:
            add(f"rejected-{order.id}", NoticeKind.ORDER_REJECTED, name, order.answered_at, None, order.answer_note)
        else:
            add(f"accepted-{order.id}-{order.total_paise}", NoticeKind.ORDER_ACCEPTED, name, order.answered_at,
                order.total_paise, order.answer_note)
        if order.dispatched_at and order.dispatched_at >= since:
            add(f"sent-{order.id}", NoticeKind.ORDER_SENT, name, order.dispatched_at, order.total_paise)

    rows = db.execute(
        select(SupplierEntry, Supplier.name).join(Supplier, Supplier.id == SupplierEntry.supplier_id)
        .where(Supplier.shop_user_id == user.id, SupplierEntry.answered_at >= since, SupplierEntry.deleted_at.is_(None),
               ~SupplierEntry.by_supplier)
        .order_by(SupplierEntry.id.desc()).limit(MAX_ROWS)
    ).all()
    for entry, name in rows:
        if entry.confirm == Confirm.DISPUTED.value:
            add(f"notright-{entry.id}", NoticeKind.NOT_RIGHT, name, entry.answered_at, entry.amount_paise,
                entry.dispute_reason)
        elif entry.confirm == Confirm.CONFIRMED.value and entry.kind == SupplierEntryKind.PAYMENT.value:
            add(f"money-{entry.id}", NoticeKind.MONEY_CONFIRMED, name, entry.answered_at, entry.amount_paise)

    rows = db.execute(
        select(SupplierEntry, Supplier.name).join(Supplier, Supplier.id == SupplierEntry.supplier_id)
        .where(Supplier.shop_user_id == user.id, SupplierEntry.by_supplier,
               or_(SupplierEntry.created_at >= since, SupplierEntry.deleted_at >= since))
        .order_by(SupplierEntry.id.desc()).limit(MAX_ROWS)
    ).all()
    for entry, name in rows:
        if entry.deleted_at is not None:
            add(f"theydeleted-{entry.id}", NoticeKind.THEY_DELETED, name, entry.deleted_at, entry.amount_paise,
                entry.delete_reason)
        elif entry.confirm == Confirm.WAITING.value:
            kind = NoticeKind.THEY_GOT if entry.kind == SupplierEntryKind.PAYMENT.value else NoticeKind.THEY_GAVE
            add(f"they-{entry.id}", kind, name, entry.created_at, entry.amount_paise, entry.note)
    return out


def for_supplier(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """What this supplier's shops did."""
    out: list[NoticeOut] = []
    rows = db.execute(
        select(SupplyLink, ShopProfile.shop_name)
        .join(ShopProfile, ShopProfile.user_id == SupplyLink.shop_user_id, isouter=True)
        .where(SupplyLink.supplier_user_id == user.id)
    ).all()
    names = {link.id: name or "Shop" for link, name in rows}
    for link, _ in rows:
        name = names[link.id]
        if link.status == LinkStatus.ASKED.value and link.asked_at >= since:
            out.append(_notice(f"wants-{link.id}", NoticeKind.WANTS_TO_CONNECT, NoticeType.LEDGER, name, link.asked_at))
        if link.status == LinkStatus.ENDED.value and link.ended_by_shop and link.ended_at >= since:
            out.append(_notice(f"shopleft-{link.id}", NoticeKind.SHOP_LEFT, NoticeType.LEDGER, name, link.ended_at))
    on = [link.id for link, _ in rows if link.status == LinkStatus.ON.value]
    if not on:
        return out

    orders = db.scalars(
        select(SupplierOrder)
        .where(SupplierOrder.link_id.in_(on),
               or_(SupplierOrder.created_at >= since, SupplierOrder.received_at >= since,
                   SupplierOrder.cancelled_at >= since))
        .order_by(SupplierOrder.id.desc()).limit(MAX_ROWS)
    ).all()
    for order in orders:
        name = names[order.link_id]
        if order.status == OrderStatus.SENT.value and order.created_at >= since:  # waiting for an answer
            out.append(_notice(f"order-{order.id}", NoticeKind.NEW_ORDER, NoticeType.ORDER, name, order.created_at,
                               None, order.note))
        if order.status == OrderStatus.CANCELLED.value and order.cancelled_at and order.cancelled_at >= since:
            out.append(_notice(f"cancelled-{order.id}", NoticeKind.ORDER_CANCELLED, NoticeType.ORDER, name,
                               order.cancelled_at))
        if order.status == OrderStatus.RECEIVED.value and order.received_at and order.received_at >= since:
            out.append(_notice(f"received-{order.id}", NoticeKind.ORDER_RECEIVED, NoticeType.ORDER, name,
                               order.received_at))

    entries = db.scalars(
        select(SupplierEntry)
        .where(SupplierEntry.link_id.in_(on),
               or_(SupplierEntry.created_at >= since, SupplierEntry.deleted_at >= since,
                   SupplierEntry.answered_at >= since))
        .order_by(SupplierEntry.id.desc()).limit(MAX_ROWS)
    ).all()
    for entry in entries:
        name = names[entry.link_id]
        if entry.by_supplier:  # only the shop's answer is news
            if entry.deleted_at is None and entry.answered_at and entry.answered_at >= since:
                if entry.confirm == Confirm.CONFIRMED.value:
                    out.append(_notice(f"agreed-{entry.id}", NoticeKind.SHOP_AGREED, NoticeType.LEDGER, name,
                                       entry.answered_at, entry.amount_paise, entry.note))
                elif entry.confirm == Confirm.DISPUTED.value:
                    out.append(_notice(f"shopnotright-{entry.id}", NoticeKind.SHOP_NOT_RIGHT, NoticeType.LEDGER, name,
                                       entry.answered_at, entry.amount_paise, entry.dispute_reason))
        elif entry.deleted_at is not None:
            if entry.deleted_at >= since:
                out.append(_notice(f"gone-{entry.id}", NoticeKind.ENTRY_DELETED, NoticeType.LEDGER, name,
                                   entry.deleted_at, entry.amount_paise, entry.delete_reason))
        elif entry.confirm == Confirm.WAITING.value and entry.created_at >= since:
            kind = (NoticeKind.CONFIRM_PAYMENT if entry.kind == SupplierEntryKind.PAYMENT.value
                    else NoticeKind.CONFIRM_PURCHASE)
            out.append(_notice(f"confirm-{entry.id}", kind, NoticeType.LEDGER, name, entry.created_at,
                               entry.amount_paise, entry.note))
    return out


def low_products(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """Counted products running low now (gone once refilled)."""
    found = [p for p in products.of_supplier(db, user.id) if p.counted]
    left = products.quantities(db, [p.id for p in found])
    out = []
    for p in found:
        seen = products.out(p, left)
        at = left.get(p.id, products.NONE).last_move_at or p.updated_at
        if seen.low and at >= since:
            out.append(_notice(f"low-{p.id}", NoticeKind.PRODUCT_LOW, NoticeType.STOCK, p.name,
                               min(at, datetime.now(UTC)), None, f"{seen.quantity_milli} {p.unit}"))
    return out


def _notice(ref: str, kind: NoticeKind, group: NoticeType, name: str, at: datetime, amount: int | None = None,
            note: str | None = None) -> NoticeOut:
    return NoticeOut(id=ref, kind=kind, type=group, name=name, amount_paise=amount, note=note, test_mode=False,
                     at=at, unread=False)
