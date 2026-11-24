"""Pay to Shop: finding the shop, paying online (pretend Razorpay) or by UPI,
the shop's confirmation, privacy and limits."""

import pytest
from sqlalchemy import text

from app import ratelimit
from app.database import engine
from tests.test_calendar import _account
from tests.test_customer import _history
from tests.test_payments import SHOP_KEY, SHOP_SECRET, _ref, _sign, test_account, world  # noqa: F401
from tests.test_udhaar import RAMESH, SHOP_A, SHOP_B, _add_customer, _entry, _post_entry

UPI = "lakshmi@okaxis"


@pytest.fixture(autouse=True)
def _no_old_counts():
    ratelimit.forget()


def _people(client, upi=False):
    shop = _account(client, SHOP_A)
    if upi:
        client.put("/api/payments/settings/upi", json={"upiId": UPI, "upiName": "Lakshmi"}, headers=shop)
    return shop, _account(client, RAMESH, roles=("CUSTOMER",))


def _find(client, who, mobile=SHOP_A):
    return client.post("/api/payments/shops/find", json={"mobile": mobile}, headers=who)


def _pay(client, who, ref=f"mobile:{SHOP_A}", rupees=150, method="ONLINE", client_ref=None, **extra):
    return client.post("/api/payments/shop", headers=who, json={
        "ref": ref, "amountPaise": rupees * 100, "method": method, "clientRef": client_ref or _ref(), **extra})


def _claimed(client, who, **extra):
    payment = _pay(client, who, method="UPI", **extra).json()["payment"]
    return client.post(f"/api/payments/{payment['id']}/claim", headers=who).json()


def _day(client, shop):
    return client.get("/api/payments", headers=shop).json()


# ---------- finding a shop ----------


def test_find_a_shop_by_its_login_number(client, world, test_account):  # noqa: F811
    _, ramesh = _people(client)
    found = _find(client, ramesh)
    assert found.status_code == 200, found.text
    body = found.json()
    assert body["shopName"] and body["shopCategory"] and body["ref"] == f"mobile:{SHOP_A}"
    assert body["online"] is True and body["testMode"] is True and body["upi"] is False
    # Only what is needed to check the shop: no address, owner or UPI ID.
    assert set(body) == {"ref", "shopName", "shopCategory", "shopPhoto", "bookId", "duePaise", "online", "testMode", "upi"}


def test_numbers_that_are_not_a_shop(client, world):  # noqa: F811
    _, ramesh = _people(client)
    _account(client, "9000000001", roles=("CUSTOMER",))
    for mobile in ("9000000001", "9000000002"):  # a customer, and nobody: the same answer
        answer = _find(client, ramesh, mobile)
        assert answer.status_code == 404 and answer.json()["code"] == "SHOP_NOT_FOUND"
    assert _find(client, ramesh, "123").status_code == 400


def test_a_typed_contact_number_is_not_trusted(client, world):  # noqa: F811
    """Shop B writes shop A's number as its contact: it must still find shop A."""
    _people(client)
    _account(client, SHOP_B)
    ramesh2 = _account(client, "9000000003", roles=("CUSTOMER",))
    with engine.begin() as connection:
        connection.execute(text("UPDATE shop_profiles SET shop_name = 'Fake', contact_number = :n WHERE user_id = "
                                "(SELECT id FROM users WHERE mobile = :b)"), {"n": SHOP_A, "b": SHOP_B})
    assert _find(client, ramesh2).json()["shopName"] != "Fake"


def test_look_ups_are_limited(client, world, monkeypatch):  # noqa: F811
    monkeypatch.setattr(ratelimit, "LOOKUPS_PER_HOUR", 3)
    _, ramesh = _people(client)
    for _ in range(3):
        _find(client, ramesh, "9000000009")
    assert _find(client, ramesh).status_code == 429
    # Paying with a number is a look-up too.
    assert _pay(client, ramesh).status_code == 429
    other = _account(client, "9000000004", roles=("CUSTOMER",))
    assert _find(client, other).status_code == 200


def test_own_shop_cannot_be_paid(client, world, test_account):  # noqa: F811
    both = _account(client, SHOP_A, roles=("BUSINESS", "CUSTOMER"))
    assert _find(client, both).json()["code"] == "OWN_SHOP"
    assert _pay(client, both).json()["code"] == "OWN_SHOP"


def test_linked_shops_then_shops_paid_before(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 90))
    _account(client, SHOP_B)
    start = _pay(client, ramesh, ref=f"mobile:{SHOP_B}").json()
    _finish(client, world, ramesh, start)

    listed = client.get("/api/payments/shops", headers=ramesh).json()["shops"]
    assert [s["ref"] for s in listed] == [f"book:{customer['id']}", f"paid:{start['payment']['id']}"]
    assert listed[0]["duePaise"] == 9000
    for item in listed:
        assert _pay(client, ramesh, ref=item["ref"]).status_code == 201
    # Finding a linked shop by number gives its book (so udhaar due is shown).
    assert _find(client, ramesh).json()["duePaise"] == 9000


# ---------- online ----------


def _finish(client, world, who, start):  # noqa: F811
    paid = world.pay(start["orderId"])
    return client.post(f"/api/payments/{start['payment']['id']}/verify", headers=who, json={
        "razorpayPaymentId": paid.payment_id, "razorpayOrderId": start["orderId"],
        "razorpaySignature": _sign(start["orderId"], paid.payment_id)})


def test_pay_online(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    start = _pay(client, ramesh, note=" milk ").json()
    assert start["keyId"] and start["orderId"] and start["upiId"] is None
    assert _history(client, ramesh)["transactions"] == []  # nothing until paid
    assert _finish(client, world, ramesh, start).json()["status"] == "PAID"

    day = _day(client, shop)
    assert day["totalPaise"] == 15000 and day["payments"][0]["source"] == "DIRECT"
    assert day["payments"][0]["customerName"] and day["payments"][0]["note"] == "milk"
    items = _history(client, ramesh)["transactions"]
    assert [(t["amountPaise"], t["online"], t["status"]) for t in items] == [(15000, True, "PAID")]


def test_udhaar_is_not_changed(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 500))
    start = _pay(client, ramesh, ref=f"book:{customer['id']}").json()
    _finish(client, world, ramesh, start)
    assert client.get("/api/udhaar/mine", headers=ramesh).json()[0]["balancePaise"] == 50000


def test_forged_signature_is_refused(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    start = _pay(client, ramesh).json()
    paid = world.pay(start["orderId"])
    forged = client.post(f"/api/payments/{start['payment']['id']}/verify", headers=ramesh, json={
        "razorpayPaymentId": paid.payment_id, "razorpayOrderId": start["orderId"], "razorpaySignature": "0" * 64})
    assert forged.status_code == 400


def test_the_same_request_twice_is_one_payment(client, world, test_account):  # noqa: F811
    _, ramesh = _people(client)
    ref = _ref()
    first, again = _pay(client, ramesh, client_ref=ref).json(), _pay(client, ramesh, client_ref=ref).json()
    assert first["payment"]["id"] == again["payment"]["id"] and first["orderId"] == again["orderId"]
    assert len(world.made) == 1
    assert _pay(client, ramesh, client_ref=ref, rupees=999).status_code == 409
    other = _account(client, "9000000001", roles=("CUSTOMER",))
    assert _pay(client, other, client_ref=ref).status_code == 404


# ---------- UPI ----------


def test_upi_counts_only_after_the_shop_confirms(client, world):  # noqa: F811
    shop, ramesh = _people(client, upi=True)
    assert _find(client, ramesh).json()["online"] is False
    start = _pay(client, ramesh, method="UPI").json()
    assert start["upiId"] == UPI and start["orderId"] is None
    payment_id = start["payment"]["id"]
    assert _day(client, shop)["toConfirm"] == []  # not claimed yet

    assert client.post(f"/api/payments/{payment_id}/claim", headers=ramesh).json()["claimedAt"]
    day = _day(client, shop)
    assert [p["id"] for p in day["toConfirm"]] == [payment_id] and day["toConfirm"][0]["customerName"]
    assert day["totalPaise"] == 0
    assert _history(client, ramesh)["transactions"][0]["status"] == "WAITING"

    for _ in range(2):  # tapped twice: counted once
        assert client.post(f"/api/payments/{payment_id}/confirm", headers=shop).json()["status"] == "PAID"
    day = _day(client, shop)
    assert day["totalPaise"] == 15000 and day["count"] == 1 and day["toConfirm"] == []
    item = _history(client, ramesh)["transactions"]
    assert [(t["status"], t["online"]) for t in item] == [("PAID", False)]


def test_shop_says_not_received_and_the_first_answer_stands(client, world):  # noqa: F811
    shop, ramesh = _people(client, upi=True)
    payment = _claimed(client, ramesh)
    assert client.post(f"/api/payments/{payment['id']}/not-received", headers=shop).json()["status"] == "CANCELLED"
    assert client.post(f"/api/payments/{payment['id']}/confirm", headers=shop).json()["status"] == "CANCELLED"
    assert _day(client, shop)["totalPaise"] == 0
    assert _history(client, ramesh)["transactions"][0]["status"] == "NOT_CONFIRMED"


def test_did_not_pay_and_unanswered_question(client, world):  # noqa: F811
    shop, ramesh = _people(client, upi=True)
    payment = _pay(client, ramesh, method="UPI").json()["payment"]
    asked = client.get("/api/payments/shops", headers=ramesh).json()["unfinished"]
    assert [u["payment"]["id"] for u in asked] == [payment["id"]] and asked[0]["shopName"]
    client.post(f"/api/payments/{payment['id']}/drop", headers=ramesh)
    assert client.get("/api/payments/shops", headers=ramesh).json()["unfinished"] == []
    # After "I did not pay", "I paid" does nothing, and the other way round.
    assert client.post(f"/api/payments/{payment['id']}/claim", headers=ramesh).json()["claimedAt"] is None
    claimed = _claimed(client, ramesh)
    assert client.post(f"/api/payments/{claimed['id']}/drop", headers=ramesh).json()["status"] == "WAITING"
    assert len(_day(client, shop)["toConfirm"]) == 1


def test_confirmed_money_counts_on_the_day_it_came(client, world):  # noqa: F811
    shop, ramesh = _people(client, upi=True)
    payment = _claimed(client, ramesh)
    with engine.begin() as connection:
        connection.execute(text("UPDATE payments SET claimed_at = '2026-11-20T10:00:00+05:30'"))
    client.post(f"/api/payments/{payment['id']}/confirm", headers=shop)
    assert client.get("/api/payments?day=2026-11-20", headers=shop).json()["totalPaise"] == 15000


def test_only_the_right_people_can_answer(client, world):  # noqa: F811
    shop, ramesh = _people(client, upi=True)
    waiting = _pay(client, ramesh, method="UPI").json()["payment"]["id"]
    claimed = _claimed(client, ramesh)["id"]
    other_shop = _account(client, SHOP_B)
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    for who in (other_shop, stranger, ramesh):
        assert client.post(f"/api/payments/{claimed}/confirm", headers=who).status_code in (403, 404)
    for who in (other_shop, stranger, shop):
        assert client.post(f"/api/payments/{waiting}/claim", headers=who).status_code == 404
    # The shop cannot confirm what the customer has not said they paid.
    assert client.post(f"/api/payments/{waiting}/confirm", headers=shop).status_code == 404
    assert _day(client, other_shop)["toConfirm"] == []


def test_online_payments_cannot_be_confirmed_by_hand(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    payment = _pay(client, ramesh).json()["payment"]["id"]
    assert client.post(f"/api/payments/{payment}/claim", headers=ramesh).status_code == 404
    assert client.post(f"/api/payments/{payment}/confirm", headers=shop).status_code == 404


def test_which_ways_a_shop_offers(client, world):  # noqa: F811
    shop, ramesh = _people(client)
    assert _pay(client, ramesh).json()["code"] == "SHOP_NO_ONLINE"
    assert _pay(client, ramesh, method="UPI").json()["code"] == "SHOP_NO_UPI"
    client.put("/api/payments/settings/upi", json={"upiId": UPI}, headers=shop)
    assert _find(client, ramesh).json()["upi"] is True
    # With its own Razorpay connected, payments confirm by themselves: no by-hand UPI.
    client.post("/api/payments/settings/razorpay", json={"keyId": SHOP_KEY, "keySecret": SHOP_SECRET}, headers=shop)
    found = _find(client, ramesh).json()
    assert found["online"] is True and found["upi"] is False


# ---------- checks ----------


def test_references_to_others_do_not_work(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    book = _add_customer(client, shop)["id"]
    start = _pay(client, ramesh).json()
    _finish(client, world, ramesh, start)
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    assert _pay(client, stranger, ref=f"book:{book}").status_code == 404
    assert _pay(client, stranger, ref=f"paid:{start['payment']['id']}").status_code == 404
    for bad in ("shop:1", "book:x", "mobile:123", "book:1;", ""):
        assert _pay(client, ramesh, ref=bad).status_code == 400


def test_amounts_roles_and_login(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    for paise in (0, 99, 100_000_001):
        response = client.post("/api/payments/shop", headers=ramesh, json={
            "ref": f"mobile:{SHOP_A}", "amountPaise": paise, "method": "ONLINE", "clientRef": _ref()})
        assert response.status_code == 400
    other_shop = _account(client, SHOP_B)
    assert _pay(client, other_shop).status_code == 403
    assert _find(client, other_shop).status_code == 403
    assert client.get("/api/payments/shops", headers=other_shop).status_code == 403
    assert client.get("/api/payments/shops").status_code == 401


def test_payment_requests_are_limited(client, world, test_account, monkeypatch):  # noqa: F811
    from app.payments import service
    monkeypatch.setattr(service, "CUSTOMER_REQUESTS_PER_10_MIN", 2)
    _, ramesh = _people(client)
    assert [_pay(client, ramesh).status_code for _ in range(3)] == [201, 201, 429]


def test_waiting_upi_never_blocks_the_razorpay_checks(client, world, test_account):  # noqa: F811
    """Many unanswered UPI payments must not stop a paid online one being found."""
    _, ramesh = _people(client, upi=True)
    for _ in range(6):
        _pay(client, ramesh, method="UPI")
    start = _pay(client, ramesh).json()
    world.pay(start["orderId"])
    assert [t["amountPaise"] for t in _history(client, ramesh)["transactions"]] == [15000]


# ---------- the shop's QR ----------


def _qr(client, shop):
    response = client.get("/api/payments/settings/qr", headers=shop)
    assert response.status_code == 200, response.text
    return response.json()


def _scan(client, who, code):
    return client.post("/api/payments/shops/scan", json={"code": code}, headers=who)


def test_shop_qr_stays_the_same_and_hides_the_number(client, world):  # noqa: F811
    shop, _ = _people(client)
    qr = _qr(client, shop)
    assert qr["data"].startswith("qbox://pay?qbox=") and qr["worksInUpiApps"] is False
    assert SHOP_A not in qr["data"]
    code = qr["data"].split("qbox=")[1]
    client.put("/api/payments/settings/upi", json={"upiId": UPI, "upiName": "Lakshmi & Sons"}, headers=shop)
    after = _qr(client, shop)
    assert after["data"] == f"upi://pay?pa=lakshmi%40okaxis&pn=Lakshmi%20%26%20Sons&cu=INR&qbox={code}"
    assert after["worksInUpiApps"] is True
    assert _qr(client, _account(client, SHOP_B))["data"].split("qbox=")[1] != code


def test_scan_and_pay(client, world, test_account):  # noqa: F811
    shop, ramesh = _people(client)
    code = _qr(client, shop)["data"].split("qbox=")[1]
    found = _scan(client, ramesh, code).json()
    assert found["shopName"] and found["ref"] == f"code:{code}" and found["online"] is True
    start = _pay(client, ramesh, ref=found["ref"]).json()
    assert _finish(client, world, ramesh, start).json()["status"] == "PAID"
    assert _day(client, shop)["totalPaise"] == 15000

    # Once linked, scanning shows the udhaar there.
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 90))
    again = _scan(client, ramesh, code).json()
    assert again["ref"] == f"book:{customer['id']}" and again["duePaise"] == 9000


def test_scan_checks(client, world):  # noqa: F811
    shop, ramesh = _people(client)
    code = _qr(client, shop)["data"].split("qbox=")[1]
    unknown = _scan(client, ramesh, "a" * 16)
    assert unknown.status_code == 404 and unknown.json()["code"] == "SHOP_NOT_FOUND"
    assert _pay(client, ramesh, ref="code:" + "a" * 16).status_code == 404
    for bad in ("", "A" * 16, "1" * 16, "abc"):
        assert _scan(client, ramesh, bad).status_code == 400
    assert _scan(client, shop, code).status_code == 403
    assert client.get("/api/payments/settings/qr", headers=ramesh).status_code == 403
    assert client.get("/api/payments/settings/qr").status_code == 401
    both = _account(client, "9000000005", roles=("BUSINESS", "CUSTOMER"))
    assert _scan(client, both, _qr(client, both)["data"].split("qbox=")[1]).json()["code"] == "OWN_SHOP"
