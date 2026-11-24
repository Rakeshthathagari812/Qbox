"""Pay to Shop: a customer pays a shop from their own QBOX app (no udhaar needed).

- Which shop: the shop's QBOX QR (a random code), one of their linked shops, a
  shop they paid before, or a shop's
  QBOX login number (checked by OTP and unique, unlike the contact number a
  shop types in). Number look-ups are limited, so nobody can collect shops.
- ONLINE: Razorpay's payment screen; checked exactly like an udhaar payment.
- UPI: straight to the shop's own UPI ID, offered only when the shop has not
  connected its own Razorpay. QBOX cannot see that money, so "I paid" is only
  the customer's word: it counts after the SHOP confirms it.
- It never changes the udhaar book: paying udhaar is a separate button.
"""

import base64
import secrets
from datetime import UTC, datetime, timedelta
from urllib.parse import quote

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models import (
    Gateway,
    Payment,
    PaymentSource,
    PaymentStatus,
    Role,
    ShopPaymentSettings,
    ShopProfile,
    User,
    UserRole,
)
from app.payments import service
from app.payments.gateways import Gateways
from app.payments.schemas import (
    PaymentOut,
    PayMethodChoice,
    PayShopOut,
    PayShopsOut,
    ShopPayIn,
    ShopPayOut,
    ShopQrOut,
    UnfinishedOut,
)
from app.ratelimit import limit_lookups
from app.udhaar import service as udhaar
from app.users import photos

RECENT_SHOPS = 10
ASK_FOR = timedelta(hours=24)  # "did you pay?" is asked again until then
CONFIRM_WITHIN = timedelta(days=23)  # + service.GIVE_UP_AFTER = 30 days


# ---------- customer ----------


def shops_to_pay(db: Session, user: User, gateways: Gateways) -> PayShopsOut:
    """Linked shops, then shops paid before; and UPI payments not answered yet."""
    service.require(user, Role.CUSTOMER)
    shops, seen = [], {user.id}
    for book in udhaar.my_books(db, user):
        owner = udhaar.customer_book(db, user, book.book_id).shop_user_id
        if owner not in seen:
            seen.add(owner)
            shops.append(_shop_out(db, owner, f"book:{book.book_id}", gateways, book.book_id, book.balance_paise))

    recent = db.scalars(
        select(Payment)
        .where(Payment.payer_user_id == user.id, Payment.source == PaymentSource.DIRECT.value,
               Payment.status == PaymentStatus.PAID.value)
        .order_by(Payment.paid_at.desc()).limit(100)
    ).all()
    most = len(shops) + RECENT_SHOPS
    for payment in recent:
        if payment.shop_user_id not in seen and len(shops) < most:
            seen.add(payment.shop_user_id)
            shops.append(_shop_out(db, payment.shop_user_id, f"paid:{payment.id}", gateways))

    waiting = db.scalars(
        select(Payment)
        .where(*_upi_waiting(user), Payment.claimed_at.is_(None), Payment.expires_at > datetime.now(UTC))
        .order_by(Payment.created_at.desc())
    ).all()
    return PayShopsOut(
        shops=shops,
        unfinished=[UnfinishedOut(payment=service.out(db, p), shop_name=service.shop_name(db, p.shop_user_id))
                    for p in waiting],
    )


def find_shop(db: Session, user: User, mobile: str, gateways: Gateways) -> PayShopOut:
    """The shop's name for this number, so the customer can check it before paying."""
    service.require(user, Role.CUSTOMER)
    return _found(db, user, _by_mobile(db, user, mobile), f"mobile:{mobile}", gateways)


def scan_shop(db: Session, user: User, code: str, gateways: Gateways) -> PayShopOut:
    """The shop whose QBOX QR was scanned. What is paid, and where, always comes
    from here, never from the sticker."""
    service.require(user, Role.CUSTOMER)
    return _found(db, user, _by_code(db, user, code), f"code:{code}", gateways)


def pay_shop(db: Session, user: User, body: ShopPayIn, gateways: Gateways) -> ShopPayOut:
    service.require(user, Role.CUSTOMER)
    owner = _resolve(db, user, body.ref)
    row = db.get(ShopPaymentSettings, owner)
    existing = service.by_client_ref(db, owner, body.client_ref)
    if existing is not None:
        return _again(db, user, existing, body, row)

    name = service.shop_name(db, owner)
    online = body.method == PayMethodChoice.ONLINE
    account = gateways.for_shop(row) if online else None
    if online and account is None:
        raise ApiError(409, "SHOP_NO_ONLINE", f"{name} does not take online payments in QBOX yet")
    if not online and not _takes_upi(row, gateways):
        raise ApiError(409, "SHOP_NO_UPI", f"{name} does not take UPI payments this way")
    service.check_rate(db, Payment.payer_user_id == user.id, service.CUSTOMER_REQUESTS_PER_10_MIN)

    now = datetime.now(UTC)
    payment = Payment(
        shop_user_id=owner,
        source=PaymentSource.DIRECT.value,
        status=PaymentStatus.WAITING.value,
        amount_paise=body.amount_paise,
        note=service.clean(body.note),
        payer_user_id=user.id,
        method=None if online else "upi",
        client_ref=body.client_ref,
        expires_at=now + (timedelta(minutes=service.ORDER_MINUTES) if online else ASK_FOR),
    )
    if online:
        order = account.create_order(body.amount_paise, f"qbox-{body.client_ref}", {"qbox": "direct"})
        payment.gateway, payment.gateway_ref = Gateway.ORDER.value, order.ref
        payment.gateway_key_id = account.key_id
    db.add(payment)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return _start(db, user, payment, row)


def claim(db: Session, user: User, payment_id: int) -> PaymentOut:
    """ "I paid" : the shop is asked to check its bank and confirm."""
    payment = _mine(db, user, payment_id)
    if payment.status == PaymentStatus.WAITING.value and payment.claimed_at is None:
        payment.claimed_at = datetime.now(UTC)
        payment.expires_at = payment.claimed_at + CONFIRM_WITHIN
    db.commit()
    return service.out(db, payment)


def drop(db: Session, user: User, payment_id: int) -> PaymentOut:
    """ "I did not pay" (only before "I paid")."""
    payment = _mine(db, user, payment_id)
    if payment.status == PaymentStatus.WAITING.value and payment.claimed_at is None:
        payment.status = PaymentStatus.CANCELLED.value
    db.commit()
    return service.out(db, payment)


# ---------- shop ----------


def shop_qr(db: Session, user: User) -> ShopQrOut:
    """The shop's own QR (made once, then always the same)."""
    service.require(user, Role.BUSINESS)
    row = db.get(ShopPaymentSettings, user.id)
    if row is None or row.pay_code is None:
        row = _new_code(db, user)
    name = service.shop_name(db, user.id)
    if row.upi_id:
        # A normal UPI QR with one extra part that only QBOX reads.
        data = f"upi://pay?pa={quote(row.upi_id)}&pn={quote(row.upi_name or name)}&cu=INR&qbox={row.pay_code}"
    else:
        data = f"qbox://pay?qbox={row.pay_code}"
    return ShopQrOut(shop_name=name, data=data, works_in_upi_apps=bool(row.upi_id))


def _new_code(db: Session, user: User) -> ShopPaymentSettings:
    row = service.settings_row(db, user)
    row.pay_code = base64.b32encode(secrets.token_bytes(10)).decode().lower()
    try:
        db.commit()
    except IntegrityError:  # asked twice at the same moment: the other one's code stands
        db.rollback()
        row = db.get(ShopPaymentSettings, user.id, populate_existing=True)
        if row is None or row.pay_code is None:
            raise ApiError(409, "TRY_AGAIN", "Please try again") from None
    return row

def to_confirm(db: Session, user: User) -> list[PaymentOut]:
    """UPI payments customers say they made; the shop checks its bank."""
    rows = db.scalars(
        select(Payment)
        .where(Payment.shop_user_id == user.id, Payment.source == PaymentSource.DIRECT.value,
               Payment.gateway.is_(None), Payment.status == PaymentStatus.WAITING.value,
               Payment.claimed_at.is_not(None))
        .order_by(Payment.claimed_at.desc())
    ).all()
    return [service.out(db, p) for p in rows]


def answer(db: Session, user: User, payment_id: int, received: bool) -> PaymentOut:
    """The shop's answer: money received, or not. The first answer stands."""
    service.require(user, Role.BUSINESS)
    payment = _locked(db, payment_id)
    if (payment is None or payment.shop_user_id != user.id or payment.source != PaymentSource.DIRECT.value
            or payment.gateway is not None or payment.claimed_at is None):
        db.rollback()
        raise service.not_found()
    if payment.status == PaymentStatus.WAITING.value:
        if received:
            payment.status = PaymentStatus.PAID.value
            payment.paid_at = payment.claimed_at  # the day the money came
        else:
            payment.status = PaymentStatus.CANCELLED.value
        payment.answered_at = datetime.now(UTC)
    db.commit()
    return service.out(db, payment)


# ---------- helpers ----------


def _resolve(db: Session, user: User, ref: str) -> int:
    """The shop's user id for "book:12", "paid:55" (both the customer's own), "mobile:98..." or "code:..."."""
    kind, value = ref.split(":")
    if kind == "mobile":
        return _by_mobile(db, user, value)
    if kind == "code":
        return _by_code(db, user, value)
    if kind == "book":
        owner = udhaar.customer_book(db, user, int(value)).shop_user_id
    else:
        payment = db.get(Payment, int(value))
        if payment is None or payment.payer_user_id != user.id or payment.status != PaymentStatus.PAID.value:
            raise service.not_found()
        owner = payment.shop_user_id
    if owner == user.id:
        raise _own_shop()
    return owner


def _by_mobile(db: Session, user: User, mobile: str) -> int:
    if mobile == user.mobile:
        raise _own_shop()
    limit_lookups(user.id)
    owner = db.scalar(
        select(User.id)
        .join(ShopProfile, ShopProfile.user_id == User.id)
        .join(UserRole, UserRole.user_id == User.id)
        .where(User.mobile == mobile, UserRole.role == Role.BUSINESS.value)
    )
    if owner is None:
        raise ApiError(404, "SHOP_NOT_FOUND",
                       "No QBOX shop uses this number. Ask the shop for its QBOX login number")
    return owner


def _by_code(db: Session, user: User, code: str) -> int:
    owner = db.scalar(select(ShopPaymentSettings.shop_user_id).where(ShopPaymentSettings.pay_code == code))
    if owner is None:
        raise ApiError(404, "SHOP_NOT_FOUND", "This QBOX QR is not in use. Ask the shop for its new one")
    if owner == user.id:
        raise _own_shop()
    return owner


def _found(db: Session, user: User, owner: int, ref: str, gateways: Gateways) -> PayShopOut:
    """With their udhaar there, if they are in this shop's book."""
    book = next((b for b in udhaar.my_books(db, user)
                 if udhaar.customer_book(db, user, b.book_id).shop_user_id == owner), None)
    if book is not None:
        return _shop_out(db, owner, f"book:{book.book_id}", gateways, book.book_id, book.balance_paise)
    return _shop_out(db, owner, ref, gateways)


def _takes_upi(row: ShopPaymentSettings | None, gateways: Gateways) -> bool:
    return bool(row and row.upi_id) and gateways.own(row) is None


def _shop_out(db: Session, owner: int, ref: str, gateways: Gateways,
              book_id: int | None = None, balance: int = 0) -> PayShopOut:
    shop = db.get(ShopProfile, owner)
    row = db.get(ShopPaymentSettings, owner)
    account = gateways.for_shop(row)
    return PayShopOut(
        ref=ref,
        shop_name=service.shop_name(db, owner),
        shop_category=(shop.shop_category_detail or shop.shop_category) if shop else None,
        shop_photo=photos.ref_of(db, owner, Role.BUSINESS),
        book_id=book_id,
        due_paise=max(balance, 0),
        online=account is not None,
        test_mode=bool(account and account.test_mode),
        upi=_takes_upi(row, gateways),
    )


def _again(db: Session, user: User, payment: Payment, body: ShopPayIn, row: ShopPaymentSettings | None) -> ShopPayOut:
    """The same request sent twice gives the same payment, never a second one."""
    online = payment.gateway == Gateway.ORDER.value
    if payment.payer_user_id != user.id or payment.source != PaymentSource.DIRECT.value:
        raise service.not_found()
    if payment.amount_paise != body.amount_paise or online != (body.method == PayMethodChoice.ONLINE):
        raise ApiError(409, "TRY_AGAIN", "Please try again")
    return _start(db, user, payment, row)


def _start(db: Session, user: User, payment: Payment, row: ShopPaymentSettings | None) -> ShopPayOut:
    upi = payment.gateway is None
    return ShopPayOut(
        payment=service.out(db, payment),
        shop_name=service.shop_name(db, payment.shop_user_id),
        contact=user.mobile,
        key_id=payment.gateway_key_id,
        order_id=payment.gateway_ref,
        upi_id=row.upi_id if upi and row else None,
        upi_name=row.upi_name if upi and row else None,
    )


def _upi_waiting(user: User):
    return (Payment.payer_user_id == user.id, Payment.source == PaymentSource.DIRECT.value,
            Payment.gateway.is_(None), Payment.status == PaymentStatus.WAITING.value)


def _mine(db: Session, user: User, payment_id: int) -> Payment:
    payment = _locked(db, payment_id)
    if (payment is None or payment.payer_user_id != user.id or payment.source != PaymentSource.DIRECT.value
            or payment.gateway is not None):
        db.rollback()
        raise service.not_found()
    return payment


def _locked(db: Session, payment_id: int) -> Payment | None:
    """The row, locked, so two answers at the same moment cannot both count."""
    return db.execute(
        select(Payment).where(Payment.id == payment_id).with_for_update().execution_options(populate_existing=True)
    ).scalar_one_or_none()


def _own_shop() -> ApiError:
    return ApiError(400, "OWN_SHOP", "This is your own shop")
