"""Stock API paths. All need login and the BUSINESS role. The rules are in service.py."""

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import User
from app.stock import service
from app.stock.schemas import ItemChangeIn, ItemDetailOut, ItemIn, ItemOut, ItemsIn, MoveIn, MoveOut, StockOut

router = APIRouter(prefix="/api/stock", tags=["Stock"])


@router.get("/items", response_model=StockOut, summary="My stock: every item, its quantity, value and low stock")
def get_stock(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.get_stock(db, user)


@router.post("/items", response_model=ItemOut, status_code=status.HTTP_201_CREATED,
             summary="Add an item (with the stock already in the shop)")
def add_item(body: ItemIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_item(db, user, body)


@router.post("/items/bulk", response_model=list[ItemOut], status_code=status.HTTP_201_CREATED,
             summary="Add many items at once (quick start); names already in stock are skipped")
def add_items(body: ItemsIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_items(db, user, body.items)


@router.get("/items/{item_id}", response_model=ItemDetailOut, summary="One item and its history")
def get_item(item_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.get_item(db, user, item_id)


@router.put("/items/{item_id}", response_model=ItemOut, summary="Change name, prices or alert level")
def change_item(item_id: int, body: ItemChangeIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.change_item(db, user, item_id, body)


@router.post("/items/{item_id}/archive", response_model=ItemOut,
             summary="Remove an item from the list (its history is kept)")
def archive_item(item_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.archive_item(db, user, item_id)


@router.post("/items/{item_id}/moves", response_model=MoveOut, status_code=status.HTTP_201_CREATED,
             summary="Stock in, sold/used, or a correction (with a reason)")
def add_move(item_id: int, body: MoveIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.add_move(db, user, item_id, body)
