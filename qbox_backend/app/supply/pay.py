"""Paying a supplier.

- The supplier writes their own UPI ID. Only shops connected with them get it,
  fresh each time they pay, and the money goes straight to the supplier.
- QBOX cannot see that money: what a shop says it paid counts only after the
  supplier confirms it (like every payment, see service.py).
"""

from collections import defaultdict

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import Role, SupplierEntry, SupplierEntryKind, SupplyPay, User
from app.payments.schemas import UpiIn


def save_upi(db: Session, user: User, body: UpiIn) -> None:
    if Role.SUPPLIER.value not in {r.role for r in user.roles}:
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")
    row = db.get(SupplyPay, user.id)
    if row is None:
        row = SupplyPay(user_id=user.id)
        db.add(row)
    row.upi_id = body.upi_id
    row.upi_name = body.upi_name if body.upi_id else None
    db.commit()


def upi_of(db: Session, user_ids: set[int]) -> dict[int, SupplyPay]:
    """Those who have a UPI ID."""
    if not user_ids:
        return {}
    rows = db.scalars(select(SupplyPay).where(SupplyPay.user_id.in_(user_ids), SupplyPay.upi_id.is_not(None)))
    return {r.user_id: r for r in rows}


def for_orders(db: Session, order_ids: list[int]) -> dict[int, dict[str | None, int]]:
    """What was paid for each order, by the supplier's answer."""
    out: dict[int, dict[str | None, int]] = defaultdict(lambda: defaultdict(int))
    if order_ids:
        rows = db.execute(
            select(SupplierEntry.order_id, SupplierEntry.confirm, func.sum(SupplierEntry.amount_paise))
            .where(SupplierEntry.order_id.in_(order_ids), SupplierEntry.kind == SupplierEntryKind.PAYMENT.value,
                   SupplierEntry.deleted_at.is_(None))
            .group_by(SupplierEntry.order_id, SupplierEntry.confirm)
        ).all()
        for order_id, confirm, amount in rows:
            out[order_id][confirm] += int(amount)
    return out
