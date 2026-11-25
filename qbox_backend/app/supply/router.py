"""The supplier's side (SUPPLIER role, own shops only). The rules are in service.py."""

from datetime import date

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import User
from app.payments.schemas import UpiIn
from app.supply import counts, pay, products, reports, service
from app.supply.schemas import (
    AcceptOrderIn,
    AcceptShopIn,
    OptionalReasonIn,
    ProductChangeIn,
    ProductMoveIn,
    ProductOut,
    ProductsIn,
    ProductStockIn,
    ProductStockOut,
    ReasonIn,
    ReportOut,
    SupplyEntryIn,
    SupplyEntryOut,
    SupplyHomeOut,
    SupplyOrderOut,
    SupplyPaymentsOut,
    SupplyShopDetailOut,
    SupplyShopOut,
)

router = APIRouter(prefix="/api/supply", tags=["Supplier side"])


@router.get("/shops", response_model=SupplyHomeOut, summary="Shops asking to connect, and my shops with what they owe")
def home(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.home(db, user)


@router.get("/shops/{link_id}", response_model=SupplyShopDetailOut, summary="One shop: its account and orders")
def shop(link_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.shop(db, user, link_id)


@router.post("/shops/{link_id}/accept", response_model=SupplyShopOut,
             summary="Connect, and agree the opening balance shown")
def accept_shop(link_id: int, body: AcceptShopIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.accept_shop(db, user, link_id, body.balance_paise)


@router.post("/shops/{link_id}/decline", status_code=status.HTTP_204_NO_CONTENT, summary="Do not connect")
def decline_shop(link_id: int, body: OptionalReasonIn, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    service.decline_shop(db, user, link_id, body.reason)


@router.post("/shops/{link_id}/end", status_code=status.HTTP_204_NO_CONTENT,
             summary="Disconnect (the account so far stays readable)")
def end_shop(link_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    service.end_shop(db, user, link_id)


@router.post("/shops/{link_id}/entries", response_model=SupplyEntryOut, status_code=status.HTTP_201_CREATED,
             summary="Goods given or money received, written by the supplier (the shop answers)")
def add_entry(link_id: int, body: SupplyEntryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_entry(db, user, link_id, body)


@router.post("/entries/{entry_id}/delete", response_model=SupplyEntryOut, summary="Delete my own entry (kept with the reason)")
def delete_entry(entry_id: int, body: ReasonIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.delete_entry(db, user, entry_id, body.reason)


@router.post("/entries/{entry_id}/confirm", response_model=SupplyEntryOut, summary="This entry is right")
def confirm_entry(entry_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.confirm_entry(db, user, entry_id)


@router.post("/entries/{entry_id}/dispute", response_model=SupplyEntryOut, summary="This entry is not right")
def dispute_entry(entry_id: int, body: ReasonIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.dispute_entry(db, user, entry_id, body.reason)


@router.get("/orders", response_model=list[SupplyOrderOut], summary="Every shop's orders, newest first")
def orders(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.orders(db, user)


@router.post("/orders/{order_id}/accept", response_model=SupplyOrderOut,
             summary="What can be given, the prices, and the bill")
def accept_order(order_id: int, body: AcceptOrderIn, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    return service.accept_order(db, user, order_id, body)


@router.post("/orders/{order_id}/reject", response_model=SupplyOrderOut, summary="Cannot give this order")
def reject_order(order_id: int, body: ReasonIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.reject_order(db, user, order_id, body.reason)


@router.post("/orders/{order_id}/dispatch", response_model=SupplyOrderOut, summary="The goods are on the way")
def dispatch_order(order_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.dispatch_order(db, user, order_id)


@router.get("/payments", response_model=SupplyPaymentsOut, summary="What shops paid, and what is to come")
def payments(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.payments(db, user)


@router.put("/upi", response_model=SupplyPaymentsOut, summary="My UPI ID, for connected shops (empty = remove it)")
def save_upi(body: UpiIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    pay.save_upi(db, user, body)
    return service.payments(db, user)


@router.get("/products", response_model=list[ProductOut], summary="What I sell")
def my_products(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return products.mine(db, user)


@router.post("/products", response_model=list[ProductOut], status_code=status.HTTP_201_CREATED,
             summary="Add products (one, or many from the ready list)")
def add_products(body: ProductsIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return products.add(db, user, body.products)


@router.put("/products/{product_id}", response_model=ProductOut, summary="Change a product's name, price, available")
def change_product(product_id: int, body: ProductChangeIn, user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    return products.change(db, user, product_id, body)


@router.delete("/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Stop selling a product")
def remove_product(product_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    products.remove(db, user, product_id)


@router.get("/products/{product_id}/stock", response_model=ProductStockOut, summary="How much I have, and its history")
def product_stock(product_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return counts.get(db, user, product_id)


@router.put("/products/{product_id}/stock", response_model=ProductStockOut, summary="Count it or not, and when to warn")
def change_stock(product_id: int, body: ProductStockIn, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    return counts.change(db, user, product_id, body)


@router.post("/products/{product_id}/moves", response_model=ProductStockOut, status_code=status.HTTP_201_CREATED,
             summary="Stock in, out, or counted")
def add_move(product_id: int, body: ProductMoveIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return counts.add(db, user, product_id, body)


@router.get("/report", response_model=ReportOut, summary="Given, received, by shop and by product")
def report(start: date, end: date, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return reports.report(db, user, start, end)
