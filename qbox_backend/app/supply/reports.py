"""What the supplier gave and got between two days. Read from the same records as
the ledger, so it always agrees with it."""

from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import (
    Confirm,
    OrderStatus,
    StockUnit,
    SupplierEntry,
    SupplierEntryKind,
    SupplierEntryLine,
    SupplierOrder,
    User,
)
from app.supply import rules, service
from app.supply.schemas import ReportOut, ReportProductOut, ReportShopOut, SupplyShopOut
from app.udhaar.schemas import INDIA

MAX_DAYS = 800
PRODUCTS_SHOWN = 200


def report(db: Session, user: User, start: date, end: date) -> ReportOut:
    if end < start or (end - start).days > MAX_DAYS:
        raise ApiError(400, "INVALID_INPUT", "Choose dates up to 2 years apart")
    home = service.home(db, user)  # also checks the role
    mine = service.links_of(db, user)
    shop_of = {link.id: link.shop_user_id for link in mine.values()}
    since = datetime.combine(start, time.min, INDIA)
    until = datetime.combine(end + timedelta(days=1), time.min, INDIA)
    inside = (SupplierEntry.link_id.in_(shop_of), SupplierEntry.deleted_at.is_(None),
              SupplierEntry.entry_at >= since, SupplierEntry.entry_at < until)

    given: dict[int, int] = defaultdict(int)
    received: dict[int, int] = defaultdict(int)
    waiting = 0
    by = (SupplierEntry.link_id, SupplierEntry.kind, SupplierEntry.confirm, SupplierEntry.by_supplier)
    for link_id, kind, confirm, by_supplier, amount in db.execute(
        select(*by, func.sum(SupplierEntry.amount_paise)).where(*inside).group_by(*by)
    ).all():
        purchase = kind == SupplierEntryKind.PURCHASE.value
        if rules.counts(kind, confirm, by_supplier, for_shop=False):
            (given if purchase else received)[shop_of[link_id]] += int(amount)
        elif confirm == Confirm.WAITING.value and not purchase:
            waiting += int(amount)

    # A shop that connected again has several connections: the newest one is now.
    newest = {link.supplier_id: link.id for link in sorted(mine.values(), key=lambda x: x.id)}
    by_shop: dict[int, list[SupplyShopOut]] = defaultdict(list)
    for s in home.shops:
        if s.link_id in newest.values():
            by_shop[shop_of[s.link_id]].append(s)
    shops = []
    for shop, theirs in by_shop.items():
        to_get = sum(s.balance_paise for s in theirs)
        if given[shop] or received[shop] or to_get:
            shops.append(ReportShopOut(shop_name=theirs[0].shop_name, given_paise=given[shop],
                                       received_paise=received[shop], to_get_paise=to_get,
                                       connected=any(s.connected for s in theirs)))
    shops.sort(key=lambda s: (-s.given_paise, -s.to_get_paise, s.shop_name.lower()))

    orders = {OrderStatus(status): count for status, count in db.execute(
        select(SupplierOrder.status, func.count())
        .where(SupplierOrder.link_id.in_(shop_of), SupplierOrder.created_at >= since, SupplierOrder.created_at < until)
        .group_by(SupplierOrder.status)
    ).all()}
    return ReportOut(
        given_paise=sum(given.values()),
        received_paise=sum(received.values()),
        waiting_paise=waiting,
        to_get_paise=home.total_due_paise,
        orders=orders,
        shops=shops,
        # Goods the shop has not agreed to yet are not counted.
        products=_products(db, (*inside, or_(~SupplierEntry.by_supplier,
                                             SupplierEntry.confirm == Confirm.CONFIRMED.value))),
    )


def _products(db: Session, inside) -> list[ReportProductOut]:
    """What was given most, by the names on the bills."""
    names: dict[tuple[str, str], str] = {}
    qty: dict[tuple[str, str], int] = defaultdict(int)
    amount: dict[tuple[str, str], int | None] = defaultdict(lambda: None)
    for name, unit, quantity, cost in db.execute(
        select(SupplierEntryLine.name, SupplierEntryLine.unit, SupplierEntryLine.qty_milli, SupplierEntryLine.cost_paise)
        .join(SupplierEntry, SupplierEntry.id == SupplierEntryLine.entry_id)
        .where(*inside).order_by(SupplierEntryLine.id)
    ).all():
        key = (name.lower(), unit)
        names[key] = name
        qty[key] += quantity
        if cost is not None:
            amount[key] = (amount[key] or 0) + round(quantity * cost / 1000)
    out = [ReportProductOut(name=names[k], unit=StockUnit(k[1]), qty_milli=qty[k], amount_paise=amount[k]) for k in names]
    out.sort(key=lambda p: (-(p.amount_paise or 0), -p.qty_milli, p.name.lower()))
    return out[:PRODUCTS_SHOWN]
