"""The connection between a supplier in a shop's list and a QBOX Supplier account.

- The supplier agrees by reading out a code sent to their phone. The message
  says what the shop owes: sharing the code agrees that amount (the opening
  balance). Entries from before stay private to the shop, and can no longer be
  deleted.
- A supplier who is not on QBOX yet: the number is marked verified. When they
  join with it, they are asked, shown the amount, and say yes themselves.
- A connection can be ended by either side. What was shared stays readable to
  both, so nobody can hide an agreed account by disconnecting.
"""

from collections.abc import Callable
from datetime import UTC, datetime

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import Confirm, LinkStatus, Role, Supplier, SupplierEntry, SupplyLink, User, UserRole

LIVE = (LinkStatus.ASKED.value, LinkStatus.ON.value)


def lock(db: Session, supplier_id: int) -> None:
    """Changes to one supplier's account wait their turn, so an entry can never
    slip in between "what is owed" and "agreed"."""
    db.execute(select(Supplier.id).where(Supplier.id == supplier_id).with_for_update())


def on(db: Session, supplier_id: int) -> SupplyLink | None:
    return db.scalars(
        select(SupplyLink).where(SupplyLink.supplier_id == supplier_id, SupplyLink.status == LinkStatus.ON.value)
        .execution_options(populate_existing=True)
    ).first()


def latest(db: Session, supplier_ids: list[int]) -> dict[int, SupplyLink]:
    """The newest connection (or question, or answer) of each supplier."""
    if not supplier_ids:
        return {}
    rows = db.scalars(select(SupplyLink).where(SupplyLink.supplier_id.in_(supplier_ids)).order_by(SupplyLink.id)).all()
    return {r.supplier_id: r for r in rows}


def check_can_connect(db: Session, shop: User, mobile: str | None, supplier_id: int | None = None) -> None:
    """Before a code is sent, and again before it is used."""
    if not mobile:
        raise ApiError(400, "NO_MOBILE", "Add the supplier's mobile number first")
    if mobile == shop.mobile:
        raise ApiError(400, "OWN_NUMBER", "This is your own number. Enter the supplier's number")
    twin = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == shop.id, Supplier.mobile == mobile,
                               Supplier.verified_at.is_not(None), Supplier.archived_at.is_(None),
                               Supplier.id != (supplier_id or 0))
    ).first()
    if twin is not None:
        raise ApiError(409, "ALREADY_CONNECTED", f"{twin.name} is already in your list with this number")
    if supplier_id is not None and on(db, supplier_id) is not None:
        raise ApiError(409, "ALREADY_CONNECTED", "You are already connected")


def verified(db: Session, supplier: Supplier, opening_paise: int) -> None:
    """The supplier read out the code: connected at once if they use QBOX. The
    account must be locked. Not committed."""
    now = datetime.now(UTC)
    supplier.verified_at = now
    link = _live(db, supplier.id)
    if link is None:
        other = db.scalars(
            select(User).join(UserRole, UserRole.user_id == User.id)
            .where(User.mobile == supplier.mobile, UserRole.role == Role.SUPPLIER.value)
        ).first()
        if other is None:
            return  # when they join: welcome()
        # A question left from an older entry of this shop is replaced.
        for old in db.scalars(select(SupplyLink).where(SupplyLink.shop_user_id == supplier.shop_user_id,
                                                       SupplyLink.supplier_user_id == other.id,
                                                       SupplyLink.status == LinkStatus.ASKED.value)):
            old.status = LinkStatus.CANCELLED.value
            old.ended_at, old.ended_by_shop = now, True
        db.flush()
        link = SupplyLink(supplier_id=supplier.id, shop_user_id=supplier.shop_user_id, supplier_user_id=other.id,
                          asked_at=now)
        db.add(link)
    link.status = LinkStatus.ON.value
    link.answered_at = now
    link.opening_paise = opening_paise
    link.opening_entry_id = _last_entry(db, supplier.id)


def welcome(db: Session, user: User) -> None:
    """Someone became a QBOX supplier: shops that checked their number with a code
    are waiting in their Shop Ledger. Not committed."""
    waiting = db.scalars(
        select(Supplier).where(Supplier.mobile == user.mobile, Supplier.verified_at.is_not(None),
                               Supplier.archived_at.is_(None), Supplier.shop_user_id != user.id)
        .order_by(Supplier.id)
    ).all()
    seen: set[int] = set()
    for supplier in waiting:
        if supplier.shop_user_id in seen or _live(db, supplier.id) is not None:
            continue
        seen.add(supplier.shop_user_id)
        db.add(SupplyLink(supplier_id=supplier.id, shop_user_id=supplier.shop_user_id, supplier_user_id=user.id,
                          status=LinkStatus.ASKED.value, asked_at=datetime.now(UTC)))


def accept(db: Session, link: SupplyLink, balance_paise: int, balance_now: Callable[[], int]) -> None:
    """[balance_now] is called after the account is locked."""
    lock(db, link.supplier_id)
    db.refresh(link)
    if link.status == LinkStatus.ON.value:
        return  # a retry
    if link.status != LinkStatus.ASKED.value:
        raise _gone()
    if balance_now() != balance_paise:
        db.rollback()
        raise ApiError(409, "BALANCE_CHANGED", "The shop's account changed. Please check the amount again")
    link.status = LinkStatus.ON.value
    link.answered_at = datetime.now(UTC)
    link.opening_paise = balance_paise
    link.opening_entry_id = _last_entry(db, link.supplier_id)
    db.commit()


def decline(db: Session, link: SupplyLink, reason: str | None) -> None:
    lock(db, link.supplier_id)
    db.refresh(link)
    if link.status == LinkStatus.DECLINED.value:
        return
    if link.status != LinkStatus.ASKED.value:
        raise _gone()
    link.status = LinkStatus.DECLINED.value
    link.answered_at = datetime.now(UTC)
    link.decline_reason = reason
    db.commit()


def end(db: Session, supplier_id: int, by_shop: bool) -> None:
    """Ends the connection, or takes the question back. Not committed."""
    lock(db, supplier_id)
    link = _live(db, supplier_id)
    if link is None:
        return
    link.ended_at = datetime.now(UTC)
    link.ended_by_shop = by_shop
    if link.status == LinkStatus.ASKED.value:
        link.status = LinkStatus.CANCELLED.value
        return
    link.status = LinkStatus.ENDED.value
    # Never answered, and cannot be any more: they count for the shop only.
    db.execute(
        update(SupplierEntry)
        .where(SupplierEntry.link_id == link.id,
               SupplierEntry.confirm.in_([Confirm.WAITING.value, Confirm.DISPUTED.value]))
        .values(confirm=Confirm.CLOSED.value)
    )


def _last_entry(db: Session, supplier_id: int) -> int:
    return db.scalar(select(func.max(SupplierEntry.id)).where(SupplierEntry.supplier_id == supplier_id)) or 0


def _live(db: Session, supplier_id: int) -> SupplyLink | None:
    return db.scalars(
        select(SupplyLink).where(SupplyLink.supplier_id == supplier_id, SupplyLink.status.in_(LIVE))
        .execution_options(populate_existing=True)
    ).first()


def _gone() -> ApiError:
    return ApiError(409, "REQUEST_CLOSED", "This request is no longer open")
