"""Payment API paths. All need login. The rules are in service.py.

Shop side (BUSINESS role):  /api/payments/settings..., /collect, /manual, /, /{id}/cancel
Customer side (CUSTOMER role): /api/payments/udhaar/{book_id}, /shops..., /shop, /{id}/verify, /claim, /drop
Both: /api/payments/{id} (the shop it was paid to, or the customer who paid)
"""

from datetime import date

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import User
from app.payments import direct, service
from app.payments.gateways import Gateways, get_gateways
from app.payments.schemas import (
    CollectIn,
    FindShopIn,
    PaymentOut,
    PaymentSettingsOut,
    PaymentsDayOut,
    PayShopOut,
    PayShopsOut,
    RazorpayKeysIn,
    ScanShopIn,
    ShopPayIn,
    ShopPayOut,
    ShopQrOut,
    UdhaarPayIn,
    UdhaarPayOut,
    UpiIn,
    VerifyIn,
)

router = APIRouter(prefix="/api/payments", tags=["Payments"])


@router.get("/settings", response_model=PaymentSettingsOut, summary="How my shop takes payments")
def get_settings(user: User = Depends(current_user), db: Session = Depends(get_db),
                 gateways: Gateways = Depends(get_gateways)):
    return service.get_settings_out(db, user, gateways)


@router.put("/settings/upi", response_model=PaymentSettingsOut, summary="Save my own UPI ID (empty = remove)")
def set_upi(body: UpiIn, user: User = Depends(current_user), db: Session = Depends(get_db),
            gateways: Gateways = Depends(get_gateways)):
    return service.set_upi(db, user, body, gateways)


@router.post("/settings/razorpay", response_model=PaymentSettingsOut,
             summary="Connect my own Razorpay account (keys checked with Razorpay, secret stored encrypted)")
def connect_razorpay(body: RazorpayKeysIn, user: User = Depends(current_user), db: Session = Depends(get_db),
                     gateways: Gateways = Depends(get_gateways)):
    return service.connect_razorpay(db, user, body, gateways)


@router.delete("/settings/razorpay", response_model=PaymentSettingsOut, summary="Disconnect my Razorpay account")
def disconnect_razorpay(user: User = Depends(current_user), db: Session = Depends(get_db),
                        gateways: Gateways = Depends(get_gateways)):
    return service.disconnect_razorpay(db, user, gateways)


@router.get("/settings/qr", response_model=ShopQrOut, summary="My shop's QR for customers to scan and pay")
def shop_qr(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return direct.shop_qr(db, user)


@router.post("/collect", response_model=PaymentOut, status_code=status.HTTP_201_CREATED,
             summary="A one-time QR for this amount (Razorpay confirms the payment by itself)")
def collect(body: CollectIn, user: User = Depends(current_user), db: Session = Depends(get_db),
            gateways: Gateways = Depends(get_gateways)):
    return service.collect(db, user, body, gateways)


@router.post("/manual", response_model=PaymentOut, status_code=status.HTTP_201_CREATED,
             summary="Record money paid to my own UPI ID (confirmed by me)")
def record_manual(body: CollectIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return service.record_manual(db, user, body)


@router.get("", response_model=PaymentsDayOut, summary="Payments received on a day (today if not given)")
def day_payments(day: date | None = None, user: User = Depends(current_user), db: Session = Depends(get_db),
                 gateways: Gateways = Depends(get_gateways)):
    result = service.day_payments(db, user, day, gateways)
    result.to_confirm = direct.to_confirm(db, user)
    return result


@router.post("/udhaar/{book_id}", response_model=UdhaarPayOut, status_code=status.HTTP_201_CREATED,
             summary="Customer: pay udhaar to a shop (opens Razorpay's payment screen in the app)")
def pay_udhaar(book_id: int, body: UdhaarPayIn, user: User = Depends(current_user),
               db: Session = Depends(get_db), gateways: Gateways = Depends(get_gateways)):
    return service.pay_udhaar(db, user, book_id, body, gateways)


@router.get("/shops", response_model=PayShopsOut, summary="Customer: shops I can pay (linked, and paid before)")
def shops_to_pay(user: User = Depends(current_user), db: Session = Depends(get_db),
                 gateways: Gateways = Depends(get_gateways)):
    return direct.shops_to_pay(db, user, gateways)


@router.post("/shops/find", response_model=PayShopOut,
             summary="Customer: the shop with this QBOX login number (limited per hour)")
def find_shop(body: FindShopIn, user: User = Depends(current_user), db: Session = Depends(get_db),
              gateways: Gateways = Depends(get_gateways)):
    return direct.find_shop(db, user, body.mobile, gateways)


@router.post("/shops/scan", response_model=PayShopOut, summary="Customer: the shop whose QBOX QR I scanned")
def scan_shop(body: ScanShopIn, user: User = Depends(current_user), db: Session = Depends(get_db),
              gateways: Gateways = Depends(get_gateways)):
    return direct.scan_shop(db, user, body.code, gateways)


@router.post("/shop", response_model=ShopPayOut, status_code=status.HTTP_201_CREATED,
             summary="Customer: pay a shop (Razorpay's screen, or the shop's own UPI ID)")
def pay_shop(body: ShopPayIn, user: User = Depends(current_user), db: Session = Depends(get_db),
             gateways: Gateways = Depends(get_gateways)):
    return direct.pay_shop(db, user, body, gateways)


@router.post("/{payment_id}/claim", response_model=PaymentOut, summary="Customer: I paid by UPI (the shop confirms)")
def claim(payment_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return direct.claim(db, user, payment_id)


@router.post("/{payment_id}/drop", response_model=PaymentOut, summary="Customer: I did not pay by UPI")
def drop(payment_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return direct.drop(db, user, payment_id)


@router.post("/{payment_id}/confirm", response_model=PaymentOut, summary="Shop: the customer's UPI money came")
def confirm(payment_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return direct.answer(db, user, payment_id, received=True)


@router.post("/{payment_id}/not-received", response_model=PaymentOut, summary="Shop: the UPI money did not come")
def not_received(payment_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return direct.answer(db, user, payment_id, received=False)


@router.get("/{payment_id}", response_model=PaymentOut, summary="One payment (checks Razorpay while waiting)")
def get_payment(payment_id: int, user: User = Depends(current_user), db: Session = Depends(get_db),
                gateways: Gateways = Depends(get_gateways)):
    return service.get_payment(db, user, payment_id, gateways)


@router.post("/{payment_id}/cancel", response_model=PaymentOut, summary="Stop a QR (recorded as paid if it was)")
def cancel(payment_id: int, user: User = Depends(current_user), db: Session = Depends(get_db),
           gateways: Gateways = Depends(get_gateways)):
    return service.cancel(db, user, payment_id, gateways)


@router.post("/{payment_id}/verify", response_model=PaymentOut,
             summary="Customer: what Razorpay's payment screen returned (signature checked)")
def verify(payment_id: int, body: VerifyIn, user: User = Depends(current_user), db: Session = Depends(get_db),
           gateways: Gateways = Depends(get_gateways)):
    return service.verify(db, user, payment_id, body, gateways)
