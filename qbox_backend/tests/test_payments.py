"""Payments: settings, counter QR, udhaar payments, checks and privacy.
Razorpay is pretend here (FakeRazorpay), so no real account is ever touched.
The last tests check the real Razorpay client against recorded answers."""

import hashlib
import hmac
import json
import uuid
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from sqlalchemy import text

from app.config import get_settings
from app.database import engine
from app.main import app
from app.models import Gateway
from app.payments.gateways import Gateways, get_gateways, lock, unlock
from app.payments.razorpay import Collect, FeatureOff, Paid, Razorpay
from tests.test_calendar import _account
from tests.test_udhaar import RAMESH, SHOP_A, SHOP_B, _add_customer, _entry, _post_entry

TEST_KEY = "rzp_test_QBOXTEST1234"
TEST_SECRET = "testsecret0123456789abcd"
SHOP_KEY = "rzp_test_SHOPOWN98765"
SHOP_SECRET = "shopsecret9876543210wxyz"


class World:
    """Pretend Razorpay: what was made, what was paid, what was closed."""

    def __init__(self):
        self.qr_on = True
        self.keys_ok = True
        self.made: list[tuple[str, Collect, int]] = []  # (key id, what, amount)
        self.paid: dict[str, Paid] = {}  # ref -> payment
        self.payments: dict[str, Paid] = {}  # pay_... -> payment
        self.closed: list[str] = []
        self._n = 0

    def pay(self, ref, amount=None, vpa="ramesh@okaxis"):
        made = next(m for m in self.made if m[1].ref == ref)
        self._n += 1
        paid = Paid(payment_id=f"pay_TEST{self._n:06d}", amount_paise=amount or made[2],
                    paid_at=datetime.now(UTC), method="upi", vpa=vpa,
                    order_id=ref if made[1].gateway == Gateway.ORDER else None)
        self.paid[ref] = paid
        self.payments[paid.payment_id] = paid
        return paid


class FakeRazorpay(Razorpay):
    def __init__(self, key_id, key_secret, world):
        super().__init__(key_id, key_secret, http=httpx.Client())
        self.world = world

    def _make(self, gateway, prefix, amount, **urls):
        self.world._n += 1
        made = Collect(gateway, f"{prefix}_TEST{self.world._n:06d}", **urls)
        self.world.made.append((self.key_id, made, amount))
        return made

    def check_keys(self):
        if not self.world.keys_ok:
            from app.errors import ApiError
            raise ApiError(400, "RAZORPAY_KEYS_WRONG", "Razorpay did not accept these keys")

    def create_qr(self, amount_paise, description, close_by, notes):
        if not self.world.qr_on:
            raise FeatureOff()
        return self._make(Gateway.QR_CODE, "qr", amount_paise, qr_image_url="https://rzp.io/qr.png")

    def create_link(self, amount_paise, description, expire_by, notes):
        return self._make(Gateway.PAYMENT_LINK, "plink", amount_paise, pay_url="https://rzp.io/i/test")

    def create_order(self, amount_paise, receipt, notes):
        return self._make(Gateway.ORDER, "order", amount_paise)

    def find_paid(self, gateway, ref, amount_paise):
        paid = self.world.paid.get(ref)
        return paid if paid and paid.amount_paise == amount_paise else None

    def payment(self, payment_id):
        return self.world.payments.get(payment_id)

    def close(self, gateway, ref):
        self.world.closed.append(ref)


class FakeGateways(Gateways):
    def __init__(self, world):
        self.world = world

    def make(self, key_id, key_secret):
        return FakeRazorpay(key_id, key_secret, self.world)


@pytest.fixture
def world():
    w = World()
    app.dependency_overrides[get_gateways] = lambda: FakeGateways(w)
    yield w
    app.dependency_overrides.pop(get_gateways, None)


@pytest.fixture
def test_account(monkeypatch):
    """QBOX's test account from .env, as on the development PC."""
    monkeypatch.setattr(get_settings(), "razorpay_key_id", TEST_KEY)
    monkeypatch.setattr(get_settings(), "razorpay_key_secret", TEST_SECRET)


def _ref():
    return uuid.uuid4().hex


def _collect(client, shop, rupees=250, **extra):
    return client.post("/api/payments/collect",
                       json={"amountPaise": rupees * 100, "clientRef": _ref(), **extra}, headers=shop)


# ---------- settings ----------


def test_settings_start_empty_then_upi_id(client, world):
    shop = _account(client, SHOP_A)
    start = client.get("/api/payments/settings", headers=shop).json()
    assert start["automatic"] is False and start["upiId"] is None and start["razorpayConnected"] is False

    saved = client.put("/api/payments/settings/upi",
                       json={"upiId": " lakshmi.stores@okaxis ", "upiName": "  Lakshmi   Stores "}, headers=shop)
    assert saved.status_code == 200, saved.text
    assert saved.json()["upiId"] == "lakshmi.stores@okaxis"
    assert saved.json()["upiName"] == "Lakshmi Stores"

    bad = client.put("/api/payments/settings/upi", json={"upiId": "not a upi id"}, headers=shop)
    assert bad.status_code == 400 and "UPI ID" in bad.json()["message"]

    removed = client.put("/api/payments/settings/upi", json={"upiId": ""}, headers=shop).json()
    assert removed["upiId"] is None and removed["upiName"] is None


def test_connect_razorpay_keeps_the_secret_encrypted(client, world):
    shop = _account(client, SHOP_A)
    response = client.post("/api/payments/settings/razorpay",
                           json={"keyId": SHOP_KEY, "keySecret": SHOP_SECRET}, headers=shop)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["razorpayConnected"] is True and body["automatic"] is True and body["testMode"] is True
    assert body["razorpayKeyHint"] == "rzp_test_••••8765"
    assert SHOP_SECRET not in response.text

    with engine.connect() as connection:
        stored = connection.execute(text("SELECT razorpay_secret FROM shop_payment_settings")).scalar_one()
    assert SHOP_SECRET not in stored and unlock(stored) == SHOP_SECRET

    off = client.delete("/api/payments/settings/razorpay", headers=shop).json()
    assert off["razorpayConnected"] is False and off["automatic"] is False


def test_wrong_razorpay_keys_are_refused(client, world):
    shop = _account(client, SHOP_A)
    world.keys_ok = False
    response = client.post("/api/payments/settings/razorpay",
                           json={"keyId": SHOP_KEY, "keySecret": SHOP_SECRET}, headers=shop)
    assert response.status_code == 400 and response.json()["code"] == "RAZORPAY_KEYS_WRONG"
    for keys in [{"keyId": "abc", "keySecret": SHOP_SECRET}, {"keyId": SHOP_KEY, "keySecret": "short"}]:
        assert client.post("/api/payments/settings/razorpay", json=keys, headers=shop).status_code == 400
    assert client.get("/api/payments/settings", headers=shop).json()["razorpayConnected"] is False


def test_test_account_is_used_until_the_shop_connects_its_own(client, world, test_account):
    shop = _account(client, SHOP_A)
    settings = client.get("/api/payments/settings", headers=shop).json()
    assert settings["automatic"] is True and settings["usingTestAccount"] is True
    _collect(client, shop)
    client.post("/api/payments/settings/razorpay", json={"keyId": SHOP_KEY, "keySecret": SHOP_SECRET}, headers=shop)
    assert client.get("/api/payments/settings", headers=shop).json()["usingTestAccount"] is False
    _collect(client, shop)
    assert [key for key, _, _ in world.made] == [TEST_KEY, SHOP_KEY]


# ---------- counter QR ----------


def test_no_payment_account_means_no_automatic_qr(client, world):
    shop = _account(client, SHOP_A)
    response = _collect(client, shop)
    assert response.status_code == 409 and response.json()["code"] == "NO_ONLINE_PAYMENTS"


def test_counter_qr_until_paid(client, world, test_account):
    shop = _account(client, SHOP_A)
    ref = _ref()
    made = client.post("/api/payments/collect",
                       json={"amountPaise": 25000, "note": " rice ", "clientRef": ref}, headers=shop)
    assert made.status_code == 201, made.text
    payment = made.json()
    assert payment["status"] == "WAITING" and payment["source"] == "COUNTER"
    assert payment["qrImageUrl"] == "https://rzp.io/qr.png" and payment["testMode"] is True
    assert payment["note"] == "rice"

    # The same request again (a retry) gives the same QR, not a second one.
    again = client.post("/api/payments/collect", json={"amountPaise": 25000, "clientRef": ref}, headers=shop)
    assert again.json()["id"] == payment["id"] and len(world.made) == 1

    assert client.get(f"/api/payments/{payment['id']}", headers=shop).json()["status"] == "WAITING"
    qr = world.made[0][1].ref
    world.pay(qr)
    _forget_last_check(payment["id"])
    paid = client.get(f"/api/payments/{payment['id']}", headers=shop).json()
    assert paid["status"] == "PAID" and paid["payerVpa"] == "ramesh@okaxis" and paid["method"] == "upi"

    today = client.get("/api/payments", headers=shop).json()
    assert today["totalPaise"] == 25000 and today["count"] == 1
    assert [p["id"] for p in today["payments"]] == [payment["id"]]


def test_payment_link_when_qr_codes_is_off(client, world, test_account):
    world.qr_on = False
    shop = _account(client, SHOP_A)
    payment = _collect(client, shop).json()
    assert payment["payUrl"] == "https://rzp.io/i/test" and payment["qrImageUrl"] is None


def test_counter_qr_for_udhaar_adds_one_payment_entry(client, world, test_account):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 500))
    payment = _collect(client, shop, rupees=200, udhaarCustomerId=customer["id"]).json()
    world.pay(world.made[0][1].ref)
    for _ in range(3):  # checked many times, counted once
        _forget_last_check(payment["id"])
        assert client.get(f"/api/payments/{payment['id']}", headers=shop).json()["customerName"] == "Ramesh"

    detail = client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop).json()
    assert detail["customer"]["balancePaise"] == 30000
    assert [(e["kind"], e["note"]) for e in detail["entries"]][0] == ("PAYMENT", "Paid by UPI QR")
    assert len(detail["entries"]) == 2


def test_wrong_amount_is_never_marked_paid(client, world, test_account):
    shop = _account(client, SHOP_A)
    payment = _collect(client, shop).json()
    world.pay(world.made[0][1].ref, amount=100)  # ₹1 paid for a ₹250 QR
    _forget_last_check(payment["id"])
    assert client.get(f"/api/payments/{payment['id']}", headers=shop).json()["status"] == "WAITING"


def test_cancel_and_expiry(client, world, test_account):
    shop = _account(client, SHOP_A)
    first = _collect(client, shop).json()
    cancelled = client.post(f"/api/payments/{first['id']}/cancel", headers=shop).json()
    assert cancelled["status"] == "CANCELLED" and world.closed == [world.made[0][1].ref]

    # Paid just before the cancel: recorded as paid, not cancelled.
    second = _collect(client, shop).json()
    world.pay(world.made[1][1].ref)
    assert client.post(f"/api/payments/{second['id']}/cancel", headers=shop).json()["status"] == "PAID"

    third = _collect(client, shop).json()
    with engine.begin() as connection:
        connection.execute(text("UPDATE payments SET expires_at = now() - interval '1 minute', checked_at = NULL "
                                "WHERE id = :id"), {"id": third["id"]})
    assert client.get(f"/api/payments/{third['id']}", headers=shop).json()["status"] == "EXPIRED"
    assert world.made[2][1].ref in world.closed


def test_manual_upi_payment(client, world):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 300))
    body = {"amountPaise": 10000, "clientRef": _ref(), "udhaarCustomerId": customer["id"]}
    first = client.post("/api/payments/manual", json=body, headers=shop)
    assert first.status_code == 201, first.text
    assert first.json()["status"] == "PAID" and first.json()["source"] == "MANUAL"
    assert client.post("/api/payments/manual", json=body, headers=shop).json()["id"] == first.json()["id"]
    detail = client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop).json()
    assert detail["customer"]["balancePaise"] == 20000 and len(detail["entries"]) == 2
    assert client.get("/api/payments", headers=shop).json()["totalPaise"] == 10000


def test_amount_and_customer_checks(client, world, test_account):
    shop = _account(client, SHOP_A)
    other = _account(client, SHOP_B)
    theirs = _add_customer(client, other)
    for body in [{"amountPaise": 50}, {"amountPaise": 100_000_001}, {"amountPaise": 100, "clientRef": "x"}]:
        assert client.post("/api/payments/collect", json={"clientRef": _ref(), **body}, headers=shop).status_code == 400
    # Another shop's udhaar customer looks like a missing one.
    response = _collect(client, shop, udhaarCustomerId=theirs["id"])
    assert response.status_code == 404
    assert world.made == []


# ---------- customer pays udhaar ----------


def _customer_setup(client, owes=500):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", owes))
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    return shop, customer["id"], ramesh


def _sign(order_id, payment_id, secret=TEST_SECRET):
    return hmac.new(secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256).hexdigest()


def test_customer_pays_udhaar_in_the_app(client, world, test_account):
    shop, book_id, ramesh = _customer_setup(client)
    started = client.post(f"/api/payments/udhaar/{book_id}",
                          json={"amountPaise": 30000, "clientRef": _ref()}, headers=ramesh)
    assert started.status_code == 201, started.text
    body = started.json()
    assert body["keyId"] == TEST_KEY and body["contact"] == RAMESH and body["shopName"]
    assert TEST_SECRET not in started.text
    order_id, payment_id = body["orderId"], body["payment"]["id"]

    paid = world.pay(order_id)
    forged = {"razorpayPaymentId": paid.payment_id, "razorpayOrderId": order_id, "razorpaySignature": "0" * 64}
    refused = client.post(f"/api/payments/{payment_id}/verify", json=forged, headers=ramesh)
    assert refused.status_code == 400 and refused.json()["code"] == "PAYMENT_NOT_VERIFIED"

    good = {**forged, "razorpaySignature": _sign(order_id, paid.payment_id)}
    verified = client.post(f"/api/payments/{payment_id}/verify", json=good, headers=ramesh)
    assert verified.status_code == 200, verified.text
    assert verified.json()["status"] == "PAID"
    assert client.post(f"/api/payments/{payment_id}/verify", json=good, headers=ramesh).json()["status"] == "PAID"

    book = client.get(f"/api/udhaar/mine/{book_id}", headers=ramesh).json()
    assert book["book"]["balancePaise"] == 20000
    assert book["entries"][0]["note"] == "Paid online in QBOX"
    today = client.get("/api/payments", headers=shop).json()
    assert today["totalPaise"] == 30000 and today["payments"][0]["customerName"] == "Ramesh"
    assert today["payments"][0]["source"] == "UDHAAR"


def test_customer_payment_found_without_the_app(client, world, test_account):
    """The customer paid but closed the app before it reported back: the shop's
    payments list finds it by asking Razorpay."""
    shop, book_id, ramesh = _customer_setup(client)
    body = client.post(f"/api/payments/udhaar/{book_id}",
                       json={"amountPaise": 50000, "clientRef": _ref()}, headers=ramesh).json()
    world.pay(body["orderId"])
    assert client.get("/api/payments", headers=shop).json()["totalPaise"] == 50000
    assert client.get(f"/api/udhaar/mine/{book_id}", headers=ramesh).json()["book"]["balancePaise"] == 0


def test_customer_payment_checks(client, world, test_account):
    shop, book_id, ramesh = _customer_setup(client, owes=200)
    too_much = client.post(f"/api/payments/udhaar/{book_id}",
                           json={"amountPaise": 20100, "clientRef": _ref()}, headers=ramesh)
    assert too_much.status_code == 400 and too_much.json()["code"] == "MORE_THAN_DUE"
    assert client.post(f"/api/payments/udhaar/{book_id + 999}",
                       json={"amountPaise": 100, "clientRef": _ref()}, headers=ramesh).status_code == 404
    # A shop account cannot use the customer path, and a customer cannot collect.
    assert client.post(f"/api/payments/udhaar/{book_id}",
                       json={"amountPaise": 100, "clientRef": _ref()}, headers=shop).status_code == 403
    assert _collect(client, ramesh).status_code == 403

    _post_entry(client, shop, book_id, _entry("PAYMENT", 200))
    settled = client.post(f"/api/payments/udhaar/{book_id}",
                          json={"amountPaise": 100, "clientRef": _ref()}, headers=ramesh)
    assert settled.status_code == 409 and settled.json()["code"] == "NOTHING_DUE"


def test_shop_without_online_payments(client, world):
    _, book_id, ramesh = _customer_setup(client)
    response = client.post(f"/api/payments/udhaar/{book_id}",
                           json={"amountPaise": 100, "clientRef": _ref()}, headers=ramesh)
    assert response.status_code == 409 and response.json()["code"] == "SHOP_NO_ONLINE"


def test_payments_are_private(client, world, test_account):
    shop, book_id, ramesh = _customer_setup(client)
    counter = _collect(client, shop).json()
    mine = client.post(f"/api/payments/udhaar/{book_id}",
                       json={"amountPaise": 100, "clientRef": _ref()}, headers=ramesh).json()["payment"]
    other_shop = _account(client, SHOP_B)
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    for who in (other_shop, stranger):
        assert client.get(f"/api/payments/{counter['id']}", headers=who).status_code == 404
        assert client.get(f"/api/payments/{mine['id']}", headers=who).status_code == 404
        assert client.post(f"/api/payments/{counter['id']}/cancel", headers=who).status_code == 404
    # The customer sees their own payment, but not the shop's counter payments, and cannot cancel.
    assert client.get(f"/api/payments/{mine['id']}", headers=ramesh).status_code == 200
    assert client.get(f"/api/payments/{counter['id']}", headers=ramesh).status_code == 404
    assert client.post(f"/api/payments/{mine['id']}/cancel", headers=ramesh).status_code == 404
    assert client.get("/api/payments", headers=other_shop).json()["count"] == 0


def test_too_many_requests(client, world, test_account, monkeypatch):
    from app.payments import service
    monkeypatch.setattr(service, "SHOP_REQUESTS_PER_10_MIN", 2)
    shop = _account(client, SHOP_A)
    assert _collect(client, shop).status_code == 201
    assert _collect(client, shop).status_code == 201
    response = _collect(client, shop)
    assert response.status_code == 429 and response.json()["code"] == "PAYMENT_LIMIT"


def _forget_last_check(payment_id):
    """Payments are checked with Razorpay at most every 2 seconds; tests skip the wait."""
    with engine.begin() as connection:
        connection.execute(text("UPDATE payments SET checked_at = NULL WHERE id = :id"), {"id": payment_id})


# ---------- the real Razorpay client, against recorded answers ----------


def _razorpay(handler):
    return Razorpay(TEST_KEY, TEST_SECRET, http=httpx.Client(transport=httpx.MockTransport(handler)))


def test_client_sends_keys_and_reads_a_qr():
    seen = {}

    def handler(request):
        seen["auth"] = request.headers["authorization"]
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"id": "qr_ABC123", "image_url": "https://rzp.io/i/qr"})

    made = _razorpay(handler).create_qr(25000, "Shop: rice", datetime.now(UTC) + timedelta(minutes=20), {})
    assert made.ref == "qr_ABC123" and made.gateway == Gateway.QR_CODE
    assert seen["auth"].startswith("Basic ")
    assert seen["body"]["payment_amount"] == 25000 and seen["body"]["usage"] == "single_use"


def test_client_knows_when_qr_codes_is_off_and_when_keys_are_wrong():
    from app.errors import ApiError

    off = _razorpay(lambda r: httpx.Response(400, json={"error": {
        "code": "BAD_REQUEST_ERROR", "description": "The requested URL was not found on the server."}}))
    with pytest.raises(FeatureOff):
        off.create_qr(100, "x", datetime.now(UTC) + timedelta(minutes=20), {})

    wrong = _razorpay(lambda r: httpx.Response(401, json={"error": {"description": "Authentication failed"}}))
    with pytest.raises(ApiError) as error:
        wrong.check_keys()
    assert error.value.code == "RAZORPAY_KEYS_WRONG" and error.value.status_code == 400


def test_client_captures_an_authorized_payment():
    def handler(request):
        if request.url.path.endswith("/capture"):
            return httpx.Response(200, json={"id": "pay_X1", "amount": 500, "currency": "INR",
                                             "status": "captured", "method": "upi", "vpa": "a@ybl",
                                             "order_id": "order_1", "created_at": 1763800000})
        return httpx.Response(200, json={"items": [{"id": "pay_X1", "amount": 500, "currency": "INR",
                                                    "status": "authorized"}]})

    paid = _razorpay(handler).find_paid(Gateway.ORDER, "order_1", 500)
    assert paid.payment_id == "pay_X1" and paid.vpa == "a@ybl" and paid.order_id == "order_1"


def test_client_signature_check():
    client = _razorpay(lambda r: httpx.Response(200, json={}))
    assert client.signature_ok("order_1", "pay_1", _sign("order_1", "pay_1"))
    assert not client.signature_ok("order_1", "pay_2", _sign("order_1", "pay_1"))
    assert not client.signature_ok("order_1", "pay_1", "")


def test_unreadable_saved_key_is_not_used(monkeypatch):
    stored = lock(SHOP_SECRET)
    monkeypatch.setattr(get_settings(), "payment_secret_key", "a-different-key-than-before-0123456789")
    assert unlock(stored) is None
