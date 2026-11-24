"""Payment rules.

- A shop sees only its own payments; a customer sees only the payments they
  made. Anything else looks like a missing payment (404), so nothing is revealed.
- A payment becomes PAID only when Razorpay says the money was captured, for
  exactly the amount asked; or, for MANUAL, when the shop confirms it by hand.
- Each Razorpay payment is counted once. A payment for udhaar adds one PAYMENT
  entry to that customer's book, however often its status is checked.
- On this PC Razorpay cannot reach us, so we ask Razorpay "is it paid?" while
  the app is waiting (at most every 2 seconds per payment).
"""

import logging
import threading
import time as clock
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import get_settings
from app.errors import ApiError
from app.models import (
    CustomerProfile,
    EntryKind,
    Gateway,
    Payment,
    PaymentSource,
    PaymentStatus,
    Role,
    ShopPaymentSettings,
    ShopProfile,
    UdhaarCustomer,
    UdhaarEntry,
    User,
)
from app.payments.gateways import Gateways, hint, lock
from app.payments.razorpay import FeatureOff, Paid, Razorpay
from app.payments.schemas import (
    CollectIn,
    PaymentOut,
    PaymentSettingsOut,
    PaymentsDayOut,
    RazorpayKeysIn,
    UdhaarPayIn,
    UdhaarPayOut,
    UpiIn,
    VerifyIn,
)
from app.udhaar import service as udhaar
from app.udhaar.schemas import INDIA

log = logging.getLogger("qbox.payments")

CHECK_EVERY = timedelta(seconds=2)
ORDER_MINUTES = 30
SHOP_REQUESTS_PER_10_MIN = 60
CUSTOMER_REQUESTS_PER_10_MIN = 10
REFRESH_IN_LIST = 5
# Until then Razorpay is asked before a waiting payment is given up, so money
# paid while the app was closed is still found days later.
GIVE_UP_AFTER = timedelta(days=7)

# Razorpay accounts without QR Codes switched on: key id -> when we found out.
# Counter payments then use a payment link; QR Codes is tried again after an hour.
_no_qr: dict[str, float] = {}
_no_qr_lock = threading.Lock()
_NO_QR_RETRY_SECONDS = 3600


# ---------- payment settings (shop) ----------


def get_settings_out(db: Session, user: User, gateways: Gateways) -> PaymentSettingsOut:
    require(user, Role.BUSINESS)
    return _settings_out(db.get(ShopPaymentSettings, user.id), gateways)


def set_upi(db: Session, user: User, body: UpiIn, gateways: Gateways) -> PaymentSettingsOut:
    require(user, Role.BUSINESS)
    row = settings_row(db, user)
    row.upi_id = body.upi_id
    row.upi_name = body.upi_name if body.upi_id else None
    db.commit()
    return _settings_out(row, gateways)


def connect_razorpay(db: Session, user: User, body: RazorpayKeysIn, gateways: Gateways) -> PaymentSettingsOut:
    """Checks the keys with Razorpay first; the secret is then stored encrypted."""
    require(user, Role.BUSINESS)
    gateways.make(body.key_id, body.key_secret).check_keys()
    row = settings_row(db, user)
    row.razorpay_key_id = body.key_id
    row.razorpay_secret = lock(body.key_secret)
    row.razorpay_connected_at = datetime.now(UTC)
    db.commit()
    return _settings_out(row, gateways)


def disconnect_razorpay(db: Session, user: User, gateways: Gateways) -> PaymentSettingsOut:
    require(user, Role.BUSINESS)
    row = db.get(ShopPaymentSettings, user.id)
    if row is not None:
        row.razorpay_key_id = None
        row.razorpay_secret = None
        row.razorpay_connected_at = None
        db.commit()
    return _settings_out(row, gateways)


# ---------- collecting (shop) ----------


def collect(db: Session, user: User, body: CollectIn, gateways: Gateways) -> PaymentOut:
    """A one-time QR for exactly this amount. Sending the same request twice
    (same client_ref, e.g. a retry) gives the same QR."""
    require(user, Role.BUSINESS)
    existing = by_client_ref(db, user.id, body.client_ref)
    if existing is not None:
        return out(db, existing)
    if body.udhaar_customer_id is not None:
        udhaar.shop_customer(db, user, body.udhaar_customer_id)
    account = gateways.for_shop(db.get(ShopPaymentSettings, user.id))
    if account is None:
        raise ApiError(409, "NO_ONLINE_PAYMENTS",
                       "Automatic payments are not set up. Connect Razorpay in Payment settings, "
                       "or use your own UPI ID")
    check_rate(db, Payment.shop_user_id == user.id, SHOP_REQUESTS_PER_10_MIN)

    note = clean(body.note)
    expires = datetime.now(UTC) + timedelta(minutes=get_settings().payment_qr_minutes)
    description = f"{shop_name(db, user.id)}: {note or 'payment'}"[:80]
    made = _make_qr(account, body.amount_paise, description, expires, {"qbox": "counter"})
    payment = Payment(
        shop_user_id=user.id,
        source=PaymentSource.COUNTER.value,
        status=PaymentStatus.WAITING.value,
        amount_paise=body.amount_paise,
        note=note,
        udhaar_customer_id=body.udhaar_customer_id,
        gateway=made.gateway.value,
        gateway_ref=made.ref,
        gateway_key_id=account.key_id,
        qr_image_url=made.qr_image_url,
        pay_url=made.pay_url,
        client_ref=body.client_ref,
        expires_at=expires,
    )
    db.add(payment)
    try:
        db.commit()
    except IntegrityError:  # the same request arrived twice at the same moment
        db.rollback()
        account.close(made.gateway, made.ref)
        return out(db, by_client_ref(db, user.id, body.client_ref))
    return out(db, payment)


def record_manual(db: Session, user: User, body: CollectIn) -> PaymentOut:
    """Money paid to the shop's own UPI ID, confirmed by the shop by hand."""
    require(user, Role.BUSINESS)
    existing = by_client_ref(db, user.id, body.client_ref)
    if existing is not None:
        return out(db, existing)
    if body.udhaar_customer_id is not None:
        udhaar.shop_customer(db, user, body.udhaar_customer_id)
    now = datetime.now(UTC)
    payment = Payment(
        shop_user_id=user.id,
        source=PaymentSource.MANUAL.value,
        status=PaymentStatus.PAID.value,
        amount_paise=body.amount_paise,
        note=clean(body.note),
        udhaar_customer_id=body.udhaar_customer_id,
        client_ref=body.client_ref,
        paid_at=now,
    )
    db.add(payment)
    try:
        db.flush()
        _add_udhaar_entry(db, payment)
        db.commit()
    except IntegrityError:
        db.rollback()
        return out(db, by_client_ref(db, user.id, body.client_ref))
    return out(db, payment)


def cancel(db: Session, user: User, payment_id: int, gateways: Gateways) -> PaymentOut:
    """Stops a QR. If it was paid in the meantime, it is recorded as paid instead."""
    payment = _visible(db, user, payment_id)
    if payment.shop_user_id != user.id:
        raise not_found()
    if payment.status != PaymentStatus.WAITING.value:
        return out(db, payment)
    account = _account_for(db, payment, gateways)
    if account is not None and payment.gateway:
        paid = account.find_paid(Gateway(payment.gateway), payment.gateway_ref, payment.amount_paise)
        if paid is not None:
            return out(db, _mark_paid(db, payment.id, paid))
        account.close(Gateway(payment.gateway), payment.gateway_ref)
    payment.status = PaymentStatus.CANCELLED.value
    db.commit()
    return out(db, payment)


def day_payments(db: Session, user: User, day: date | None, gateways: Gateways) -> PaymentsDayOut:
    """Everything paid to the shop on one day (India time; today if not given)."""
    require(user, Role.BUSINESS)
    _refresh_waiting(db, Payment.shop_user_id == user.id, gateways)
    day = day or datetime.now(INDIA).date()
    start = datetime.combine(day, time.min, INDIA)
    rows = db.scalars(
        select(Payment)
        .where(
            Payment.shop_user_id == user.id,
            Payment.status == PaymentStatus.PAID.value,
            Payment.paid_at >= start,
            Payment.paid_at < start + timedelta(days=1),
        )
        .order_by(Payment.paid_at.desc(), Payment.id.desc())
    ).all()
    names = _names(db, rows)
    return PaymentsDayOut(
        day=day,
        total_paise=sum(p.amount_paise for p in rows),
        count=len(rows),
        payments=[out(db, p, names) for p in rows],
    )


# ---------- paying udhaar (customer) ----------


def pay_udhaar(db: Session, user: User, book_id: int, body: UdhaarPayIn, gateways: Gateways) -> UdhaarPayOut:
    """Makes a Razorpay order for the customer to pay on Razorpay's own payment screen."""
    customer = udhaar.customer_book(db, user, book_id)
    shop = shop_name(db, customer.shop_user_id)
    row = db.get(ShopPaymentSettings, customer.shop_user_id)
    existing = by_client_ref(db, customer.shop_user_id, body.client_ref)
    if existing is not None:
        if existing.payer_user_id != user.id or existing.gateway != Gateway.ORDER.value:
            raise not_found()
        return UdhaarPayOut(payment=out(db, existing), key_id=existing.gateway_key_id or "",
                            order_id=existing.gateway_ref or "", shop_name=shop, contact=user.mobile)

    due = udhaar.balance(db, customer.id)
    if due <= 0:
        raise ApiError(409, "NOTHING_DUE", f"Nothing is due at {shop}")
    if body.amount_paise > due:
        raise ApiError(400, "MORE_THAN_DUE", f"You owe {_rupees(due)} at {shop}. Pay up to that amount")
    account = gateways.for_shop(row)
    if account is None:
        raise ApiError(409, "SHOP_NO_ONLINE",
                       f"{shop} does not take online payments in QBOX yet. Please pay at the shop")
    check_rate(db, Payment.payer_user_id == user.id, CUSTOMER_REQUESTS_PER_10_MIN)

    order = account.create_order(body.amount_paise, f"qbox-{body.client_ref}",
                                 {"qbox": "udhaar", "book": str(customer.id)})
    payment = Payment(
        shop_user_id=customer.shop_user_id,
        source=PaymentSource.UDHAAR.value,
        status=PaymentStatus.WAITING.value,
        amount_paise=body.amount_paise,
        udhaar_customer_id=customer.id,
        payer_user_id=user.id,
        gateway=Gateway.ORDER.value,
        gateway_ref=order.ref,
        gateway_key_id=account.key_id,
        client_ref=body.client_ref,
        expires_at=datetime.now(UTC) + timedelta(minutes=ORDER_MINUTES),
    )
    db.add(payment)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return UdhaarPayOut(payment=out(db, payment), key_id=account.key_id, order_id=order.ref,
                        shop_name=shop, contact=user.mobile)


def verify(db: Session, user: User, payment_id: int, body: VerifyIn, gateways: Gateways) -> PaymentOut:
    """What Razorpay's payment screen returned: checked with the signature, then
    with Razorpay itself, before the udhaar book changes."""
    payment = db.get(Payment, payment_id)
    if payment is None or payment.payer_user_id != user.id:
        raise not_found()
    if payment.status == PaymentStatus.PAID.value:
        return out(db, payment)
    account = _account_for(db, payment, gateways)
    if account is None:
        raise ApiError(409, "SHOP_NO_ONLINE", "This shop's online payments are switched off. Please contact the shop")
    if body.razorpay_order_id != payment.gateway_ref or not account.signature_ok(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    ):
        log.warning("Payment %s: the payment screen's signature did not match", payment.id)
        raise ApiError(400, "PAYMENT_NOT_VERIFIED",
                       "This payment could not be checked. If money was taken, it will show here in a few minutes")
    paid = account.payment(body.razorpay_payment_id)
    if paid is None or paid.order_id != payment.gateway_ref:
        return out(db, _refresh(db, payment, gateways, force=True))
    return out(db, _mark_paid(db, payment.id, paid))


# ---------- checking one payment (shop or the customer who paid) ----------


def get_payment(db: Session, user: User, payment_id: int, gateways: Gateways) -> PaymentOut:
    return out(db, _refresh(db, _visible(db, user, payment_id), gateways))


def refresh_payer_waiting(db: Session, user: User, gateways: Gateways) -> None:
    """The customer's own payments that are still waiting (for their history)."""
    _refresh_waiting(db, Payment.payer_user_id == user.id, gateways)


# ---------- helpers ----------


def _make_qr(account: Razorpay, amount: int, description: str, expires: datetime, notes: dict):
    with _no_qr_lock:
        since = _no_qr.get(account.key_id)
    if since is None or clock.monotonic() - since > _NO_QR_RETRY_SECONDS:
        try:
            return account.create_qr(amount, description, expires, notes)
        except FeatureOff:
            log.info("Razorpay QR Codes is not switched on for this account: using a payment link")
            with _no_qr_lock:
                _no_qr[account.key_id] = clock.monotonic()
    return account.create_link(amount, description, expires, notes)


def _refresh(db: Session, payment: Payment, gateways: Gateways, force: bool = False) -> Payment:
    """Asks Razorpay whether a waiting payment was paid; expires it when its time is up."""
    if payment.status != PaymentStatus.WAITING.value or not payment.gateway:
        return payment
    now = datetime.now(UTC)
    if not force and payment.checked_at and now - payment.checked_at < CHECK_EVERY:
        return payment
    account = _account_for(db, payment, gateways)
    if account is None:  # the shop disconnected that Razorpay account: it cannot be checked
        payment.checked_at = now  # so it does not keep others from being checked
        db.commit()
        return payment
    gateway = Gateway(payment.gateway)
    paid = account.find_paid(gateway, payment.gateway_ref, payment.amount_paise)
    if paid is not None:
        return _mark_paid(db, payment.id, paid)
    payment.checked_at = now
    if payment.expires_at and now >= payment.expires_at:
        account.close(gateway, payment.gateway_ref)
        payment.status = PaymentStatus.EXPIRED.value
    db.commit()
    return payment


def _refresh_waiting(db: Session, who, gateways: Gateways) -> None:
    """Checks a few waiting payments (e.g. a customer who paid udhaar while the
    shop's Collect screen was closed). Ones too old to
    still be paid (GIVE_UP_AFTER) are simply expired."""
    now = datetime.now(UTC)
    db.execute(
        update(Payment)
        .where(who, Payment.status == PaymentStatus.WAITING.value,
               Payment.expires_at < now - GIVE_UP_AFTER)
        .values(status=PaymentStatus.EXPIRED.value)
    )
    db.commit()
    waiting = db.scalars(
        select(Payment)
        .where(who, Payment.status == PaymentStatus.WAITING.value, Payment.gateway.is_not(None))
        .order_by(Payment.checked_at.asc().nulls_first())
        .limit(REFRESH_IN_LIST)
    ).all()
    for payment in waiting:
        try:
            _refresh(db, payment, gateways)
        except ApiError as error:
            log.info("Could not check payment %s now (%s)", payment.id, error.code)


def _mark_paid(db: Session, payment_id: int, paid: Paid) -> Payment:
    """Records the money as received, once. The row is locked so two checks at
    the same moment cannot both count it."""
    payment = db.execute(
        select(Payment).where(Payment.id == payment_id).with_for_update()
        .execution_options(populate_existing=True)
    ).scalar_one()
    if payment.status == PaymentStatus.PAID.value:
        db.commit()
        return payment
    if paid.amount_paise != payment.amount_paise:
        log.error("Payment %s: Razorpay amount does not match; not marked paid", payment.id)
        db.rollback()
        return payment
    payment.status = PaymentStatus.PAID.value
    payment.gateway_payment_id = paid.payment_id
    payment.payer_vpa = paid.vpa
    payment.method = paid.method
    payment.paid_at = paid.paid_at
    payment.checked_at = datetime.now(UTC)
    try:
        _add_udhaar_entry(db, payment)
        db.commit()
    except IntegrityError:  # this Razorpay payment was already counted for another request
        db.rollback()
        log.error("Payment %s: Razorpay payment already counted elsewhere", payment_id)
        payment = db.get(Payment, payment_id)
        db.refresh(payment)
    return payment


def _add_udhaar_entry(db: Session, payment: Payment) -> None:
    """One PAYMENT entry in the customer's udhaar book for this payment."""
    if payment.udhaar_customer_id is None or payment.udhaar_entry_id is not None:
        return
    ref = f"qbox-payment-{payment.id}"
    entry = db.scalars(
        select(UdhaarEntry).where(UdhaarEntry.customer_id == payment.udhaar_customer_id,
                                  UdhaarEntry.client_ref == ref)
    ).first()
    if entry is None:
        label = {
            PaymentSource.UDHAAR.value: "Paid online in QBOX",
            PaymentSource.COUNTER.value: "Paid by UPI QR",
            PaymentSource.MANUAL.value: "Paid by UPI",
        }[payment.source]
        entry = UdhaarEntry(
            customer_id=payment.udhaar_customer_id,
            kind=EntryKind.PAYMENT.value,
            amount_paise=payment.amount_paise,
            note=f"{label}: {payment.note}" if payment.note else label,
            entry_at=payment.paid_at or datetime.now(UTC),
            client_ref=ref,
        )
        db.add(entry)
        db.flush()
    payment.udhaar_entry_id = entry.id


def _visible(db: Session, user: User, payment_id: int) -> Payment:
    payment = db.get(Payment, payment_id)
    is_shop = payment is not None and payment.shop_user_id == user.id and _has(user, Role.BUSINESS)
    if payment is None or not (is_shop or payment.payer_user_id == user.id):
        raise not_found()
    return payment


def _account_for(db: Session, payment: Payment, gateways: Gateways) -> Razorpay | None:
    return gateways.for_key(db.get(ShopPaymentSettings, payment.shop_user_id), payment.gateway_key_id)


def settings_row(db: Session, user: User) -> ShopPaymentSettings:
    row = db.get(ShopPaymentSettings, user.id)
    if row is None:
        row = ShopPaymentSettings(shop_user_id=user.id)
        db.add(row)
    return row


def _settings_out(row: ShopPaymentSettings | None, gateways: Gateways) -> PaymentSettingsOut:
    own = gateways.own(row)
    account = own or gateways.test_account()
    return PaymentSettingsOut(
        upi_id=row.upi_id if row else None,
        upi_name=row.upi_name if row else None,
        razorpay_connected=bool(row and row.razorpay_key_id),
        razorpay_key_hint=hint(row.razorpay_key_id) if row and row.razorpay_key_id else None,
        automatic=account is not None,
        test_mode=bool(account and account.test_mode),
        using_test_account=account is not None and own is None,
    )


def by_client_ref(db: Session, shop_user_id: int, client_ref: str) -> Payment | None:
    return db.scalars(
        select(Payment).where(Payment.shop_user_id == shop_user_id, Payment.client_ref == client_ref)
    ).first()


def check_rate(db: Session, who, limit: int) -> None:
    """Stops one phone from making hundreds of Razorpay requests."""
    recent = db.scalar(
        select(func.count()).select_from(Payment).where(
            who, Payment.source != PaymentSource.MANUAL.value,
            Payment.created_at > datetime.now(UTC) - timedelta(minutes=10),
        )
    )
    if recent >= limit:
        raise ApiError(429, "PAYMENT_LIMIT", "Too many payment requests. Please wait a few minutes")


def _names(db: Session, payments) -> dict[int, str]:
    ids = {p.udhaar_customer_id for p in payments if p.udhaar_customer_id}
    if not ids:
        return {}
    return dict(db.execute(select(UdhaarCustomer.id, UdhaarCustomer.name).where(UdhaarCustomer.id.in_(ids))).all())


def out(db: Session, payment: Payment, names: dict[int, str] | None = None) -> PaymentOut:
    name = None
    if payment.udhaar_customer_id:
        if names is not None:
            name = names.get(payment.udhaar_customer_id)
        else:
            customer = db.get(UdhaarCustomer, payment.udhaar_customer_id)
            name = customer.name if customer else None
    elif payment.source == PaymentSource.DIRECT.value and payment.payer_user_id:
        payer = db.get(CustomerProfile, payment.payer_user_id)
        name = payer.full_name if payer else None
    return PaymentOut(
        id=payment.id,
        source=PaymentSource(payment.source),
        status=PaymentStatus(payment.status),
        amount_paise=payment.amount_paise,
        note=payment.note,
        udhaar_customer_id=payment.udhaar_customer_id,
        customer_name=name,
        payer_vpa=payment.payer_vpa,
        method=payment.method,
        qr_image_url=payment.qr_image_url,
        pay_url=payment.pay_url,
        test_mode=bool(payment.gateway_key_id and payment.gateway_key_id.startswith("rzp_test_")),
        expires_at=payment.expires_at,
        paid_at=payment.paid_at,
        claimed_at=payment.claimed_at,
        created_at=payment.created_at or datetime.now(UTC),
    )


def shop_name(db: Session, shop_user_id: int) -> str:
    shop = db.get(ShopProfile, shop_user_id)
    return shop.shop_name if shop else "QBOX shop"


def clean(note: str | None) -> str | None:
    note = " ".join((note or "").split())
    return note or None


def _rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


def _has(user: User, role: Role) -> bool:
    return role.value in {r.role for r in user.roles}


def require(user: User, role: Role) -> None:
    if not _has(user, role):
        raise ApiError(403, "ROLE_NOT_HELD", "Your account does not have this role")


def not_found() -> ApiError:
    return ApiError(404, "PAYMENT_NOT_FOUND", "This payment is not available")
