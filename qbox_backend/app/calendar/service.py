"""Calendar rules. Every query is limited to the logged-in user's own events,
so nobody can see or change another person's calendar."""

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.calendar.schemas import EventIn, EventOut, FestivalOut
from app.errors import ApiError
from app.models import CalendarEvent, Festival, Role, User

MAX_EVENTS_PER_CALENDAR = 1000


def list_events(db: Session, user: User, role: Role) -> list[EventOut]:
    _require_role(user, role)
    events = db.scalars(
        select(CalendarEvent)
        .where(CalendarEvent.user_id == user.id, CalendarEvent.role == role.value)
        .order_by(CalendarEvent.day, CalendarEvent.time.nulls_first(), CalendarEvent.id)
    ).all()
    return [_out(e) for e in events]


def create_event(db: Session, user: User, body: EventIn) -> EventOut:
    _require_role(user, body.role)
    existing = _by_ref(db, user, body)
    if existing is not None:
        return _out(existing)
    count = db.scalar(
        select(func.count())
        .select_from(CalendarEvent)
        .where(CalendarEvent.user_id == user.id, CalendarEvent.role == body.role.value)
    )
    if count >= MAX_EVENTS_PER_CALENDAR:
        raise ApiError(400, "TOO_MANY_EVENTS",
                       f"A calendar can hold up to {MAX_EVENTS_PER_CALENDAR} events. Delete old ones first")
    event = CalendarEvent(user_id=user.id, role=body.role.value, client_ref=body.client_ref)
    _apply(event, body)
    db.add(event)
    try:
        db.commit()
    except IntegrityError:  # the same event arrived twice at the same moment
        db.rollback()
        existing = _by_ref(db, user, body)
        if existing is None:
            raise ApiError(409, "TRY_AGAIN", "Please try again") from None
        return _out(existing)
    return _out(event)


def _by_ref(db: Session, user: User, body: EventIn) -> CalendarEvent | None:
    if body.client_ref is None:
        return None
    return db.scalars(
        select(CalendarEvent).where(
            CalendarEvent.user_id == user.id, CalendarEvent.client_ref == body.client_ref
        )
    ).first()


def update_event(db: Session, user: User, event_id: int, body: EventIn) -> EventOut:
    event = _own_event(db, user, event_id)
    _apply(event, body)  # the role (which calendar it is in) never changes
    db.commit()
    return _out(event)


def delete_event(db: Session, user: User, event_id: int) -> None:
    db.delete(_own_event(db, user, event_id))
    db.commit()


def list_festivals(db: Session) -> list[FestivalOut]:
    festivals = db.scalars(select(Festival).order_by(Festival.day, Festival.id)).all()
    return [FestivalOut.model_validate(f, from_attributes=True) for f in festivals]


def _require_role(user: User, role: Role) -> None:
    if role.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def _own_event(db: Session, user: User, event_id: int) -> CalendarEvent:
    event = db.get(CalendarEvent, event_id)
    # Someone else's event looks exactly like a missing one: nothing is revealed.
    if event is None or event.user_id != user.id:
        raise ApiError(404, "EVENT_NOT_FOUND", "This event no longer exists")
    return event


def _apply(event: CalendarEvent, body: EventIn) -> None:
    event.title = body.title.strip()
    event.note = body.note.strip() if body.note and body.note.strip() else None
    event.category = body.category.value
    event.day = body.day
    event.time = body.time
    event.repeat = body.repeat.value
    event.remind_minutes = body.remind_minutes


def _out(event: CalendarEvent) -> EventOut:
    return EventOut.model_validate(event, from_attributes=True)
