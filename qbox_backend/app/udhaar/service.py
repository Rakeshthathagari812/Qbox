"""Udhaar rules.

- A shop sees and changes only its own book. Another shop's customer or entry
  looks exactly like a missing one (404), so nothing is revealed.
- A customer sees, read-only, every book that holds their login mobile number.
- Balances are always calculated from the entries; deleted entries do not count.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import case, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, object_session

from app.auth import otp
from app.config import get_settings
from app.errors import ApiError
from app.models import (
    Dispute,
    EntryKind,
    OtpCode,
    OtpPurpose,
    Role,
    ShopProfile,
    UdhaarCustomer,
    UdhaarEntry,
    User,
)
from app.udhaar.schemas import (
    AddCustomerIn,
    BookOut,
    CustomerChangeIn,
    CustomerDetailOut,
    CustomerOut,
    EntryIn,
    EntryOut,
    InviteIn,
    InviteOut,
    MyBookDetailOut,
    MyBookOut,
)
from app.users import photos

MAX_CUSTOMERS_PER_SHOP = 5000
MAX_ENTRIES_PER_CUSTOMER = 10000


@dataclass
class _Stats:
    balance: int = 0
    last_entry_at: datetime | None = None
    last_payment_at: datetime | None = None
    first_credit_at: datetime | None = None

    @property
    def owing_since(self) -> datetime | None:
        if self.balance <= 0:
            return None
        return self.last_payment_at or self.first_credit_at


# ---------- shop side ----------


def get_book(db: Session, user: User) -> BookOut:
    _require(user, Role.BUSINESS)
    customers = db.scalars(select(UdhaarCustomer).where(UdhaarCustomer.shop_user_id == user.id)).all()
    stats = _stats(db, [c.id for c in customers])
    out = [_customer_out(c, stats.get(c.id, _Stats())) for c in customers]
    out.sort(key=lambda c: (-c.balance_paise, c.name.lower()))
    return BookOut(
        total_pending_paise=sum(c.balance_paise for c in out if c.balance_paise > 0),
        customers=out,
    )


def send_invite(db: Session, user: User, body: InviteIn) -> InviteOut:
    """Sends the "add you to our udhaar book" OTP to the customer's phone."""
    _require(user, Role.BUSINESS)
    _check_can_add(db, user, body.mobile)
    return _send_code(db, user, body.mobile)


def _send_code(db: Session, user: User, mobile: str) -> InviteOut:
    settings = get_settings()
    sent_last_hour = db.scalar(
        select(func.count())
        .select_from(OtpCode)
        .where(
            OtpCode.requested_by == user.id,
            OtpCode.purpose == OtpPurpose.UDHAAR_ADD.value,
            OtpCode.created_at > datetime.now(UTC) - timedelta(hours=1),
        )
    )
    if sent_last_hour >= settings.udhaar_invites_per_hour:
        raise ApiError(429, "INVITE_LIMIT",
                       "Too many customer codes sent in the last hour. Please try again later")

    shop_name = user.shop.shop_name if user.shop else "A shop"

    def message(code: str, minutes: int) -> str:
        return (
            f"{code} is the code for {shop_name} to add you to their QBOX udhaar book. "
            f"Share it only if you are at the shop now. Never share it on a phone call. "
            f"Valid {minutes} min."
        )

    code = otp.send_otp(db, mobile, OtpPurpose.UDHAAR_ADD, requested_by=user.id, message=message)
    return InviteOut(
        mobile=mobile,
        expires_in_seconds=settings.otp_expiry_seconds,
        resend_in_seconds=settings.otp_resend_seconds,
        dev_otp=code if settings.otp_expose else None,
    )


def add_customer(db: Session, user: User, body: AddCustomerIn) -> CustomerOut:
    """Checks the code the customer read out, then adds them to the book."""
    _require(user, Role.BUSINESS)
    _check_can_add(db, user, body.mobile)
    otp.verify_otp(db, body.mobile, OtpPurpose.UDHAAR_ADD, body.otp, requested_by=user.id)
    customer = UdhaarCustomer(
        shop_user_id=user.id,
        name=body.name.strip(),
        mobile=body.mobile,
        credit_limit_paise=body.credit_limit_paise,
        verified_at=datetime.now(UTC),
    )
    db.add(customer)
    try:
        db.commit()
    except IntegrityError:  # added at the same moment from another phone
        db.rollback()
        raise _already_added(db, user, body.mobile) from None
    return _customer_out(customer, _Stats())


def send_number_invite(db: Session, user: User, customer_id: int, mobile: str) -> InviteOut:
    """Change a customer's number, step 1: a code goes to the NEW number."""
    customer = _own_customer(db, user, customer_id)
    _check_new_number(db, user, customer, mobile)
    return _send_code(db, user, mobile)


def change_number(db: Session, user: User, customer_id: int, mobile: str, code: str) -> CustomerOut:
    """Step 2: with the code from the new number, the customer (and all their
    history) moves to it. Any "not me" report is cleared: the number is checked again."""
    customer = _own_customer(db, user, customer_id)
    _check_new_number(db, user, customer, mobile)
    otp.verify_otp(db, mobile, OtpPurpose.UDHAAR_ADD, code, requested_by=user.id)
    customer.mobile = mobile
    customer.verified_at = datetime.now(UTC)
    customer.dispute_status = Dispute.NONE.value
    customer.disputed_at = None
    customer.dispute_resolved_at = None
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _already_added(db, user, mobile) from None
    return _customer_out(customer, _stats(db, [customer.id]).get(customer.id, _Stats()))


def confirm_dispute(db: Session, user: User, customer_id: int) -> CustomerOut:
    """The shop says the reported number IS the customer's. The link stays and
    the customer cannot report it again."""
    return _resolve(db, user, customer_id, Dispute.CONFIRMED)


def unlink_dispute(db: Session, user: User, customer_id: int) -> CustomerOut:
    """The shop agrees it is the wrong number: the book is hidden from that phone.
    The shop keeps every entry and can move them to the right number."""
    return _resolve(db, user, customer_id, Dispute.UNLINKED)


def _resolve(db: Session, user: User, customer_id: int, decision: Dispute) -> CustomerOut:
    customer = _own_customer(db, user, customer_id)
    if customer.dispute_status != Dispute.REPORTED.value:
        raise ApiError(409, "NO_DISPUTE", "There is no report to check for this customer")
    customer.dispute_status = decision.value
    customer.dispute_resolved_at = datetime.now(UTC)
    db.commit()
    return _customer_out(customer, _stats(db, [customer.id]).get(customer.id, _Stats()))


def get_customer(db: Session, user: User, customer_id: int) -> CustomerDetailOut:
    customer = _own_customer(db, user, customer_id)
    entries = _entries(db, customer.id)
    stats = _stats(db, [customer.id]).get(customer.id, _Stats())
    return CustomerDetailOut(customer=_customer_out(customer, stats), entries=entries)


def change_customer(db: Session, user: User, customer_id: int, body: CustomerChangeIn) -> CustomerOut:
    customer = _own_customer(db, user, customer_id)
    customer.name = body.name.strip()
    customer.credit_limit_paise = body.credit_limit_paise
    db.commit()
    return _customer_out(customer, _stats(db, [customer.id]).get(customer.id, _Stats()))


def add_entry(db: Session, user: User, customer_id: int, body: EntryIn) -> EntryOut:
    """Adds a credit or payment. Sending the same entry twice (same client_ref,
    e.g. a retry after the phone was offline) keeps only one."""
    customer = _own_customer(db, user, customer_id)
    existing = _by_client_ref(db, customer.id, body.client_ref)
    if existing is not None:
        return _entry_out(existing)
    count = db.scalar(
        select(func.count()).select_from(UdhaarEntry).where(UdhaarEntry.customer_id == customer.id)
    )
    if count >= MAX_ENTRIES_PER_CUSTOMER:
        raise ApiError(400, "TOO_MANY_ENTRIES", "This customer has too many entries")
    entry = UdhaarEntry(
        customer_id=customer.id,
        kind=body.kind.value,
        amount_paise=body.amount_paise,
        note=body.note.strip() if body.note and body.note.strip() else None,
        entry_at=body.entry_at,
        client_ref=body.client_ref,
    )
    db.add(entry)
    try:
        db.commit()
    except IntegrityError:  # the same entry arrived twice at the same moment
        db.rollback()
        return _entry_out(_by_client_ref(db, customer.id, body.client_ref))
    return _entry_out(entry)


def delete_entry(db: Session, user: User, entry_id: int, reason: str) -> EntryOut:
    """Marks an entry deleted. The row stays, with the time and the reason."""
    _require(user, Role.BUSINESS)
    entry = db.get(UdhaarEntry, entry_id)
    customer = db.get(UdhaarCustomer, entry.customer_id) if entry else None
    if entry is None or customer is None or customer.shop_user_id != user.id:
        raise ApiError(404, "ENTRY_NOT_FOUND", "This entry no longer exists")
    if entry.deleted_at is None:
        entry.deleted_at = datetime.now(UTC)
        entry.delete_reason = reason.strip()
        db.commit()
    return _entry_out(entry)


# ---------- customer side ----------


def my_books(db: Session, user: User) -> list[MyBookOut]:
    _require(user, Role.CUSTOMER)
    rows = db.execute(
        select(UdhaarCustomer, ShopProfile)
        .join(ShopProfile, ShopProfile.user_id == UdhaarCustomer.shop_user_id, isouter=True)
        .where(UdhaarCustomer.mobile == user.mobile, UdhaarCustomer.dispute_status != Dispute.UNLINKED.value)
    ).all()
    stats = _stats(db, [c.id for c, _ in rows])
    books = [_book_out(c, shop, stats.get(c.id, _Stats())) for c, shop in rows]
    books.sort(key=lambda b: (-b.balance_paise, b.shop_name.lower()))
    return books


def my_book(db: Session, user: User, book_id: int) -> MyBookDetailOut:
    customer = _my_customer(db, user, book_id)
    shop = db.get(ShopProfile, customer.shop_user_id)
    stats = _stats(db, [customer.id]).get(customer.id, _Stats())
    return MyBookDetailOut(book=_book_out(customer, shop, stats), entries=_entries(db, customer.id))


def not_me(db: Session, user: User, book_id: int) -> MyBookOut:
    """The customer reports "this is not my number". Nothing is hidden: the
    shop is asked to check, and only the shop decides."""
    customer = _my_customer(db, user, book_id)
    if customer.dispute_status == Dispute.CONFIRMED.value:
        raise ApiError(409, "DISPUTE_CLOSED",
                       "The shop already confirmed this number is yours. Please talk to the shop")
    if customer.dispute_status == Dispute.NONE.value:
        customer.dispute_status = Dispute.REPORTED.value
        customer.disputed_at = datetime.now(UTC)
        db.commit()
    return _my_book_out(db, customer)


def cancel_not_me(db: Session, user: User, book_id: int) -> MyBookOut:
    """The customer takes the report back (only while the shop has not decided)."""
    customer = _my_customer(db, user, book_id)
    if customer.dispute_status == Dispute.REPORTED.value:
        customer.dispute_status = Dispute.NONE.value
        customer.disputed_at = None
        db.commit()
    return _my_book_out(db, customer)


def _my_book_out(db: Session, customer: UdhaarCustomer) -> MyBookOut:
    shop = db.get(ShopProfile, customer.shop_user_id)
    return _book_out(customer, shop, _stats(db, [customer.id]).get(customer.id, _Stats()))


# ---------- for other features (payments) ----------


def shop_customer(db: Session, user: User, customer_id: int) -> UdhaarCustomer:
    """A customer in this shop's own book (404 for anything else)."""
    return _own_customer(db, user, customer_id)


def customer_book(db: Session, user: User, book_id: int) -> UdhaarCustomer:
    """A book this customer can see (404 for anything else)."""
    return _my_customer(db, user, book_id)


def balance(db: Session, customer_id: int) -> int:
    """What the customer owes now (paise; negative = advance)."""
    return _stats(db, [customer_id]).get(customer_id, _Stats()).balance


# ---------- helpers ----------


def _require(user: User, role: Role) -> None:
    if role.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def _check_can_add(db: Session, user: User, mobile: str) -> None:
    if mobile == user.mobile:
        raise ApiError(400, "OWN_NUMBER", "This is your own number. Enter the customer's number")
    if _find_in_book(db, user, mobile) is not None:
        raise _already_added(db, user, mobile)
    count = db.scalar(
        select(func.count()).select_from(UdhaarCustomer).where(UdhaarCustomer.shop_user_id == user.id)
    )
    if count >= MAX_CUSTOMERS_PER_SHOP:
        raise ApiError(400, "TOO_MANY_CUSTOMERS",
                       f"An udhaar book can hold up to {MAX_CUSTOMERS_PER_SHOP} customers")


def _check_new_number(db: Session, user: User, customer: UdhaarCustomer, mobile: str) -> None:
    if mobile == customer.mobile:
        raise ApiError(400, "SAME_NUMBER", "This is already the customer's number")
    if mobile == user.mobile:
        raise ApiError(400, "OWN_NUMBER", "This is your own number. Enter the customer's number")
    if _find_in_book(db, user, mobile) is not None:
        raise _already_added(db, user, mobile)


def _find_in_book(db: Session, user: User, mobile: str) -> UdhaarCustomer | None:
    return db.scalars(
        select(UdhaarCustomer).where(UdhaarCustomer.shop_user_id == user.id, UdhaarCustomer.mobile == mobile)
    ).first()


def _already_added(db: Session, user: User, mobile: str) -> ApiError:
    existing = _find_in_book(db, user, mobile)
    name = existing.name if existing else "This customer"
    return ApiError(409, "CUSTOMER_EXISTS", f"{name} is already in your udhaar book with this number")


def _own_customer(db: Session, user: User, customer_id: int) -> UdhaarCustomer:
    _require(user, Role.BUSINESS)
    customer = db.get(UdhaarCustomer, customer_id)
    if customer is None or customer.shop_user_id != user.id:
        raise ApiError(404, "CUSTOMER_NOT_FOUND", "This customer is not in your udhaar book")
    return customer


def _my_customer(db: Session, user: User, book_id: int) -> UdhaarCustomer:
    _require(user, Role.CUSTOMER)
    customer = db.get(UdhaarCustomer, book_id)
    if (
        customer is None
        or customer.mobile != user.mobile
        or customer.dispute_status == Dispute.UNLINKED.value
    ):
        raise ApiError(404, "BOOK_NOT_FOUND", "This udhaar book is not available")
    return customer


def _by_client_ref(db: Session, customer_id: int, client_ref: str) -> UdhaarEntry | None:
    return db.scalars(
        select(UdhaarEntry).where(UdhaarEntry.customer_id == customer_id, UdhaarEntry.client_ref == client_ref)
    ).first()


def _entries(db: Session, customer_id: int) -> list[EntryOut]:
    entries = db.scalars(
        select(UdhaarEntry)
        .where(UdhaarEntry.customer_id == customer_id)
        .order_by(UdhaarEntry.entry_at.desc(), UdhaarEntry.id.desc())
    ).all()
    return [_entry_out(e) for e in entries]


def _stats(db: Session, customer_ids: list[int]) -> dict[int, _Stats]:
    """Balance and dates per customer, from live (not deleted) entries, in one query."""
    if not customer_ids:
        return {}
    credit = UdhaarEntry.kind == EntryKind.CREDIT.value
    rows = db.execute(
        select(
            UdhaarEntry.customer_id,
            func.sum(case((credit, UdhaarEntry.amount_paise), else_=-UdhaarEntry.amount_paise)),
            func.max(UdhaarEntry.entry_at),
            func.max(case((credit, None), else_=UdhaarEntry.entry_at)),
            func.min(case((credit, UdhaarEntry.entry_at), else_=None)),
        )
        .where(UdhaarEntry.customer_id.in_(customer_ids), UdhaarEntry.deleted_at.is_(None))
        .group_by(UdhaarEntry.customer_id)
    ).all()
    return {cid: _Stats(int(balance or 0), last, paid, first) for cid, balance, last, paid, first in rows}


def _customer_out(customer: UdhaarCustomer, stats: _Stats) -> CustomerOut:
    return CustomerOut(
        id=customer.id,
        name=customer.name,
        mobile=customer.mobile,
        credit_limit_paise=customer.credit_limit_paise,
        balance_paise=stats.balance,
        last_entry_at=stats.last_entry_at,
        owing_since=stats.owing_since,
        dispute=Dispute(customer.dispute_status or Dispute.NONE.value),
        disputed_at=customer.disputed_at,
        verified_at=customer.verified_at,
        added_at=customer.created_at or customer.verified_at,
    )


def _book_out(customer: UdhaarCustomer, shop: ShopProfile | None, stats: _Stats) -> MyBookOut:
    return MyBookOut(
        book_id=customer.id,
        shop_name=shop.shop_name if shop else "Shop",
        shop_phone=shop.contact_number if shop else None,
        shop_category=(shop.shop_category_detail or shop.shop_category) if shop else None,
        shop_address=shop.address if shop else None,
        shop_photo=photos.ref_of(object_session(shop), shop.user_id, Role.BUSINESS) if shop else None,
        balance_paise=stats.balance,
        last_entry_at=stats.last_entry_at,
        dispute=Dispute(customer.dispute_status or Dispute.NONE.value),
        verified_at=customer.verified_at,
    )


def _entry_out(entry: UdhaarEntry) -> EntryOut:
    return EntryOut.model_validate(entry, from_attributes=True)
