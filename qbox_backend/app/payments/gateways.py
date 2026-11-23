"""Which Razorpay account collects for a shop, and keeping its secret key safe.

- A shop that connected its own Razorpay account: that account (money goes
  straight to the shop's bank).
- Otherwise, on this PC only: QBOX's test account from .env (never in production).
- The secret key is stored encrypted with QBOX_PAYMENT_SECRET_KEY.
"""

import base64
import hashlib
import logging

from cryptography.fernet import Fernet, InvalidToken

from app.config import get_settings
from app.models import ShopPaymentSettings
from app.payments.razorpay import Razorpay

log = logging.getLogger("qbox.payments")


def _fernet() -> Fernet:
    digest = hashlib.sha256(get_settings().payment_secret_key.encode()).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def lock(secret: str) -> str:
    """Encrypts a Razorpay secret key for the database."""
    return _fernet().encrypt(secret.encode()).decode()


def unlock(stored: str) -> str | None:
    """The secret key again, or None if it cannot be read (QBOX_PAYMENT_SECRET_KEY changed)."""
    try:
        return _fernet().decrypt(stored.encode()).decode()
    except (InvalidToken, ValueError):
        log.error("A saved Razorpay key could not be read: was QBOX_PAYMENT_SECRET_KEY changed?")
        return None


def hint(key_id: str) -> str:
    """rzp_test_AbCdEfGh1234 -> rzp_test_••••1234 (enough to recognise it)."""
    prefix = "rzp_test_" if key_id.startswith("rzp_test_") else ("rzp_live_" if key_id.startswith("rzp_live_") else "")
    return f"{prefix}••••{key_id[-4:]}"


class Gateways:
    def make(self, key_id: str, key_secret: str) -> Razorpay:
        return Razorpay(key_id, key_secret)

    def own(self, row: ShopPaymentSettings | None) -> Razorpay | None:
        """The shop's own Razorpay account, if connected."""
        if row is None or not row.razorpay_key_id or not row.razorpay_secret:
            return None
        secret = unlock(row.razorpay_secret)
        return self.make(row.razorpay_key_id, secret) if secret else None

    def test_account(self) -> Razorpay | None:
        settings = get_settings()
        if not settings.razorpay_test_account_on:
            return None
        return self.make(settings.razorpay_key_id, settings.razorpay_key_secret)

    def for_shop(self, row: ShopPaymentSettings | None) -> Razorpay | None:
        """The account new payments go to."""
        return self.own(row) or self.test_account()

    def for_key(self, row: ShopPaymentSettings | None, key_id: str | None) -> Razorpay | None:
        """The account an earlier payment was made on (needed to check it)."""
        for account in (self.own(row), self.test_account()):
            if account is not None and account.key_id == key_id:
                return account
        return None


_gateways = Gateways()


def get_gateways() -> Gateways:
    return _gateways
