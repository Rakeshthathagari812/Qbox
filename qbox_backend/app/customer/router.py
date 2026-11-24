"""Customer endpoints (CUSTOMER role, own data only). The rules are in service.py."""

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.customer import pages, records, service
from app.customer.schemas import (
    BudgetIn,
    BudgetOut,
    MarkIn,
    PageIn,
    PageOut,
    PagesOut,
    RecordIn,
    TransactionOut,
    TransactionsOut,
)
from app.database import get_db
from app.deps import current_user
from app.models import User
from app.payments.gateways import Gateways, get_gateways
from app.udhaar.schemas import ClientRef

router = APIRouter(prefix="/api/customer", tags=["Customer"])


@router.get("/transactions", response_model=TransactionsOut,
            summary="My udhaar lines and payments in one month (this month if not given)")
def transactions(month: str | None = Query(default=None, pattern=r"^20[0-9]{2}-(0[1-9]|1[0-2])$"),
                 user: User = Depends(current_user), db: Session = Depends(get_db),
                 gateways: Gateways = Depends(get_gateways)):
    return service.transactions(db, user, month, gateways)


@router.post("/records", response_model=TransactionOut, status_code=status.HTTP_201_CREATED,
             summary="Add a payment I made outside QBOX (cash, another app, a scanned QR)")
def add_record(body: RecordIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return records.add(db, user, body)


@router.post("/records/{record_id}/different", response_model=TransactionOut,
             summary="Not the same payment as another one of that day (do not ask again)")
def different_record(record_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return records.different(db, user, record_id)


@router.post("/records/{record_id}/same", response_model=TransactionOut,
             summary="The same payment as another one of that day (kept, not counted)")
def same_record(record_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return records.same(db, user, record_id)


@router.put("/expenses/{item}", response_model=MarkIn,
            summary="An expense (entry-12, payment-5, own-7): its category, or leave it out")
def mark_expense(item: str, body: MarkIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return records.mark(db, user, item, body)


@router.put("/budget", response_model=BudgetOut, summary="My monthly budget (empty = none)")
def set_budget(body: BudgetIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return records.set_budget(db, user, body)


@router.get("/pages", response_model=PagesOut, summary="My lists and notes")
def my_pages(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return pages.all_pages(db, user)


@router.put("/pages/{ref}", response_model=PageOut,
            summary="Save a list or note (409 = changed on another phone: join the two and send again)")
def save_page(ref: ClientRef, body: PageIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return pages.save(db, user, ref, body)


@router.delete("/pages/{ref}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a list or note")
def remove_page(ref: ClientRef, user: User = Depends(current_user), db: Session = Depends(get_db)):
    pages.remove(db, user, ref)
