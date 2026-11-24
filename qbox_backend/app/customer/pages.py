"""Checklist & Notes: a customer's own lists and notes. Private to them.

The app edits a copy on the phone and sends the whole page:
- [base_version] is the version the phone started from. If the server's is newer
  (another phone changed it), the app is told, joins the two, and sends again.
- The same save sent twice (a retry after a lost answer) counts once (save_ref).
- A deleted page keeps only its id, so an old retry cannot bring it back.
"""

from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.customer.records import require_customer
from app.customer.schemas import PageIn, PageItem, PageOut, PagesOut
from app.errors import ApiError
from app.models import CustomerPage, User

MAX_PAGES = 200
MAX_EVER = 5_000  # with deleted ones


def all_pages(db: Session, user: User) -> PagesOut:
    require_customer(user)
    rows = db.scalars(
        select(CustomerPage)
        .where(CustomerPage.user_id == user.id, CustomerPage.deleted_at.is_(None))
        .order_by(CustomerPage.updated_at.desc())
    ).all()
    return PagesOut(pages=[_out(r) for r in rows])


def save(db: Session, user: User, ref: str, body: PageIn) -> PageOut:
    require_customer(user)
    row = _find(db, user, ref)
    if row is None:
        if body.base_version != 0:
            raise _changed()
        _check_room(db, user)
        row = CustomerPage(user_id=user.id, client_ref=ref, kind=body.kind.value, version=1)
        db.add(row)
    elif row.deleted_at is not None:
        raise _changed()
    elif row.save_ref == body.save_ref:
        return _out(row)
    elif row.version != body.base_version:
        raise _changed()
    elif row.kind != body.kind.value:
        raise ApiError(400, "INVALID_INPUT", "A list cannot become a note")
    else:
        row.version += 1
    row.title = body.title
    row.text = body.text
    row.items = [i.model_dump() for i in body.items]
    row.pinned = body.pinned
    row.save_ref = body.save_ref
    row.updated_at = datetime.now(UTC)
    try:
        db.commit()
    except IntegrityError:  # the same new page arrived twice at the same moment
        db.rollback()
        raise _changed() from None
    return _out(row)


def remove(db: Session, user: User, ref: str) -> None:
    require_customer(user)
    row = _find(db, user, ref)
    if row is None or row.deleted_at is not None:
        return  # already gone
    row.deleted_at = datetime.now(UTC)
    row.title, row.text, row.items = "", "", []
    row.version += 1
    db.commit()


# ---------- helpers ----------


def _find(db: Session, user: User, ref: str) -> CustomerPage | None:
    return db.scalars(
        select(CustomerPage)
        .where(CustomerPage.user_id == user.id, CustomerPage.client_ref == ref)
        .with_for_update()
    ).first()


def _check_room(db: Session, user: User) -> None:
    total, live = db.execute(
        select(func.count(), func.count().filter(CustomerPage.deleted_at.is_(None)))
        .select_from(CustomerPage)
        .where(CustomerPage.user_id == user.id)
    ).one()
    if live >= MAX_PAGES or total >= MAX_EVER:
        raise ApiError(400, "TOO_MANY_PAGES", "You have too many lists and notes. Please delete some first")


def _changed() -> ApiError:
    return ApiError(409, "PAGE_CHANGED", "This was changed on another phone. Please try again")


def _out(row: CustomerPage) -> PageOut:
    return PageOut(
        ref=row.client_ref,
        kind=row.kind,
        title=row.title,
        text=row.text,
        items=[PageItem.model_validate(i) for i in row.items],
        pinned=row.pinned,
        version=row.version,
        save_ref=row.save_ref,
        updated_at=row.updated_at,
    )
