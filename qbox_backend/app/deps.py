"""Shared request helpers ("dependencies" in FastAPI)."""

from fastapi import Depends, Header
from sqlalchemy.orm import Session

from app.database import get_db
from app.errors import ApiError
from app.models import User
from app.security import read_access


def current_user(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> User:
    """Reads "Authorization: Bearer <token>" and returns the logged-in user.
    Add `user: User = Depends(current_user)` to any endpoint that needs login.

    The token must still match the account: after a PIN reset, tokens made
    before it stop working."""
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(401, "TOKEN_MISSING", "Please log in")
    user_id, version = read_access(authorization.removeprefix("Bearer ").strip())
    user = db.get(User, user_id)
    if user is None or user.token_version != version:
        raise ApiError(401, "TOKEN_INVALID", "Your session has ended. Please log in again")
    return user
