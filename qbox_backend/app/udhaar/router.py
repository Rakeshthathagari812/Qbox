"""Udhaar endpoints. All need login.

Shop side (BUSINESS role):  /api/udhaar/customers..., /api/udhaar/entries...
Customer side (CUSTOMER role): /api/udhaar/mine...
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import User
from app.udhaar import service
from app.udhaar.schemas import (
    AddCustomerIn,
    BookOut,
    ChangeNumberIn,
    CustomerChangeIn,
    CustomerDetailOut,
    CustomerOut,
    DeleteEntryIn,
    EntryIn,
    EntryOut,
    InviteIn,
    InviteOut,
    MyBookDetailOut,
    MyBookOut,
    NumberInviteIn,
)

router = APIRouter(prefix="/api/udhaar", tags=["Udhaar"])


@router.get("/customers", response_model=BookOut, summary="My shop's udhaar book: customers, balances, total")
def get_book(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.get_book(db, user)


@router.post("/customers/otp", response_model=InviteOut,
             summary="Add a customer, step 1: send the OTP to their phone")
def send_invite(body: InviteIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.send_invite(db, user, body)


@router.post("/customers", response_model=CustomerOut, status_code=status.HTTP_201_CREATED,
             summary="Add a customer, step 2: the OTP they read out")
def add_customer(body: AddCustomerIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_customer(db, user, body)


@router.get("/customers/{customer_id}", response_model=CustomerDetailOut,
            summary="One customer's balance and full history")
def get_customer(customer_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.get_customer(db, user, customer_id)


@router.put("/customers/{customer_id}", response_model=CustomerOut, summary="Change name or credit limit")
def change_customer(customer_id: int, body: CustomerChangeIn,
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.change_customer(db, user, customer_id, body)


@router.post("/customers/{customer_id}/number/otp", response_model=InviteOut,
             summary="Change a customer's number, step 1: send a code to the new number")
def send_number_invite(customer_id: int, body: NumberInviteIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.send_number_invite(db, user, customer_id, body.mobile)


@router.post("/customers/{customer_id}/number", response_model=CustomerOut,
             summary="Change a customer's number, step 2: the code from the new number")
def change_number(customer_id: int, body: ChangeNumberIn,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.change_number(db, user, customer_id, body.mobile, body.otp)


@router.post("/customers/{customer_id}/dispute/confirm", response_model=CustomerOut,
             summary='"Not me" report: the number IS the customer\'s (link stays)')
def confirm_dispute(customer_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.confirm_dispute(db, user, customer_id)


@router.post("/customers/{customer_id}/dispute/unlink", response_model=CustomerOut,
             summary='"Not me" report: wrong number, hide the book from that phone')
def unlink_dispute(customer_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.unlink_dispute(db, user, customer_id)


@router.post("/customers/{customer_id}/entries", response_model=EntryOut, status_code=status.HTTP_201_CREATED,
             summary="Add udhaar given or payment received")
def add_entry(customer_id: int, body: EntryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_entry(db, user, customer_id, body)


@router.post("/entries/{entry_id}/delete", response_model=EntryOut,
             summary="Delete an entry (kept in history with the reason)")
def delete_entry(entry_id: int, body: DeleteEntryIn,
                 user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.delete_entry(db, user, entry_id, body.reason)


@router.get("/mine", response_model=list[MyBookOut], summary="Customer: every shop where I have udhaar")
def my_books(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.my_books(db, user)


@router.get("/mine/{book_id}", response_model=MyBookDetailOut, summary="Customer: one shop's entries for me")
def my_book(book_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.my_book(db, user, book_id)


@router.post("/mine/{book_id}/not-me", response_model=MyBookOut,
             summary="Customer: report \"this is not my number\" (the shop decides)")
def not_me(book_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.not_me(db, user, book_id)


@router.post("/mine/{book_id}/not-me/cancel", response_model=MyBookOut,
             summary="Customer: take back the report (before the shop decides)")
def cancel_not_me(book_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.cancel_not_me(db, user, book_id)
