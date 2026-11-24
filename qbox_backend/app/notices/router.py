"""The bell (own news only). The rules are in service.py."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import Role, User
from app.notices import service
from app.notices.schemas import NoticesOut, NoticeType, OffIn, ReadIn, UnreadOut

router = APIRouter(prefix="/api/notices", tags=["Bell"])


@router.get("", response_model=NoticesOut, summary="My news in one role, newest first")
def notices(role: Role, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.notices(db, user, role)


@router.get("/unread", response_model=UnreadOut, summary="How many are unread")
def unread(role: Role, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return UnreadOut(unread=service.notices(db, user, role).unread)


@router.post("/read", status_code=status.HTTP_204_NO_CONTENT, summary="One is read, or all of them")
def read(body: ReadIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    service.mark_read(db, user, body.role, body.id)


@router.put("/off", response_model=list[NoticeType], summary="Which kinds are switched off")
def off(body: OffIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.set_off(db, user, body.role, body.off)
