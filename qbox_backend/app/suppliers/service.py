"""Supplier rules.

- A shop sees and changes only its own suppliers. Another shop's supplier,
  entry or order looks exactly like a missing one (404).
- The balance (what the shop owes) is always calculated from the entries;
  deleted entries do not count, and entries are never erased.
- A purchase's items are added to stock (through the stock rules), and its
  buying price becomes the item's buying price. Deleting the purchase takes
  that stock back out with a correction, so stock history stays complete.
- The same entry or order sent twice (same client_ref) is kept once.
- With a connected supplier (see app/supply), what is written is shared with
  them: a payment counts once they confirm it, and what both agreed on cannot
  be deleted. They write too, and the shop confirms (see app/supply/rules.py).
"""

from collections import defaultdict
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import otp
from app.config import get_settings
from app.errors import ApiError
from app.models import (
    Confirm,
    LinkStatus,
    OrderStatus,
    OtpCode,
    OtpPurpose,
    PayMethod,
    PayPlan,
    Role,
    StockUnit,
    Supplier,
    SupplierEntry,
    SupplierEntryKind,
    SupplierEntryLine,
    SupplierOrder,
    SupplierOrderLine,
    SupplierProfile,
    SupplyLink,
    SupplyProduct,
    User,
)
from app.stock import service as stock
from app.suppliers.schemas import (
    EntryIn,
    EntryOut,
    LineIn,
    LineOut,
    OrderIn,
    OrderOut,
    ReceiveIn,
    SupplierChangeIn,
    SupplierCodeIn,
    SupplierCodeOut,
    SupplierDetailOut,
    SupplierIn,
    SupplierLinkOut,
    SupplierOut,
    SupplierPayOut,
    SupplierProductOut,
    SuppliersOut,
)
from app.supply import counts, links, pay, products, rules
from app.udhaar.schemas import INDIA

MAX_SUPPLIERS_PER_SHOP = 2000
MAX_ENTRIES_PER_SUPPLIER = 20_000
ENTRIES_SHOWN = 500
ORDERS_SHOWN = 100
OPEN_ORDERS = (OrderStatus.SENT.value, OrderStatus.ACCEPTED.value, OrderStatus.DISPATCHED.value)
# Payments the supplier has not agreed to do not count yet.
NOT_AGREED = (Confirm.WAITING.value, Confirm.DISPUTED.value)


class _Account:
    """A supplier's balance and dates, worked out from the entries."""

    def __init__(self) -> None:
        self.balance = 0
        self.last_entry_at: datetime | None = None
        self.next_due: date | None = None
        self.open_orders = 0
        self.to_confirm = 0


# ---------- suppliers ----------


def get_suppliers(db: Session, user: User) -> SuppliersOut:
    _require(user)
    suppliers = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == user.id, Supplier.archived_at.is_(None))
    ).all()
    accounts = _accounts(db, [s.id for s in suppliers])
    linked = links.latest(db, [s.id for s in suppliers])
    upi = pay.upi_of(db, {x.supplier_user_id for x in linked.values()})
    out = [_supplier_out(s, accounts.get(s.id, _Account()), linked.get(s.id), upi) for s in suppliers]
    out.sort(key=lambda s: (-s.balance_paise, s.name.lower()))
    return SuppliersOut(total_due_paise=sum(s.balance_paise for s in out if s.balance_paise > 0), suppliers=out)


def add_supplier(db: Session, user: User, body: SupplierIn) -> SupplierOut:
    _require(user)
    existing = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == user.id, Supplier.client_ref == body.client_ref)
    ).first()
    if existing is not None:
        return _detail_supplier(db, existing)
    _check_name(db, user, body.name)
    count = db.scalar(
        select(func.count()).select_from(Supplier)
        .where(Supplier.shop_user_id == user.id, Supplier.archived_at.is_(None))
    )
    if count >= MAX_SUPPLIERS_PER_SHOP:
        raise ApiError(400, "TOO_MANY_SUPPLIERS", f"You can keep up to {MAX_SUPPLIERS_PER_SHOP} suppliers")
    if body.otp is not None:
        links.check_can_connect(db, user, body.mobile)
        otp.verify_otp(db, body.mobile, OtpPurpose.SUPPLIER_ADD, body.otp, requested_by=user.id, detail=_code_for(None, 0))
    supplier = Supplier(shop_user_id=user.id, name=body.name, mobile=body.mobile, supplies=body.supplies,
                        note=body.note, client_ref=body.client_ref)
    db.add(supplier)
    try:
        db.flush()
        if body.otp is not None:
            links.verified(db, supplier, 0)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _exists(body.name) from None
    return _detail_supplier(db, supplier)


def get_supplier(db: Session, user: User, supplier_id: int) -> SupplierDetailOut:
    supplier = _own_supplier(db, user, supplier_id)
    entries = db.scalars(
        select(SupplierEntry)
        .where(SupplierEntry.supplier_id == supplier.id)
        .order_by(SupplierEntry.entry_at.desc(), SupplierEntry.id.desc())
        .limit(ENTRIES_SHOWN)
    ).all()
    orders = db.scalars(
        select(SupplierOrder)
        .where(SupplierOrder.supplier_id == supplier.id)
        .order_by(SupplierOrder.created_at.desc(), SupplierOrder.id.desc())
        .limit(ORDERS_SHOWN)
    ).all()
    entry_lines = _lines(db, SupplierEntryLine, SupplierEntryLine.entry_id, [e.id for e in entries])
    order_lines = _lines(db, SupplierOrderLine, SupplierOrderLine.order_id, [o.id for o in orders])
    return SupplierDetailOut(
        supplier=_detail_supplier(db, supplier),
        entries=[_entry_out(e, entry_lines.get(e.id, [])) for e in entries],
        orders=_orders_out(db, orders, order_lines),
    )


def change_supplier(db: Session, user: User, supplier_id: int, body: SupplierChangeIn) -> SupplierOut:
    supplier = _own_supplier(db, user, supplier_id)
    if body.name.lower() != supplier.name.lower():
        _check_name(db, user, body.name)
    if body.mobile != supplier.mobile:
        if links.on(db, supplier.id) is not None:
            raise ApiError(409, "CONNECTED", f"Disconnect from {supplier.name} first to change the number")
        links.end(db, supplier.id, by_shop=True)  # a question to the old number
        supplier.verified_at = None
    supplier.name = body.name
    supplier.mobile = body.mobile
    supplier.supplies = body.supplies
    supplier.note = body.note
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise _exists(body.name) from None
    return _detail_supplier(db, supplier)


def archive_supplier(db: Session, user: User, supplier_id: int) -> SupplierOut:
    """Removes a supplier from the list. Their account history is kept."""
    supplier = _own_supplier(db, user, supplier_id)
    links.end(db, supplier.id, by_shop=True)
    supplier.archived_at = datetime.now(UTC)
    db.commit()
    return _detail_supplier(db, supplier)


# ---------- connecting with the supplier's QBOX account ----------


def send_new_code(db: Session, user: User, body: SupplierCodeIn) -> SupplierCodeOut:
    """Adding a supplier, step 1. Step 2 is add_supplier with the code."""
    _require(user)
    _check_name(db, user, body.name)
    links.check_can_connect(db, user, body.mobile)
    return _send_code(db, user, body.mobile, None, 0)


def send_code(db: Session, user: User, supplier_id: int) -> SupplierCodeOut:
    """Connecting with a supplier already in the list. The message says what the
    shop owes now."""
    supplier = _own_supplier(db, user, supplier_id)
    links.check_can_connect(db, user, supplier.mobile, supplier.id)
    return _send_code(db, user, supplier.mobile, supplier.id, balances(db, [supplier.id]).get(supplier.id, 0))


def verify(db: Session, user: User, supplier_id: int, code: str) -> SupplierOut:
    supplier = _own_supplier(db, user, supplier_id)
    links.check_can_connect(db, user, supplier.mobile, supplier.id)
    owed = balances(db, [supplier.id]).get(supplier.id, 0)
    otp.verify_otp(db, supplier.mobile, OtpPurpose.SUPPLIER_ADD, code, requested_by=user.id,
                   detail=_code_for(supplier.id, owed))
    links.lock(db, supplier.id)
    if balances(db, [supplier.id]).get(supplier.id, 0) != owed:  # an entry slipped in
        db.rollback()
        raise ApiError(409, "CODE_OUTDATED", "The amount changed after the code was sent. Please send a new code")
    try:
        links.verified(db, supplier, owed)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "ALREADY_CONNECTED", "This number is already connected with your shop") from None
    return _detail_supplier(db, supplier)


def _code_for(supplier_id: int | None, owed: int) -> str:
    """What a code is for: it cannot connect another supplier, or another amount."""
    return f"{supplier_id or 'new'}:{owed}"


def _send_code(db: Session, user: User, mobile: str, supplier_id: int | None, owed: int) -> SupplierCodeOut:
    settings = get_settings()
    sent_last_hour = db.scalar(
        select(func.count()).select_from(OtpCode)
        .where(OtpCode.requested_by == user.id, OtpCode.purpose == OtpPurpose.SUPPLIER_ADD.value,
               OtpCode.created_at > datetime.now(UTC) - timedelta(hours=1))
    )
    if sent_last_hour >= settings.udhaar_invites_per_hour:
        raise ApiError(429, "INVITE_LIMIT", "Too many codes sent in the last hour. Please try again later")
    shop_name = user.shop.shop_name if user.shop else "A shop"
    amount = f"Rs {abs(owed) / 100:.2f}".removesuffix(".00")
    says = f"They say they owe you {amount}" if owed >= 0 else f"They say they paid you {amount} in advance"

    def message(code: str, minutes: int) -> str:
        return (f"{code} is the code for {shop_name} to connect with you on QBOX. {says}. "
                f"Share it only if this is right. Valid {minutes} min.")

    code = otp.send_otp(db, mobile, OtpPurpose.SUPPLIER_ADD, requested_by=user.id, message=message,
                        detail=_code_for(supplier_id, owed))
    return SupplierCodeOut(
        mobile=mobile,
        balance_paise=owed,
        expires_in_seconds=settings.otp_expiry_seconds,
        resend_in_seconds=settings.otp_resend_seconds,
        dev_otp=code if settings.otp_expose else None,
    )


def supplier_products(db: Session, user: User, supplier_id: int) -> list[SupplierProductOut]:
    """What a connected supplier sells: what they have first."""
    supplier = _own_supplier(db, user, supplier_id)
    link = links.on(db, supplier.id)
    if link is None:
        raise ApiError(409, "NOT_CONNECTED", f"Connect with {supplier.name} to see their products")
    return [
        SupplierProductOut(id=p.id, name=p.name, catalog_code=p.catalog_code, unit=StockUnit(p.unit),
                           price_paise=p.price_paise, available=can_order)
        for p, can_order in products.for_shops(db, link.supplier_user_id)
    ]


def pay_info(db: Session, user: User, supplier_id: int) -> SupplierPayOut:
    """Where the money goes. Always from the supplier's own account, never typed
    by the shop."""
    supplier = _own_supplier(db, user, supplier_id)
    link = links.on(db, supplier.id)
    if link is None:
        raise ApiError(409, "NOT_CONNECTED", f"Connect with {supplier.name} to pay them here")
    row = pay.upi_of(db, {link.supplier_user_id}).get(link.supplier_user_id)
    profile = db.get(SupplierProfile, link.supplier_user_id)
    name = (row.upi_name if row else None) or (profile.supplier_name if profile else supplier.name)
    return SupplierPayOut(name=name, upi_id=row.upi_id if row else None)


def disconnect(db: Session, user: User, supplier_id: int) -> SupplierOut:
    supplier = _own_supplier(db, user, supplier_id)
    links.end(db, supplier.id, by_shop=True)
    db.commit()
    return _detail_supplier(db, supplier)


# ---------- the account: purchases and payments ----------


def add_entry(db: Session, user: User, supplier_id: int, body: EntryIn) -> EntryOut:
    supplier = _own_supplier(db, user, supplier_id)
    existing = _entry_by_ref(db, supplier.id, body.client_ref)
    if existing is not None:
        return _entry_out(existing, _lines_of(db, existing.id))
    links.lock(db, supplier.id)
    count = db.scalar(
        select(func.count()).select_from(SupplierEntry).where(SupplierEntry.supplier_id == supplier.id)
    )
    if count >= MAX_ENTRIES_PER_SUPPLIER:
        raise ApiError(400, "TOO_MANY_ENTRIES", "This supplier has too many entries")
    if body.order_id is not None:
        order = db.get(SupplierOrder, body.order_id)
        if order is None or order.supplier_id != supplier.id:
            db.rollback()
            raise ApiError(404, "ORDER_NOT_FOUND", "This order is not available")
    lines = _in_stock(db, user, body.lines, body.client_ref)
    entry = _record(db, user, supplier, body.kind, body.amount_paise, body.note, body.entry_at, body.due_date,
                    body.method, lines, body.client_ref, paid_now=body.paid_now, order_id=body.order_id)
    try:
        db.commit()
    except IntegrityError:  # the same entry arrived twice at the same moment
        db.rollback()
        entry = _entry_by_ref(db, supplier.id, body.client_ref)
        if entry is None:
            raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _entry_out(entry, _lines_of(db, entry.id))


def delete_entry(db: Session, user: User, entry_id: int, reason: str) -> EntryOut:
    """Marks an entry deleted (kept, with the reason). A deleted purchase takes
    its items back out of stock."""
    _require(user)
    entry = db.get(SupplierEntry, entry_id)
    supplier = db.get(Supplier, entry.supplier_id) if entry else None
    if entry is None or supplier is None or supplier.shop_user_id != user.id:
        raise ApiError(404, "ENTRY_NOT_FOUND", "This entry no longer exists")
    lines = _lines_of(db, entry.id)
    links.lock(db, supplier.id)
    db.refresh(entry)
    if entry.by_supplier:
        db.rollback()
        raise ApiError(409, "NOT_YOURS", f"{supplier.name} wrote this. Say it is not right instead")
    if entry.deleted_at is None:
        _check_can_delete(db, supplier, entry)
        entry.deleted_at = datetime.now(UTC)
        entry.delete_reason = reason.strip()
        for line in lines:
            stock.purchase_undo(db, user, line.item_id, line.qty_milli,
                                f"Purchase from {supplier.name} deleted: {entry.delete_reason}",
                                f"undo-{entry.id}-{line.id}")
        db.commit()
    return _entry_out(entry, lines)


def confirm_entry(db: Session, user: User, entry_id: int) -> EntryOut:
    """What the supplier wrote is right. Goods come into the shop's stock."""
    entry, supplier = _theirs_to_answer(db, user, entry_id)
    lines = _lines_of(db, entry.id)
    if entry.confirm != Confirm.CONFIRMED.value:
        entry.confirm = Confirm.CONFIRMED.value
        entry.dispute_reason = None
        entry.answered_at = datetime.now(UTC)
        for line in lines:
            item = stock.keep_item(db, user, line.item_id, line.name, line.unit, line.catalog_code,
                                   f"entry-line-{line.id}")
            stock.purchase_in(db, user, item.id, line.qty_milli, f"From {supplier.name}", entry.entry_at,
                              f"purchase-line-{line.id}")
            if line.cost_paise is not None:
                item.cost_paise = line.cost_paise
            line.item_id = item.id
    db.commit()
    return _entry_out(entry, lines)


def dispute_entry(db: Session, user: User, entry_id: int, reason: str) -> EntryOut:
    """Not right: the supplier is told why, and can delete it and write it again."""
    entry, supplier = _theirs_to_answer(db, user, entry_id)
    if entry.confirm == Confirm.CONFIRMED.value:
        db.rollback()
        raise ApiError(409, "ALREADY_CONFIRMED", f"You already confirmed this. Please talk to {supplier.name}")
    entry.confirm = Confirm.DISPUTED.value
    entry.dispute_reason = reason.strip()
    entry.answered_at = datetime.now(UTC)
    db.commit()
    return _entry_out(entry, _lines_of(db, entry.id))


def _theirs_to_answer(db: Session, user: User, entry_id: int) -> tuple[SupplierEntry, Supplier]:
    """An entry a connected supplier wrote, locked."""
    _require(user)
    entry = db.get(SupplierEntry, entry_id)
    supplier = db.get(Supplier, entry.supplier_id) if entry else None
    if entry is None or supplier is None or supplier.shop_user_id != user.id or not entry.by_supplier:
        raise ApiError(404, "ENTRY_NOT_FOUND", "This entry no longer exists")
    links.lock(db, supplier.id)
    db.refresh(entry)
    link = links.on(db, supplier.id)
    if link is None or link.id != entry.link_id:
        db.rollback()
        raise ApiError(409, "DISCONNECTED", f"You are no longer connected with {supplier.name}")
    if entry.deleted_at is not None:
        db.rollback()
        raise ApiError(409, "ENTRY_DELETED", f"{supplier.name} deleted this entry")
    return entry, supplier


# ---------- orders ----------


def add_order(db: Session, user: User, supplier_id: int, body: OrderIn) -> OrderOut:
    supplier = _own_supplier(db, user, supplier_id)
    existing = db.scalars(
        select(SupplierOrder).where(SupplierOrder.supplier_id == supplier.id,
                                    SupplierOrder.client_ref == body.client_ref)
    ).first()
    if existing is not None:
        return _order_out(db, existing)
    links.lock(db, supplier.id)
    link = links.on(db, supplier.id)
    if link and body.pay_plan == PayPlan.UPI and not pay.upi_of(db, {link.supplier_user_id}):
        db.rollback()
        raise ApiError(409, "NO_UPI", f"{supplier.name} has not added a UPI ID yet. Choose another way to pay")
    order = SupplierOrder(supplier_id=supplier.id, status=OrderStatus.SENT.value, note=body.note,
                          client_ref=body.client_ref, link_id=link.id if link else None,
                          pay_plan=body.pay_plan.value if link and body.pay_plan else None,
                          pay_by=body.pay_by if link else None)
    db.add(order)
    db.flush()
    match = stock.matcher(db, user)
    can_order = {p.id: yes for p, yes in products.for_shops(db, link.supplier_user_id)} if link else {}
    for line in body.lines:
        if line.product_id is not None:
            product = db.get(SupplyProduct, line.product_id)
            if (link is None or product is None or product.supplier_user_id != link.supplier_user_id
                    or product.archived_at is not None):
                db.rollback()
                raise ApiError(404, "PRODUCT_NOT_FOUND", "A product you chose is no longer there. Please choose again")
            if not can_order.get(product.id):
                db.rollback()
                raise ApiError(409, "NOT_AVAILABLE", f"{product.name} is not available now")
            item = match(product.name, product.unit, product.catalog_code)
            db.add(SupplierOrderLine(order_id=order.id, product_id=product.id, item_id=item.id if item else None,
                                     name=product.name, unit=product.unit, catalog_code=product.catalog_code,
                                     qty_milli=line.qty_milli, cost_paise=product.price_paise))
            continue
        if line.name is not None:
            item = match(line.name, line.unit.value, line.catalog_code)
            db.add(SupplierOrderLine(order_id=order.id, item_id=item.id if item else None, name=line.name,
                                     unit=line.unit.value, catalog_code=line.catalog_code, qty_milli=line.qty_milli))
            continue
        item = stock.own_item(db, user, line.item_id)
        db.add(SupplierOrderLine(order_id=order.id, item_id=item.id, name=item.name, unit=item.unit,
                                 catalog_code=item.catalog_code, qty_milli=line.qty_milli))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _order_out(db, order)


def receive_order(db: Session, user: User, order_id: int, body: ReceiveIn) -> OrderOut:
    """The goods came: a purchase with what actually came (stock goes up)."""
    order, supplier = _own_order(db, user, order_id)
    links.lock(db, supplier.id)
    db.refresh(order)
    if order.status == OrderStatus.RECEIVED.value:
        return _order_out(db, order)
    if order.status not in OPEN_ORDERS:
        raise ApiError(409, "ORDER_CLOSED", "This order was cancelled" if order.status == OrderStatus.CANCELLED.value
                       else "The supplier rejected this order")
    if body.due_date and body.paid_now:
        raise ApiError(400, "INVALID_INPUT", "A purchase paid now has no due date")
    if body.paid_now and any(pay.for_orders(db, [order.id])[order.id].get(x)
                             for x in (None, Confirm.WAITING.value, Confirm.CONFIRMED.value)):
        db.rollback()
        raise ApiError(409, "ALREADY_PAID", "A payment for this order is already written. Turn off Paid now")
    lines = _what_came(db, user, order, body)
    now = datetime.now(UTC)
    # The supplier's own bill: both agree already.
    agreed = order.link_id is not None and order.total_paise == body.amount_paise
    _record(db, user, supplier, SupplierEntryKind.PURCHASE, body.amount_paise, body.note or "Order received", now,
            body.due_date, body.method, lines, body.client_ref, paid_now=body.paid_now, order_id=order.id,
            agreed=agreed)
    link = links.on(db, supplier.id)
    if link is not None and order.link_id == link.id:
        # Not marked as sent by the supplier: it left their count all the same.
        sent = [x for x in _order_lines_of(db, order.id) if x.available]
        counts.goods_out(db, link.supplier_user_id, sent, f"order-{order.id}",
                         f"To {user.shop.shop_name if user.shop else 'Shop'}")
    order.status = OrderStatus.RECEIVED.value
    order.received_at = now
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _order_out(db, order)


def _what_came(db: Session, user: User, order: SupplierOrder, body: ReceiveIn) -> list[LineIn]:
    """The order's lines, and anything extra that came."""
    ordered = {x.id: x for x in _order_lines_of(db, order.id)}
    lines: list[LineIn] = []
    for line in body.lines:
        if line.order_line_id is None:
            lines.append(line)
            continue
        asked = ordered.get(line.order_line_id)
        if asked is None:
            db.rollback()
            raise ApiError(400, "INVALID_INPUT", "Some details are missing or invalid")
        item = stock.keep_item(db, user, asked.item_id, asked.name, asked.unit, asked.catalog_code,
                               f"order-line-{asked.id}")
        lines.append(LineIn(item_id=item.id, qty_milli=line.qty_milli, cost_paise=line.cost_paise))
    return _in_stock(db, user, lines, body.client_ref)


def _in_stock(db: Session, user: User, lines: list[LineIn], client_ref: str) -> list[LineIn]:
    """As the shop's own stock items. What it does not keep yet is added."""
    out: list[LineIn] = []
    for n, line in enumerate(lines):
        item_id = line.item_id
        if item_id is None:
            item_id = stock.keep_item(db, user, None, line.name, line.unit.value, line.catalog_code,
                                      f"buy{n}-{client_ref[:33]}").id
        out.append(LineIn(item_id=item_id, qty_milli=line.qty_milli, cost_paise=line.cost_paise))
    if len({line.item_id for line in out}) != len(out):
        db.rollback()
        raise ApiError(400, "INVALID_INPUT", "The same item is there twice")
    return out


def cancel_order(db: Session, user: User, order_id: int) -> OrderOut:
    order, supplier = _own_order(db, user, order_id)
    links.lock(db, supplier.id)
    db.refresh(order)
    if order.status == OrderStatus.DISPATCHED.value and links.on(db, supplier.id) is not None:
        db.rollback()
        raise ApiError(409, "ON_THE_WAY", "The goods are on the way. Please talk to the supplier")
    if order.status in OPEN_ORDERS:
        order.status = OrderStatus.CANCELLED.value
        order.cancelled_at = datetime.now(UTC)
    db.commit()
    return _order_out(db, order)


# ---------- helpers ----------


def _record(db: Session, user: User, supplier: Supplier, kind: SupplierEntryKind, amount: int, note: str | None,
            entry_at: datetime, due_date: date | None, method: PayMethod | None, lines: list[LineIn],
            client_ref: str, paid_now: bool = False, order_id: int | None = None,
            agreed: bool = False) -> SupplierEntry:
    """Adds the entry (not committed). Purchase items go into stock; a purchase
    paid on the spot gets its payment too."""
    is_purchase = kind == SupplierEntryKind.PURCHASE
    link = links.on(db, supplier.id)
    shared = {"link_id": link.id, "confirm": Confirm.WAITING.value} if link else {}
    entry = SupplierEntry(
        supplier_id=supplier.id,
        kind=kind.value,
        amount_paise=amount,
        note=note,
        entry_at=entry_at,
        due_date=due_date if is_purchase and not paid_now else None,
        method=method.value if method and not is_purchase else None,
        order_id=order_id,
        client_ref=client_ref,
        **shared,
    )
    if link and agreed:
        entry.confirm = Confirm.CONFIRMED.value
    db.add(entry)
    db.flush()
    for line in lines if is_purchase else []:
        item = stock.purchase_in(db, user, line.item_id, line.qty_milli, f"From {supplier.name}", entry_at,
                                 f"purchase-{entry.id}-{line.item_id}")
        if line.cost_paise is not None:
            item.cost_paise = line.cost_paise  # the latest buying price
        db.add(SupplierEntryLine(entry_id=entry.id, item_id=item.id, name=item.name, unit=item.unit,
                                 qty_milli=line.qty_milli, cost_paise=line.cost_paise))
    if is_purchase and paid_now:
        db.add(SupplierEntry(supplier_id=supplier.id, kind=SupplierEntryKind.PAYMENT.value, amount_paise=amount,
                             note="Paid on purchase", entry_at=entry_at, order_id=order_id,
                             method=(method or PayMethod.CASH).value, client_ref=f"{client_ref[:34]}-paid",
                             **shared))
    db.flush()
    return entry


def _check_can_delete(db: Session, supplier: Supplier, entry: SupplierEntry) -> None:
    link = links.on(db, supplier.id)
    if entry.confirm == Confirm.CONFIRMED.value:
        why = f"{supplier.name} confirmed this, so it cannot be deleted. Add a new entry to correct it"
    elif link is not None and entry.link_id != link.id and entry.id <= (link.opening_entry_id or 0):
        why = f"This is part of the opening balance you agreed with {supplier.name}. Add a new entry to correct it"
    else:
        return
    db.rollback()
    raise ApiError(409, "AGREED", why)


def balances(db: Session, supplier_ids: list[int]) -> dict[int, int]:
    """What the shop owes each supplier now (for connecting)."""
    return {key: account.balance for key, account in _accounts(db, supplier_ids).items()}


def _require(user: User) -> None:
    if Role.BUSINESS.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def _own_supplier(db: Session, user: User, supplier_id: int) -> Supplier:
    _require(user)
    supplier = db.get(Supplier, supplier_id)
    if supplier is None or supplier.shop_user_id != user.id or supplier.archived_at is not None:
        raise ApiError(404, "SUPPLIER_NOT_FOUND", "This supplier is not in your list")
    return supplier


def _own_order(db: Session, user: User, order_id: int) -> tuple[SupplierOrder, Supplier]:
    _require(user)
    order = db.get(SupplierOrder, order_id)
    supplier = db.get(Supplier, order.supplier_id) if order else None
    if order is None or supplier is None or supplier.shop_user_id != user.id:
        raise ApiError(404, "ORDER_NOT_FOUND", "This order is not available")
    return order, supplier


def _check_name(db: Session, user: User, name: str) -> None:
    taken = db.scalars(
        select(Supplier).where(Supplier.shop_user_id == user.id, func.lower(Supplier.name) == name.lower(),
                               Supplier.archived_at.is_(None))
    ).first()
    if taken is not None:
        raise _exists(name)


def _exists(name: str) -> ApiError:
    return ApiError(409, "SUPPLIER_EXISTS", f"{name} is already in your supplier list")


def _entry_by_ref(db: Session, supplier_id: int, client_ref: str) -> SupplierEntry | None:
    return db.scalars(
        select(SupplierEntry).where(SupplierEntry.supplier_id == supplier_id, SupplierEntry.client_ref == client_ref)
    ).first()


def _lines(db: Session, table, key, ids: list[int]) -> dict[int, list]:
    if not ids:
        return {}
    grouped: dict[int, list] = defaultdict(list)
    for line in db.scalars(select(table).where(key.in_(ids)).order_by(table.id)).all():
        grouped[getattr(line, key.key)].append(line)
    return grouped


def _lines_of(db: Session, entry_id: int) -> list[SupplierEntryLine]:
    return _lines(db, SupplierEntryLine, SupplierEntryLine.entry_id, [entry_id]).get(entry_id, [])


def _order_lines_of(db: Session, order_id: int) -> list[SupplierOrderLine]:
    return _lines(db, SupplierOrderLine, SupplierOrderLine.order_id, [order_id]).get(order_id, [])


def _accounts(db: Session, supplier_ids: list[int]) -> dict[int, _Account]:
    """Balance, last entry, next pay-by date and open orders per supplier.
    Payments pay off the oldest purchases first."""
    if not supplier_ids:
        return {}
    accounts: dict[int, _Account] = defaultdict(_Account)
    rows = db.execute(
        select(SupplierEntry.supplier_id, SupplierEntry.kind, SupplierEntry.amount_paise, SupplierEntry.entry_at,
               SupplierEntry.due_date, SupplierEntry.confirm, SupplierEntry.by_supplier)
        .where(SupplierEntry.supplier_id.in_(supplier_ids), SupplierEntry.deleted_at.is_(None))
        .order_by(SupplierEntry.entry_at, SupplierEntry.id)
    ).all()
    purchases: dict[int, list[tuple[int, date | None]]] = defaultdict(list)
    paid: dict[int, int] = defaultdict(int)
    for supplier_id, kind, amount, entry_at, due, confirm, by_supplier in rows:
        account = accounts[supplier_id]
        if by_supplier and confirm == Confirm.WAITING.value:
            account.to_confirm += 1
        if not rules.counts(kind, confirm, by_supplier, for_shop=True):
            pass
        elif kind == SupplierEntryKind.PURCHASE.value:
            account.balance += amount
            purchases[supplier_id].append((amount, due))
        else:
            account.balance -= amount
            paid[supplier_id] += amount
        if account.last_entry_at is None or entry_at > account.last_entry_at:
            account.last_entry_at = entry_at
    for supplier_id, items in purchases.items():
        left = paid[supplier_id]
        dues = []
        for amount, due in items:
            covered = min(left, amount)
            left -= covered
            if covered < amount and due is not None:
                dues.append(due)
        accounts[supplier_id].next_due = min(dues) if dues else None
    for supplier_id, count in db.execute(
        select(SupplierOrder.supplier_id, func.count())
        .where(SupplierOrder.supplier_id.in_(supplier_ids), SupplierOrder.status.in_(OPEN_ORDERS))
        .group_by(SupplierOrder.supplier_id)
    ).all():
        accounts[supplier_id].open_orders = count
    return dict(accounts)


def _detail_supplier(db: Session, supplier: Supplier) -> SupplierOut:
    link = links.latest(db, [supplier.id]).get(supplier.id)
    return _supplier_out(supplier, _accounts(db, [supplier.id]).get(supplier.id, _Account()), link,
                         pay.upi_of(db, {link.supplier_user_id}) if link else {})


def _supplier_out(supplier: Supplier, account: _Account, link: SupplyLink | None, upi: dict) -> SupplierOut:
    today = datetime.now(INDIA).date()
    return SupplierOut(
        id=supplier.id,
        name=supplier.name,
        mobile=supplier.mobile,
        supplies=supplier.supplies,
        note=supplier.note,
        balance_paise=account.balance,
        last_entry_at=account.last_entry_at,
        next_due=account.next_due,
        overdue=account.next_due is not None and account.next_due < today,
        open_orders=account.open_orders,
        verified=supplier.verified_at is not None,
        to_confirm=account.to_confirm,
        takes_upi=link is not None and link.status == LinkStatus.ON.value and link.supplier_user_id in upi,
        link=SupplierLinkOut(status=LinkStatus(link.status), reason=link.decline_reason,
                             since=link.ended_at or link.answered_at or link.asked_at) if link else None,
    )


def _line_out(line) -> LineOut:
    return LineOut(id=line.id, product_id=getattr(line, "product_id", None), item_id=line.item_id, name=line.name,
                   unit=StockUnit(line.unit), qty_milli=line.qty_milli, cost_paise=line.cost_paise,
                   available=getattr(line, "available", True))


def _entry_out(entry: SupplierEntry, lines: list[SupplierEntryLine]) -> EntryOut:
    return EntryOut(
        id=entry.id,
        supplier_id=entry.supplier_id,
        kind=SupplierEntryKind(entry.kind),
        amount_paise=entry.amount_paise,
        note=entry.note,
        entry_at=entry.entry_at,
        due_date=entry.due_date,
        method=PayMethod(entry.method) if entry.method else None,
        order_id=entry.order_id,
        lines=[_line_out(line) for line in lines],
        client_ref=entry.client_ref,
        by_supplier=bool(entry.by_supplier),
        confirm=Confirm(entry.confirm) if entry.confirm else None,
        dispute_reason=entry.dispute_reason,
        deleted_at=entry.deleted_at,
        delete_reason=entry.delete_reason,
    )


def _order_out(db: Session, order: SupplierOrder) -> OrderOut:
    return _orders_out(db, [order], {order.id: _order_lines_of(db, order.id)})[0]


def _orders_out(db: Session, orders, lines: dict[int, list[SupplierOrderLine]]) -> list[OrderOut]:
    paid = pay.for_orders(db, [o.id for o in orders])
    return [_one_order(o, lines.get(o.id, []), paid[o.id]) for o in orders]


def _one_order(order: SupplierOrder, lines: list[SupplierOrderLine], paid: dict[str | None, int]) -> OrderOut:
    return OrderOut(
        id=order.id,
        supplier_id=order.supplier_id,
        status=OrderStatus(order.status),
        note=order.note,
        lines=[_line_out(line) for line in lines],
        created_at=order.created_at or datetime.now(UTC),
        received_at=order.received_at,
        shared=order.link_id is not None,
        total_paise=order.total_paise,
        answer_note=order.answer_note,
        pay_plan=PayPlan(order.pay_plan) if order.pay_plan else None,
        pay_by=order.pay_by,
        paid_paise=sum(v for k, v in paid.items() if k not in NOT_AGREED),
        paying_paise=paid.get(Confirm.WAITING.value, 0),
    )
