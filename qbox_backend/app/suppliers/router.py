"""Supplier API paths. All need login and the BUSINESS role. The rules are in service.py."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import User
from app.suppliers import service
from app.suppliers.schemas import (
    DeleteIn,
    EntryIn,
    EntryOut,
    OrderIn,
    OrderOut,
    ReceiveIn,
    SupplierChangeIn,
    SupplierDetailOut,
    SupplierIn,
    SupplierOut,
    SuppliersOut,
)

router = APIRouter(prefix="/api/suppliers", tags=["Suppliers"])


@router.get("", response_model=SuppliersOut, summary="My suppliers, what I owe each, next pay-by dates")
def get_suppliers(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.get_suppliers(db, user)


@router.post("", response_model=SupplierOut, status_code=status.HTTP_201_CREATED, summary="Add a supplier")
def add_supplier(body: SupplierIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_supplier(db, user, body)


@router.get("/{supplier_id}", response_model=SupplierDetailOut, summary="One supplier: account history and orders")
def get_supplier(supplier_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.get_supplier(db, user, supplier_id)


@router.put("/{supplier_id}", response_model=SupplierOut, summary="Change a supplier's details")
def change_supplier(supplier_id: int, body: SupplierChangeIn, user: User = Depends(current_user),
                    db: Session = Depends(get_db)):
    return service.change_supplier(db, user, supplier_id, body)


@router.post("/{supplier_id}/archive", response_model=SupplierOut,
             summary="Remove a supplier from the list (history kept)")
def archive_supplier(supplier_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.archive_supplier(db, user, supplier_id)


@router.post("/{supplier_id}/entries", response_model=EntryOut, status_code=status.HTTP_201_CREATED,
             summary="Purchase (items go into stock) or payment")
def add_entry(supplier_id: int, body: EntryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_entry(db, user, supplier_id, body)


@router.post("/entries/{entry_id}/delete", response_model=EntryOut,
             summary="Delete an entry (kept with the reason; a purchase's stock is taken back out)")
def delete_entry(entry_id: int, body: DeleteIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.delete_entry(db, user, entry_id, body.reason)


@router.post("/{supplier_id}/orders", response_model=OrderOut, status_code=status.HTTP_201_CREATED,
             summary="Save an order sent to the supplier")
def add_order(supplier_id: int, body: OrderIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_order(db, user, supplier_id, body)


@router.post("/orders/{order_id}/receive", response_model=OrderOut,
             summary="The order's goods came: a purchase, stock goes up")
def receive_order(order_id: int, body: ReceiveIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.receive_order(db, user, order_id, body)


@router.post("/orders/{order_id}/cancel", response_model=OrderOut, summary="Cancel an order")
def cancel_order(order_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.cancel_order(db, user, order_id)
