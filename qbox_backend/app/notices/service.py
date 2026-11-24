"""The bell: what happened in the last 90 days that this user should know.

Nothing is written when things happen. The list is read from the records
themselves (udhaar lines, payments, stock, suppliers), so it always agrees with
them and cannot slow down or break a payment. Only what the user has read, and
switched off, is kept.

- A customer is told only about books they can see and payments they made.
- A shop is told only about its own book, payments, stock and suppliers.
- Someone's own action is never news to them.
"""

from datetime import UTC, datetime, time, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.customer import records
from app.customer import service as history
from app.customer.schemas import TransactionStatus
from app.errors import ApiError
from app.models import (
    CustomerProfile,
    Dispute,
    EntryKind,
    NoticeRead,
    NoticeSettings,
    Payment,
    PaymentSource,
    PaymentStatus,
    Role,
    ShopProfile,
    UdhaarCustomer,
    UdhaarEntry,
    User,
)
from app.notices.schemas import TYPES, NoticeKind, NoticeOut, NoticesOut, NoticeType
from app.stock import service as stock
from app.suppliers import service as suppliers
from app.udhaar.schemas import INDIA

KEEP = timedelta(days=90)
# The first time the bell is used, older things count as read.
NEW_AT_FIRST = timedelta(days=3)
MAX_SHOWN = 100
BUDGET_NEAR = 0.8


def notices(db: Session, user: User, role: Role) -> NoticesOut:
    _require(user, role)
    settings = _settings(db, user, role)
    off = {NoticeType(t) for t in settings.off}
    found = [n for n in _all(db, user, role, off) if n.type not in off]
    read = _read(db, user, role)
    for n in found:
        n.unread = n.at > settings.read_to and n.id not in read
    found.sort(key=lambda n: (n.at, n.id), reverse=True)
    return NoticesOut(
        unread=sum(1 for n in found if n.unread),
        off=[t for t in TYPES[role] if t in off],
        notices=found[:MAX_SHOWN],
    )


def mark_read(db: Session, user: User, role: Role, notice: str | None) -> None:
    _require(user, role)
    settings = _settings(db, user, role)
    if notice is not None:
        db.execute(insert(NoticeRead).values(user_id=user.id, role=role.value, notice=notice).on_conflict_do_nothing())
    else:
        settings.read_to = datetime.now(UTC)
        # Covered by the time now.
        db.execute(delete(NoticeRead).where(NoticeRead.user_id == user.id, NoticeRead.role == role.value))
    db.commit()


def set_off(db: Session, user: User, role: Role, off: list[NoticeType]) -> list[NoticeType]:
    _require(user, role)
    settings = _settings(db, user, role)
    settings.off = [t.value for t in TYPES[role] if t in off]
    db.commit()
    return [NoticeType(t) for t in settings.off]


# ---------- what happened ----------


def _all(db: Session, user: User, role: Role, off: set[NoticeType]) -> list[NoticeOut]:
    since = datetime.now(UTC) - KEEP
    if role is Role.CUSTOMER:
        out = _books(db, user, since) + _answers(db, user, since)
        return out if NoticeType.BUDGET in off else out + _budget(db, user)
    if role is Role.BUSINESS:
        out = _paid_online(db, user, since) + _says_paid(db, user, since) + _not_me(db, user, since)
        if NoticeType.STOCK not in off:
            out += _low_stock(db, user, since)
        return out if NoticeType.SUPPLIER in off else out + _dues(db, user, since)
    return []


def _books(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """What shops did in this customer's udhaar books."""
    out: list[NoticeOut] = []
    rows = db.execute(
        select(UdhaarCustomer, ShopProfile)
        .join(ShopProfile, ShopProfile.user_id == UdhaarCustomer.shop_user_id, isouter=True)
        .where(UdhaarCustomer.mobile == user.mobile)
    ).all()
    for book, shop in rows:
        name = shop.shop_name if shop else "Shop"
        if book.dispute_status != Dispute.UNLINKED.value and book.verified_at >= since:
            out.append(_notice(f"added-{book.id}-{_stamp(book.verified_at)}", NoticeKind.ADDED, NoticeType.UDHAAR, name,
                               book.verified_at))
        decided = {Dispute.CONFIRMED.value: NoticeKind.NUMBER_KEPT, Dispute.UNLINKED.value: NoticeKind.NUMBER_REMOVED}
        kind = decided.get(book.dispute_status)
        if kind and book.dispute_resolved_at and book.dispute_resolved_at >= since:
            out.append(_notice(f"number-{book.id}-{_stamp(book.dispute_resolved_at)}", kind, NoticeType.UDHAAR, name,
                               book.dispute_resolved_at))
    paid_by_me = select(Payment.udhaar_entry_id).where(Payment.payer_user_id == user.id,
                                                       Payment.udhaar_entry_id.is_not(None))
    lines = db.execute(
        select(UdhaarEntry, ShopProfile)
        .join(UdhaarCustomer, UdhaarCustomer.id == UdhaarEntry.customer_id)
        .join(ShopProfile, ShopProfile.user_id == UdhaarCustomer.shop_user_id, isouter=True)
        .where(*history.visible_books(user),
               (UdhaarEntry.created_at >= since) | (UdhaarEntry.deleted_at >= since))
        .order_by(UdhaarEntry.id.desc()).limit(MAX_SHOWN * 2)
    ).all()
    mine = set(db.scalars(paid_by_me))
    for entry, shop in lines:
        name = shop.shop_name if shop else "Shop"
        if entry.created_at >= since and entry.id not in mine:
            kind = NoticeKind.CREDIT if entry.kind == EntryKind.CREDIT.value else NoticeKind.RECORDED
            out.append(_notice(f"line-{entry.id}", kind, NoticeType.UDHAAR, name, entry.created_at,
                               entry.amount_paise, entry.note))
        if entry.deleted_at and entry.deleted_at >= since:
            out.append(_notice(f"deleted-{entry.id}", NoticeKind.DELETED, NoticeType.UDHAAR, name, entry.deleted_at,
                               entry.amount_paise, entry.delete_reason))
    return out


def _answers(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """What shops answered about this customer's UPI payments."""
    rows = db.execute(
        select(Payment, ShopProfile)
        .join(ShopProfile, ShopProfile.user_id == Payment.shop_user_id, isouter=True)
        .where(Payment.payer_user_id == user.id, Payment.answered_at >= since)
    ).all()
    return [
        _notice(f"answer-{p.id}",
                NoticeKind.RECEIVED if p.status == PaymentStatus.PAID.value else NoticeKind.NOT_RECEIVED,
                NoticeType.PAYMENT, shop.shop_name if shop else "Shop", p.answered_at, p.amount_paise)
        for p, shop in rows
    ]


def _budget(db: Session, user: User) -> list[NoticeOut]:
    """This month's spending reached 80% of the budget, or all of it."""
    budget = records.budget(db, user)
    if not budget:
        return []
    month = datetime.now(INDIA).strftime("%Y-%m")
    spent, out = 0, []
    items = [t for t in history.month_items(db, user, month)
             if t.kind is EntryKind.PAYMENT and not t.hidden and not t.same and t.status is TransactionStatus.PAID
             and (t.deleted_at is None or t.online)]
    for item in sorted(items, key=lambda t: (t.at, t.id)):
        before, spent = spent, spent + item.amount_paise
        for kind, limit, name in ((NoticeKind.BUDGET_NEAR, int(budget * BUDGET_NEAR), "near"),
                                  (NoticeKind.BUDGET_OVER, budget + 1, "over")):
            if before < limit <= spent:
                at = min(item.at, datetime.now(UTC))
                out.append(_notice(f"budget-{month}-{budget}-{name}", kind, NoticeType.BUDGET, "", at, spent))
    # Once it is over, "nearly" is old news.
    return [n for n in out if n.kind is NoticeKind.BUDGET_OVER] or out


def _paid_online(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    at = func.coalesce(Payment.checked_at, Payment.paid_at)  # when QBOX knew
    rows = db.scalars(
        select(Payment)
        .where(Payment.shop_user_id == user.id, Payment.status == PaymentStatus.PAID.value,
               Payment.gateway.is_not(None), Payment.payer_user_id.is_not(None), at >= since)
        .order_by(at.desc()).limit(MAX_SHOWN)
    ).all()
    return [
        _notice(f"paid-{p.id}", NoticeKind.PAID_ONLINE, NoticeType.PAYMENT, _payer(db, p), p.checked_at or p.paid_at,
                p.amount_paise, p.note, test_mode=(p.gateway_key_id or "").startswith("rzp_test_"))
        for p in rows
    ]


def _says_paid(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """Waiting for this shop's answer; gone once answered."""
    rows = db.scalars(
        select(Payment)
        .where(Payment.shop_user_id == user.id, Payment.source == PaymentSource.DIRECT.value,
               Payment.gateway.is_(None), Payment.status == PaymentStatus.WAITING.value, Payment.claimed_at >= since)
    ).all()
    return [
        _notice(f"says-{p.id}", NoticeKind.SAYS_PAID, NoticeType.PAYMENT, _payer(db, p), p.claimed_at, p.amount_paise,
                p.note)
        for p in rows
    ]


def _not_me(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """Reports waiting for this shop; gone once decided."""
    rows = db.scalars(
        select(UdhaarCustomer).where(UdhaarCustomer.shop_user_id == user.id,
                                     UdhaarCustomer.dispute_status == Dispute.REPORTED.value,
                                     UdhaarCustomer.disputed_at >= since)
    ).all()
    return [
        _notice(f"notme-{c.id}-{_stamp(c.disputed_at)}", NoticeKind.NOT_ME, NoticeType.CUSTOMER, c.name, c.disputed_at)
        for c in rows
    ]


def _low_stock(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """Items low now (gone once refilled)."""
    out = []
    for item in stock.get_stock(db, user).items:
        at = item.last_move_at or item.created_at
        if item.low and at >= since:
            out.append(_notice(f"low-{item.id}", NoticeKind.LOW_STOCK, NoticeType.STOCK, item.name,
                               min(at, datetime.now(UTC)), None, f"{item.quantity_milli} {item.unit.value}"))
    return out


def _dues(db: Session, user: User, since: datetime) -> list[NoticeOut]:
    """Suppliers to pay today or earlier (gone once paid)."""
    today = datetime.now(INDIA).date()
    out = []
    for s in suppliers.get_suppliers(db, user).suppliers:
        if s.next_due is None or s.next_due > today or s.balance_paise <= 0:
            continue
        at = datetime.combine(s.next_due, time.min, INDIA)
        if at >= since:
            out.append(_notice(f"due-{s.id}-{s.next_due}", NoticeKind.SUPPLIER_DUE, NoticeType.SUPPLIER, s.name, at,
                               s.balance_paise))
    return out


# ---------- helpers ----------


def _notice(ref: str, kind: NoticeKind, group: NoticeType, name: str, at: datetime, amount: int | None = None,
            note: str | None = None, test_mode: bool = False) -> NoticeOut:
    return NoticeOut(id=ref, kind=kind, type=group, name=name, amount_paise=amount, note=note, test_mode=test_mode,
                     at=at, unread=False)


def _stamp(at: datetime) -> int:
    return int(at.timestamp())


def _payer(db: Session, payment: Payment) -> str:
    if payment.udhaar_customer_id:
        customer = db.get(UdhaarCustomer, payment.udhaar_customer_id)
        if customer is not None:
            return customer.name
    profile = db.get(CustomerProfile, payment.payer_user_id) if payment.payer_user_id else None
    return profile.full_name if profile else "A customer"


def _settings(db: Session, user: User, role: Role) -> NoticeSettings:
    row = db.get(NoticeSettings, (user.id, role.value))
    if row is None:
        db.execute(
            insert(NoticeSettings)
            .values(user_id=user.id, role=role.value, read_to=datetime.now(UTC) - NEW_AT_FIRST, off=[])
            .on_conflict_do_nothing()
        )
        db.commit()
        row = db.get(NoticeSettings, (user.id, role.value))
    return row


def _read(db: Session, user: User, role: Role) -> set[str]:
    return set(db.scalars(select(NoticeRead.notice).where(NoticeRead.user_id == user.id,
                                                          NoticeRead.role == role.value)))


def _require(user: User, role: Role) -> None:
    if role.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")
