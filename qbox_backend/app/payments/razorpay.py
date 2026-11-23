"""Talks to Razorpay (api.razorpay.com) with one shop's keys.

Only this file knows Razorpay's addresses and answers. Logs hold only what was
asked and the status code: never keys, and never who paid.
"""

import hashlib
import hmac
import logging
from dataclasses import dataclass
from datetime import UTC, datetime

import httpx

from app.errors import ApiError
from app.models import Gateway

log = logging.getLogger("qbox.payments")

API = "https://api.razorpay.com/v1"
_TIMEOUT = httpx.Timeout(15.0, connect=5.0)


@dataclass
class Collect:
    """A QR, payment link or order Razorpay made for us."""

    gateway: Gateway
    ref: str  # qr_..., plink_..., order_...
    qr_image_url: str | None = None
    pay_url: str | None = None


@dataclass
class Paid:
    """A payment Razorpay has captured (the money is the shop's)."""

    payment_id: str
    amount_paise: int
    paid_at: datetime
    method: str | None = None
    vpa: str | None = None
    order_id: str | None = None


class FeatureOff(Exception):
    """This Razorpay account does not have the feature switched on (QR Codes)."""


def _failed() -> ApiError:
    return ApiError(502, "PAYMENTS_FAILED", "Could not reach Razorpay. Please try again")


def _keys_wrong() -> ApiError:
    return ApiError(409, "RAZORPAY_KEYS_WRONG",
                    "Razorpay did not accept this shop's keys. Connect Razorpay again in Payment settings")


class Razorpay:
    def __init__(self, key_id: str, key_secret: str, http: httpx.Client | None = None):
        self.key_id = key_id
        self._secret = key_secret
        self._http = http or _shared_http()

    @property
    def test_mode(self) -> bool:
        return self.key_id.startswith("rzp_test_")

    # ---------- making payments ----------

    def check_keys(self) -> None:
        """Raises if Razorpay does not accept these keys."""
        try:
            self._call("GET", "/orders", params={"count": 1})
        except ApiError as error:
            if error.code == "RAZORPAY_KEYS_WRONG":
                raise ApiError(400, "RAZORPAY_KEYS_WRONG",
                               "Razorpay did not accept these keys. Copy both again from the Razorpay "
                               "dashboard (Account & Settings > API Keys)") from None
            raise

    def create_qr(self, amount_paise: int, description: str, close_by: datetime, notes: dict) -> Collect:
        """A one-time UPI QR for exactly this amount. FeatureOff if QR Codes is not
        switched on for this account."""
        data = self._call("POST", "/payments/qr_codes", body={
            "type": "upi_qr",
            "name": description[:40],
            "usage": "single_use",
            "fixed_amount": True,
            "payment_amount": amount_paise,
            "description": description,
            "close_by": int(close_by.timestamp()),
            "notes": notes,
        }, feature=True)
        if not isinstance(data.get("id"), str) or not isinstance(data.get("image_url"), str):
            raise _failed()
        return Collect(Gateway.QR_CODE, data["id"], qr_image_url=data["image_url"])

    def create_link(self, amount_paise: int, description: str, expire_by: datetime, notes: dict) -> Collect:
        """A payment page for exactly this amount; the app shows its link as a QR."""
        data = self._call("POST", "/payment_links", body={
            "amount": amount_paise,
            "currency": "INR",
            "accept_partial": False,
            "description": description,
            "expire_by": int(expire_by.timestamp()),
            "notify": {"sms": False, "email": False},
            "reminder_enable": False,
            "notes": notes,
        })
        if not isinstance(data.get("id"), str) or not isinstance(data.get("short_url"), str):
            raise _failed()
        return Collect(Gateway.PAYMENT_LINK, data["id"], pay_url=data["short_url"])

    def create_order(self, amount_paise: int, receipt: str, notes: dict) -> Collect:
        """An order the customer pays on Razorpay's own payment screen."""
        data = self._call("POST", "/orders", body={
            "amount": amount_paise, "currency": "INR", "receipt": receipt[:40], "notes": notes,
        })
        if not isinstance(data.get("id"), str):
            raise _failed()
        return Collect(Gateway.ORDER, data["id"])

    # ---------- checking ----------

    def find_paid(self, gateway: Gateway, ref: str, amount_paise: int) -> Paid | None:
        """The captured payment for this QR / link / order, if it has been paid."""
        if gateway == Gateway.PAYMENT_LINK:
            link = self._call("GET", f"/payment_links/{ref}")
            for item in link.get("payments") or []:
                if isinstance(item, dict) and item.get("status") in ("captured", "authorized"):
                    paid = self.payment(str(item.get("payment_id", "")))
                    if paid and paid.amount_paise == amount_paise:
                        return paid
            return None
        path = f"/payments/qr_codes/{ref}/payments" if gateway == Gateway.QR_CODE else f"/orders/{ref}/payments"
        for item in self._call("GET", path).get("items") or []:
            paid = self._settle(item)
            if paid and paid.amount_paise == amount_paise:
                return paid
        return None

    def payment(self, payment_id: str) -> Paid | None:
        """One payment, if captured. An authorized (not yet captured) payment is captured now."""
        if not payment_id.startswith("pay_") or not payment_id[4:].isalnum():
            return None
        return self._settle(self._call("GET", f"/payments/{payment_id}"))

    def close(self, gateway: Gateway, ref: str) -> None:
        """Stops a QR / link from taking money (best effort: an order needs nothing)."""
        path = {Gateway.QR_CODE: f"/payments/qr_codes/{ref}/close",
                Gateway.PAYMENT_LINK: f"/payment_links/{ref}/cancel"}.get(gateway)
        if path is None:
            return
        try:
            self._call("POST", path, body={})
        except ApiError:
            log.info("Razorpay: could not close %s (it may already be closed)", gateway.value)

    def signature_ok(self, order_id: str, payment_id: str, signature: str) -> bool:
        """The check Razorpay's payment screen gives us: proves the payment really
        belongs to this order (made with the secret key, which phones never have)."""
        expected = hmac.new(self._secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature or "")

    # ---------- helpers ----------

    def _settle(self, item: object) -> Paid | None:
        if not isinstance(item, dict) or item.get("currency", "INR") != "INR":
            return None
        status = item.get("status")
        if status == "authorized" and isinstance(item.get("id"), str):  # the account does not capture by itself
            item = self._call("POST", f"/payments/{item.get('id')}/capture",
                              body={"amount": item.get("amount"), "currency": "INR"})
            status = item.get("status")
        if status != "captured" or not isinstance(item.get("id"), str) or not isinstance(item.get("amount"), int):
            return None
        created = item.get("created_at")
        return Paid(
            payment_id=item["id"],
            amount_paise=item["amount"],
            paid_at=datetime.fromtimestamp(created, UTC) if isinstance(created, int) else datetime.now(UTC),
            method=str(item["method"])[:20] if item.get("method") else None,
            vpa=str(item["vpa"])[:100] if item.get("vpa") else None,
            order_id=item.get("order_id") if isinstance(item.get("order_id"), str) else None,
        )

    def _call(self, method: str, path: str, body: dict | None = None, params: dict | None = None,
              feature: bool = False) -> dict:
        name = path.split("/")[1]  # e.g. "orders": what was asked, never the ids
        try:
            response = self._http.request(method, f"{API}{path}", json=body, params=params,
                                          auth=(self.key_id, self._secret))
        except httpx.HTTPError:
            log.warning("Razorpay %s %s: no answer", method, name)
            raise _failed() from None
        try:
            data = response.json()
        except ValueError:
            data = {}
        if not isinstance(data, dict):
            data = {}
        if response.status_code < 400:
            return data
        log.warning("Razorpay %s %s returned %s", method, name, response.status_code)
        if response.status_code == 401:
            raise _keys_wrong()
        error = data.get("error") if isinstance(data.get("error"), dict) else {}
        description = str(error.get("description") or "")
        if feature and response.status_code in (400, 404) and (
            "not found on the server" in description or "not enabled" in description.lower()
        ):
            raise FeatureOff()
        if response.status_code == 400:
            raise ApiError(400, "PAYMENTS_REFUSED",
                           f"Razorpay refused this: {description[:150]}" if description
                           else "Razorpay refused this payment request")
        raise _failed()


_http: httpx.Client | None = None


def _shared_http() -> httpx.Client:
    """One connection pool for all shops (keys are sent with each request)."""
    global _http
    if _http is None:
        _http = httpx.Client(timeout=_TIMEOUT)
    return _http
