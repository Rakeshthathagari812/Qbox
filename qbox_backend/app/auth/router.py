"""Public endpoints (no login needed)."""

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.auth import service
from app.auth.schemas import (
    AuthOut,
    LoginIn,
    RegisterIn,
    ResetPinIn,
    SendOtpIn,
    SendOtpOut,
    VerifyOtpIn,
    VerifyOtpOut,
)
from app.database import get_db
from app.ratelimit import limit_auth_requests

# Every auth request counts toward the per-device limit (see app/ratelimit.py).
router = APIRouter(prefix="/api/auth", tags=["Login & sign up"], dependencies=[Depends(limit_auth_requests)])


@router.post("/otp/send", response_model=SendOtpOut, summary="Send an OTP for SIGNUP or RESET_PIN")
def send_otp(body: SendOtpIn, db: Session = Depends(get_db)):
    return service.send_otp(db, body.mobile, body.purpose)


@router.post("/otp/verify", response_model=VerifyOtpOut, summary="Check the OTP and get a verification token")
def verify_otp(body: VerifyOtpIn, db: Session = Depends(get_db)):
    return service.verify_otp(db, body.mobile, body.purpose, body.otp)


@router.post("/register", response_model=AuthOut, status_code=status.HTTP_201_CREATED,
             summary="Create the account (needs a SIGNUP verification token)")
def register(body: RegisterIn, db: Session = Depends(get_db)):
    return service.register(db, body)


@router.post("/login", response_model=AuthOut, summary="Log in with mobile and PIN")
def login(body: LoginIn, db: Session = Depends(get_db)):
    return service.login(db, body.mobile, body.pin)


@router.post("/pin/reset", status_code=status.HTTP_204_NO_CONTENT,
             summary="Set a new PIN (needs a RESET_PIN verification token)")
def reset_pin(body: ResetPinIn, db: Session = Depends(get_db)):
    service.reset_pin(db, body.verification_token, body.new_pin)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
