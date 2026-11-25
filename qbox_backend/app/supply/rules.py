"""What counts in the account between a shop and its supplier.

What someone writes against themselves counts at once: goods the shop says it
got, money the supplier says they got. What they write in their own favour counts
only when the other side confirms it.
"""

from app.models import Confirm, SupplierEntryKind


def counts(kind: str, confirm: str | None, by_supplier: bool, *, for_shop: bool) -> bool:
    if (kind == SupplierEntryKind.PURCHASE.value) != by_supplier:
        return True
    if confirm is None or confirm == Confirm.CONFIRMED.value:
        return True
    # Disconnected before it was answered: the shop's own book keeps its payment.
    return confirm == Confirm.CLOSED.value and for_shop and not by_supplier
