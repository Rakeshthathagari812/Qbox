"""The customer's transaction history: every udhaar line written against their
login number, every payment they made in QBOX, and what they added themselves
(records.py), one month at a time. Expenses is the same list: payments only, so
udhaar counts once, when it is paid.

- Read-only, and only their own: the same books as "My Udhaar" (a book the shop
  unlinked is not shown), plus payments where they are the payer.
- A payment in QBOX also writes a line in the udhaar book. It is shown once.
- A UPI payment (Pay to Shop) shows from the moment they say they paid, with what
  the shop answered; it counts only after the shop confirms.
- A payment they made stays in their history even if the shop deletes the line
  or the book is no longer theirs: the money did leave their account.
"""

from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.customer import records
from app.customer.schemas import TransactionOut, TransactionsOut, TransactionStatus
from app.models import (
    Dispute,
    CustomerRecord,
    EntryKind,
    ExpenseCategory,
    Payment,
    PaymentStatus,
    ShopProfile,
    UdhaarCustomer,
    UdhaarEntry,
    User,
)
from app.payments import service as payments
from app.payments.gateways import Gateways
from app.udhaar.schemas import INDIA

_ZONE = "Asia/Kolkata"


def transactions(db: Session, user: User, month: str | None, gateways: Gateways) -> TransactionsOut:
    records.require_customer(user)
    # A payment whose screen closed too early may have gone through meanwhile.
    payments.refresh_payer_waiting(db, user, gateways)

    month = month or datetime.now(INDIA).strftime("%Y-%m")
    return TransactionsOut(month=month, months=_months(db, user), transactions=month_items(db, user, month),
                           budget_paise=records.budget(db, user))


def month_items(db: Session, user: User, month: str) -> list[TransactionOut]:
    """Everything in one month, newest first."""
    start, end = _bounds(month)
    entry_rows = db.execute(
        select(UdhaarEntry, UdhaarCustomer, ShopProfile)
        .join(UdhaarCustomer, UdhaarCustomer.id == UdhaarEntry.customer_id)
        .join(ShopProfile, ShopProfile.user_id == UdhaarCustomer.shop_user_id, isouter=True)
        .where(*visible_books(user), UdhaarEntry.entry_at >= start, UdhaarEntry.entry_at < end)
    ).all()
    paid_by_me = _payments_for(db, user, [e.id for e, _, _ in entry_rows])
    items = [_from_entry(e, c, shop, paid_by_me.get(e.id)) for e, c, shop in entry_rows]

    payment_rows = db.execute(
        select(Payment, ShopProfile)
        .join(ShopProfile, ShopProfile.user_id == Payment.shop_user_id, isouter=True)
        .where(*_paid_outside_books(user), _when() >= start, _when() < end)
    ).all()
    items += [_from_payment(p, shop) for p, shop in payment_rows]
    items += records.in_month(db, user, start, end)
    _apply_marks(db, user, items)
    items.sort(key=lambda t: (t.at, t.id), reverse=True)
    return items


# ---------- helpers ----------


def _apply_marks(db: Session, user: User, items: list[TransactionOut]) -> None:
    """The customer's own choices: another category, or left out of Expenses."""
    chosen = records.marks(db, user, [t.id for t in items if t.kind == EntryKind.PAYMENT])
    for item in items:
        mark = chosen.get(item.id)
        if mark is None:
            continue
        item.hidden = mark.hidden
        if mark.category:
            item.category = ExpenseCategory(mark.category)


def visible_books(user: User):
    """Lines in the books this customer can see."""
    return (UdhaarCustomer.mobile == user.mobile, UdhaarCustomer.dispute_status != Dispute.UNLINKED.value)


def _paid_outside_books(user: User):
    """Payments they made (or say they made) that have no line in a book they can see."""
    visible_lines = (
        select(UdhaarEntry.id).join(UdhaarCustomer, UdhaarCustomer.id == UdhaarEntry.customer_id).where(*visible_books(user))
    )
    return (
        Payment.payer_user_id == user.id,
        (Payment.status == PaymentStatus.PAID.value) | Payment.claimed_at.is_not(None),
        Payment.udhaar_entry_id.is_(None) | Payment.udhaar_entry_id.not_in(visible_lines),
    )


def _when():
    return func.coalesce(Payment.paid_at, Payment.claimed_at)


def _payments_for(db: Session, user: User, entry_ids: list[int]) -> dict[int, Payment]:
    if not entry_ids:
        return {}
    rows = db.scalars(
        select(Payment).where(Payment.udhaar_entry_id.in_(entry_ids), Payment.payer_user_id == user.id,
                              Payment.status == PaymentStatus.PAID.value)
    ).all()
    return {p.udhaar_entry_id: p for p in rows}


def _months(db: Session, user: User) -> list[str]:
    entries = (
        select(func.to_char(func.timezone(_ZONE, UdhaarEntry.entry_at), "YYYY-MM"))
        .join(UdhaarCustomer, UdhaarCustomer.id == UdhaarEntry.customer_id)
        .where(*visible_books(user)).distinct()
    )
    paid = (
        select(func.to_char(func.timezone(_ZONE, _when()), "YYYY-MM"))
        .where(*_paid_outside_books(user), _when().is_not(None)).distinct()
    )
    own = (
        select(func.to_char(func.timezone(_ZONE, CustomerRecord.spent_at), "YYYY-MM"))
        .where(CustomerRecord.user_id == user.id, CustomerRecord.deleted_at.is_(None)).distinct()
    )
    return sorted({*db.scalars(entries), *db.scalars(paid), *db.scalars(own)}, reverse=True)


def _bounds(month: str) -> tuple[datetime, datetime]:
    """Start of the month and of the next one, in India time."""
    year, number = int(month[:4]), int(month[5:])
    start = datetime(year, number, 1, tzinfo=INDIA)
    end = datetime(year + number // 12, number % 12 + 1, 1, tzinfo=INDIA)
    return start.astimezone(UTC), end.astimezone(UTC)


def _shop(shop: ShopProfile | None, shop_user_id: int) -> dict:
    return {
        "shop_key": shop.qbox_id if shop else f"shop-{shop_user_id}",
        "shop_name": shop.shop_name if shop else "Shop",
    }


def _from_entry(entry: UdhaarEntry, customer: UdhaarCustomer, shop: ShopProfile | None,
                payment: Payment | None) -> TransactionOut:
    return TransactionOut(
        id=f"entry-{entry.id}",
        kind=EntryKind(entry.kind),
        amount_paise=entry.amount_paise,
        at=entry.entry_at,
        **_shop(shop, customer.shop_user_id),
        book_id=customer.id,
        note=entry.note,
        online=payment is not None,
        test_mode=_test_mode(payment),
        status=TransactionStatus.PAID,
        deleted_at=entry.deleted_at,
        delete_reason=entry.delete_reason,
        category=_category(shop) if entry.kind == EntryKind.PAYMENT.value else None,
    )


def _from_payment(payment: Payment, shop: ShopProfile | None) -> TransactionOut:
    return TransactionOut(
        id=f"payment-{payment.id}",
        kind=EntryKind.PAYMENT,
        amount_paise=payment.amount_paise,
        at=payment.paid_at or payment.claimed_at,
        **_shop(shop, payment.shop_user_id),
        book_id=None,
        note=payment.note or ("Paid online in QBOX" if payment.gateway else "Paid by UPI"),
        online=payment.gateway is not None,
        test_mode=_test_mode(payment),
        status=_status(payment),
        deleted_at=None,
        delete_reason=None,
        category=_category(shop),
    )


def _category(shop: ShopProfile | None) -> ExpenseCategory:
    return records.usual_category(shop.shop_category if shop else None)


def _status(payment: Payment) -> TransactionStatus:
    if payment.status == PaymentStatus.PAID.value:
        return TransactionStatus.PAID
    if payment.status == PaymentStatus.WAITING.value:
        return TransactionStatus.WAITING
    return TransactionStatus.NOT_CONFIRMED


def _test_mode(payment: Payment | None) -> bool:
    return bool(payment and payment.gateway_key_id and payment.gateway_key_id.startswith("rzp_test_"))