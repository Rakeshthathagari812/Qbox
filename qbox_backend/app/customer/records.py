"""Payments a customer adds themselves, and their choices for Expenses.
Private: nobody else, not even a shop, can see any of this.

- The same record sent twice (a retry after being offline) is kept once.
- Nothing in the history can be changed or deleted by the customer. A mark only
  says which category to show an item under in Expenses, or to leave it out; and
  an added payment can be said to be the same as another (shown, not counted).
"""

import re
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.customer.schemas import BudgetIn, BudgetOut, MarkIn, RecordIn, TransactionOut, TransactionStatus
from app.errors import ApiError
from app.models import (
    Dispute,
    EntryKind,
    CustomerRecord,
    ExpenseBudget,
    ExpenseCategory,
    ExpenseMark,
    Payment,
    Role,
    UdhaarCustomer,
    UdhaarEntry,
    User,
)

MAX_RECORDS = 20_000
OWN = "own"

_BY_SHOP = {
    "Grocery & Daily Needs": ExpenseCategory.GROCERIES,
    "FMCG & Household": ExpenseCategory.GROCERIES,
    "Food & Beverages": ExpenseCategory.FOOD,
    "Medical & Healthcare": ExpenseCategory.HEALTH,
    "Beauty & Personal Care": ExpenseCategory.HEALTH,
    "Clothing & Fashion": ExpenseCategory.CLOTHES,
    "Jewellery & Accessories": ExpenseCategory.CLOTHES,
    "Books & Stationery": ExpenseCategory.EDUCATION,
    "Furniture & Home Decor": ExpenseCategory.HOME,
    "Hardware & Construction": ExpenseCategory.HOME,
    "Electronics & Mobiles": ExpenseCategory.HOME,
    "Automobile & Spare Parts": ExpenseCategory.TRAVEL,
}


def require_customer(user: User) -> None:
    if Role.CUSTOMER.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def usual_category(shop_category: str | None) -> ExpenseCategory:
    return _BY_SHOP.get(shop_category or "", ExpenseCategory.OTHER)


# ---------- own records ----------


def add(db: Session, user: User, body: RecordIn) -> TransactionOut:
    require_customer(user)
    existing = _by_ref(db, user, body.client_ref)
    if existing is not None:
        return out(existing)
    count = db.scalar(select(func.count()).select_from(CustomerRecord).where(CustomerRecord.user_id == user.id))
    if count >= MAX_RECORDS:
        raise ApiError(400, "TOO_MANY_RECORDS", "You have added too many payments")
    record = CustomerRecord(
        user_id=user.id,
        client_ref=body.client_ref,
        scanned=body.scanned,
        upi_id=body.upi_id,
        title=body.title,
        amount_paise=body.amount_paise,
        category=body.category.value,
        spent_at=body.spent_at,
        note=body.note,
    )
    db.add(record)
    try:
        db.commit()
    except IntegrityError:  # the same record arrived twice at the same moment
        db.rollback()
        return out(_by_ref(db, user, body.client_ref))
    return out(record)


def different(db: Session, user: User, record_id: int) -> TransactionOut:
    """ "Not the same payment": count it, and do not ask again."""
    return _answer(db, user, record_id, same=False)


def same(db: Session, user: User, record_id: int) -> TransactionOut:
    """ "The same payment": it stays in the history and is not counted."""
    return _answer(db, user, record_id, same=True)


def _answer(db: Session, user: User, record_id: int, same: bool) -> TransactionOut:
    record = _mine(db, user, record_id)
    record.same, record.not_same = same, not same
    db.commit()
    return out(record)


def in_month(db: Session, user: User, start: datetime, end: datetime) -> list[TransactionOut]:
    rows = db.scalars(
        select(CustomerRecord).where(CustomerRecord.user_id == user.id, CustomerRecord.deleted_at.is_(None),
                                     CustomerRecord.spent_at >= start, CustomerRecord.spent_at < end)
    ).all()
    return [out(r) for r in rows]


def out(record: CustomerRecord) -> TransactionOut:
    return TransactionOut(
        id=f"own-{record.id}",
        kind=EntryKind.PAYMENT,
        amount_paise=record.amount_paise,
        at=record.spent_at,
        shop_key=OWN,
        shop_name=record.title,
        book_id=None,
        note=record.note,
        online=False,
        test_mode=False,
        status=TransactionStatus.PAID,
        deleted_at=None,
        delete_reason=None,
        own=True,
        scanned=record.scanned,
        upi_id=record.upi_id,
        not_same=record.not_same,
        same=record.same,
        category=ExpenseCategory(record.category),
    )


# ---------- choices for Expenses ----------


def mark(db: Session, user: User, item: str, body: MarkIn) -> MarkIn:
    require_customer(user)
    if not _is_theirs(db, user, item):
        raise ApiError(404, "ITEM_NOT_FOUND", "This payment is not available")
    row = db.get(ExpenseMark, (user.id, item))
    if row is None:
        row = ExpenseMark(user_id=user.id, item=item)
        db.add(row)
    row.category = body.category.value if body.category else None
    row.hidden = body.hidden
    try:
        db.commit()
    except IntegrityError:  # two taps at the same moment
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return body


def marks(db: Session, user: User, items: list[str]) -> dict[str, ExpenseMark]:
    if not items:
        return {}
    rows = db.scalars(select(ExpenseMark).where(ExpenseMark.user_id == user.id, ExpenseMark.item.in_(items))).all()
    return {r.item: r for r in rows}


def set_budget(db: Session, user: User, body: BudgetIn) -> BudgetOut:
    require_customer(user)
    row = db.get(ExpenseBudget, user.id)
    if body.month_paise is None:
        if row is not None:
            db.delete(row)
    elif row is None:
        db.add(ExpenseBudget(user_id=user.id, month_paise=body.month_paise))
    else:
        row.month_paise = body.month_paise
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return BudgetOut(month_paise=body.month_paise)


def budget(db: Session, user: User) -> int | None:
    row = db.get(ExpenseBudget, user.id)
    return row.month_paise if row else None


# ---------- helpers ----------


def _by_ref(db: Session, user: User, client_ref: str) -> CustomerRecord | None:
    return db.scalars(
        select(CustomerRecord).where(CustomerRecord.user_id == user.id, CustomerRecord.client_ref == client_ref)
    ).first()


def _mine(db: Session, user: User, record_id: int) -> CustomerRecord:
    require_customer(user)
    record = db.get(CustomerRecord, record_id)
    if record is None or record.user_id != user.id or record.deleted_at is not None:
        raise ApiError(404, "RECORD_NOT_FOUND", "This payment is not available")
    return record


def _is_theirs(db: Session, user: User, item: str) -> bool:
    """An udhaar line in a book they can see, a payment they made, or one they added."""
    match = re.fullmatch(r"(entry|payment|own)-([0-9]{1,15})", item)
    if match is None:
        return False
    number = int(match[2])
    if match[1] == "payment":
        payment = db.get(Payment, number)
        return payment is not None and payment.payer_user_id == user.id
    if match[1] == "own":
        record = db.get(CustomerRecord, number)
        return record is not None and record.user_id == user.id and record.deleted_at is None
    entry = db.get(UdhaarEntry, number)
    book = db.get(UdhaarCustomer, entry.customer_id) if entry else None
    return (book is not None and book.mobile == user.mobile
            and book.dispute_status != Dispute.UNLINKED.value)
