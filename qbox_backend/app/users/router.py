from fastapi import APIRouter, Depends

from app.deps import current_user
from app.models import User
from app.users.schemas import MeOut
from app.users.service import to_me

router = APIRouter(prefix="/api", tags=["Users"])


@router.get("/me", response_model=MeOut, summary="The logged-in user's roles and profiles (needs login)")
def me(user: User = Depends(current_user)):
    return to_me(user)
