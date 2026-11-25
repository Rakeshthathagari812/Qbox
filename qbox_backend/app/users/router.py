from typing import Annotated

from fastapi import APIRouter, Depends, Path, status
from sqlalchemy.orm import Session

from app.auth.schemas import AddRoleIn, ChangePinIn, ShopIn, SupplierIn
from app.database import get_db
from app.deps import current_user
from app.models import Role, User
from app.users import goodbye, photos, profile
from app.users.schemas import CustomerEditIn, DeleteAccountIn, DeleteCheckOut, MeOut, PhotoIn, PhotoOut, TokenOut
from app.users.service import to_me

router = APIRouter(prefix="/api", tags=["Users"])


@router.get("/me", response_model=MeOut, summary="The logged-in user's roles and profiles (needs login)")
def me(user: User = Depends(current_user)):
    return to_me(user)


@router.post("/me/roles", response_model=MeOut, summary="Add a role to my account (needs my PIN)")
def add_role(body: AddRoleIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile.add_role(db, user, body)
    return to_me(user)


@router.put("/me/shop", response_model=MeOut, summary="Change my shop's details")
def edit_shop(body: ShopIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile.edit_shop(db, user, body)
    return to_me(user)


@router.put("/me/customer", response_model=MeOut, summary="Change my customer details")
def edit_customer(body: CustomerEditIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile.edit_customer(db, user, body)
    return to_me(user)


@router.put("/me/supplier", response_model=MeOut, summary="Change my supplier details")
def edit_supplier(body: SupplierIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile.edit_supplier(db, user, body)
    return to_me(user)


@router.put("/me/photo/{role}", response_model=MeOut, summary="Set my photo for one role (JPEG, base64)")
def set_photo(role: Role, body: PhotoIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    photos.set_photo(db, user, role, body.jpeg)
    return to_me(user)


@router.delete("/me/photo/{role}", response_model=MeOut, summary="Remove my photo for one role")
def remove_photo(role: Role, user: User = Depends(current_user), db: Session = Depends(get_db)):
    photos.remove_photo(db, user, role)
    return to_me(user)


@router.get("/photos/{ref}", response_model=PhotoOut, summary="A photo: my own, or a shop's")
def photo(ref: Annotated[str, Path(pattern=r"^[0-9a-f]{32}$")], user: User = Depends(current_user),
          db: Session = Depends(get_db)):
    return photos.photo(db, user, ref)


@router.post("/me/pin", response_model=TokenOut,
             summary="Change my PIN (needs the old one; logs out my other phones)")
def change_pin(body: ChangePinIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return profile.change_pin(db, user, body.old_pin, body.new_pin)


@router.post("/me/logout-all", status_code=status.HTTP_204_NO_CONTENT, summary="Log out from all phones")
def logout_all(user: User = Depends(current_user), db: Session = Depends(get_db)):
    profile.logout_all(db, user)


@router.get("/me/delete-check", response_model=DeleteCheckOut, summary="What is still open, before deleting my account")
def delete_check(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return goodbye.check(db, user)


@router.post("/me/delete", status_code=status.HTTP_204_NO_CONTENT, summary="Delete my account (needs my PIN; cannot be undone)")
def delete_account(body: DeleteAccountIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    goodbye.delete_account(db, user, body.pin)
