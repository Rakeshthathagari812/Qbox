"""Payment API paths. All need login. The rules are in service.py.

Shop side (BUSINESS role):  /api/payments/settings..., /collect, /manual, /, /{id}/cancel
Customer side (CUSTOMER role): /api/payments/udhaar/{book_id}, /{id}/verify
Both: /api/payments/{id} (the shop it was paid to, or the customer who paid)
"""

from datetime import date

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import current_user
from app.models import User
from app.payments import service
from app.payments.gateways import Gateways, get_gateways
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
    return service.day_payments(db, user, day, gateways)


@router.post("/udhaar/{book_id}", response_model=UdhaarPayOut, status_code=status.HTTP_201_CREATED,
             summary="Customer: pay udhaar to a shop (opens Razorpay's payment screen in the app)")
def pay_udhaar(book_id: int, body: UdhaarPayIn, user: User = Depends(current_user),
               db: Session = Depends(get_db), gateways: Gateways = Depends(get_gateways)):
    return service.pay_udhaar(db, user, book_id, body, gateways)


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
