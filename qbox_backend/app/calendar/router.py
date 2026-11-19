"""Calendar endpoints. All need login."""

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.calendar import service
from app.calendar.schemas import EventIn, EventOut, FestivalOut
from app.database import get_db
from app.deps import current_user
from app.models import Role, User

router = APIRouter(prefix="/api/calendar", tags=["Calendar"])


@router.get("/events", response_model=list[EventOut], summary="All my events in one role's calendar")
def list_events(role: Role, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.list_events(db, user, role)


@router.post("/events", response_model=EventOut, status_code=status.HTTP_201_CREATED, summary="Add an event")
def create_event(body: EventIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.create_event(db, user, body)


@router.put("/events/{event_id}", response_model=EventOut, summary="Change one of my events")
def update_event(event_id: int, body: EventIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.update_event(db, user, event_id, body)


@router.delete("/events/{event_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete one of my events")
def delete_event(event_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    service.delete_event(db, user, event_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/festivals", response_model=list[FestivalOut], summary="Built-in festivals and holidays")
def list_festivals(_: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.list_festivals(db)
