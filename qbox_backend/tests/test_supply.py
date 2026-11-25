"""Supplier side: connecting, opening balance, orders, agreeing on entries,
disconnecting, privacy, and the bell."""

from datetime import datetime

import pytest
from sqlalchemy import text

from app import ratelimit
from app.config import get_settings
from app.database import engine
from app.udhaar.schemas import INDIA
from tests.test_auth import SUPPLIER
from tests.test_calendar import _account
from tests.test_stock import _item
from tests.test_suppliers import AT, _entry, _qty, _ref, _supplier
from tests.test_udhaar import SHOP_A, SHOP_B

RAVI = "9848022338"
OTHER = "9000000005"


@pytest.fixture(autouse=True)
def _no_old_counts():
    ratelimit.forget()


def _ravi(client, mobile=RAVI):
    return _account(client, mobile, roles=("SUPPLIER",))


def _code(client, shop, supplier_id):
    return client.post(f"/api/suppliers/{supplier_id}/otp", headers=shop)


def _verify(client, shop, supplier_id, code):
    return client.post(f"/api/suppliers/{supplier_id}/verify", json={"otp": code}, headers=shop)


def _ask(client, shop, supplier_id):
    """The code is sent, and read out by the supplier."""
    with engine.begin() as connection:  # tests do not wait between codes
        connection.execute(text("UPDATE otp_codes SET created_at = created_at - interval '2 minutes'"))
    sent = _code(client, shop, supplier_id)
    return _verify(client, shop, supplier_id, sent.json()["devOtp"]) if sent.status_code == 200 else sent


def _home(client, ravi):
    answer = client.get("/api/supply/shops", headers=ravi)
    assert answer.status_code == 200, answer.text
    return answer.json()


def _accept(client, ravi, link, balance):
    return client.post(f"/api/supply/shops/{link}/accept", json={"balancePaise": balance}, headers=ravi)


def _connected(client, owed=0):
    """(shop, ravi, the shop's supplier id, link id)"""
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    if owed:
        _entry(client, shop, supplier, "PURCHASE", owed)
    assert _ask(client, shop, supplier).status_code == 200
    return shop, ravi, supplier, _home(client, ravi)["shops"][0]["linkId"]


def _waiting(client, owed=0):
    """Verified before Ravi joins QBOX: he is asked, and says yes or no himself."""
    shop = _account(client, SHOP_A)
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    if owed:
        _entry(client, shop, supplier, "PURCHASE", owed)
    verified = _ask(client, shop, supplier).json()
    assert verified["verified"] is True and verified["link"] is None
    ravi = _ravi(client)
    return shop, ravi, supplier, _home(client, ravi)["requests"][0]["linkId"]


def _shop_side(client, shop, supplier):
    return client.get(f"/api/suppliers/{supplier}", headers=shop).json()


def _supplier_side(client, ravi, link):
    answer = client.get(f"/api/supply/shops/{link}", headers=ravi)
    assert answer.status_code == 200, answer.text
    return answer.json()


def _same_balance(client, shop, supplier, ravi, link, rupees):
    assert _shop_side(client, shop, supplier)["supplier"]["balancePaise"] == rupees * 100
    assert _supplier_side(client, ravi, link)["shop"]["balancePaise"] == rupees * 100


def _bell(client, who, role):
    return [n["kind"] for n in client.get(f"/api/notices?role={role}", headers=who).json()["notices"]]


# ---------- connecting by code ----------


def test_connecting_while_adding(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    sent = client.post("/api/suppliers/otp", json={"name": "Ravi Traders", "mobile": RAVI}, headers=shop)
    assert sent.status_code == 200, sent.text
    assert sent.json()["balancePaise"] == 0
    body = {"name": "Ravi Traders", "mobile": RAVI, "otp": sent.json()["devOtp"], "clientRef": _ref()}
    added = client.post("/api/suppliers", json=body, headers=shop)
    assert added.status_code == 201, added.text
    assert added.json()["verified"] is True and added.json()["link"]["status"] == "ON"
    assert client.post("/api/suppliers", json=body, headers=shop).json()["id"] == added.json()["id"]  # a retry
    home = _home(client, ravi)
    assert [(s["shopName"], s["openingPaise"], s["connected"]) for s in home["shops"]] == [
        ("Sri Balaji Kirana", 0, True)]
    assert _bell(client, shop, "BUSINESS") == ["CONNECTED"]


def test_adding_without_a_code_still_works(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    added = _supplier(client, shop, mobile=RAVI)
    assert added["verified"] is False and added["link"] is None
    assert _home(client, ravi)["shops"] == []
    assert _supplier(client, shop, "No phone")["verified"] is False


def test_wrong_codes(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    code = client.post("/api/suppliers/otp", json={"name": "Ravi", "mobile": RAVI}, headers=shop).json()["devOtp"]
    body = {"name": "Ravi", "mobile": RAVI, "clientRef": _ref()}
    wrong = "000000" if code != "000000" else "111111"
    for otp in (wrong, "12", "abcdef"):
        assert client.post("/api/suppliers", json={**body, "otp": otp}, headers=shop).status_code == 400
    # Another shop, another number: the code does not work there.
    other = _account(client, SHOP_B)
    assert client.post("/api/suppliers", json={**body, "otp": code}, headers=other).status_code == 400
    assert client.post("/api/suppliers", json={**body, "mobile": OTHER, "otp": code}, headers=shop).status_code == 400
    assert client.get("/api/suppliers", headers=shop).json()["suppliers"] == []
    assert _home(client, ravi)["shops"] == []
    assert client.post("/api/suppliers", json={**body, "otp": code}, headers=shop).status_code == 201


def test_the_message_says_the_amount_and_the_code_is_only_for_it(client, monkeypatch):
    said = []
    monkeypatch.setattr("app.auth.otp.send_sms", lambda mobile, words: said.append((mobile, words)))
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    said.clear()
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    _entry(client, shop, supplier, "PURCHASE", 500, note="secret price")
    sent = _code(client, shop, supplier).json()
    assert sent["balancePaise"] == 50000
    assert said[0][0] == RAVI and "They say they owe you Rs 500." in said[0][1]
    assert "Sri Balaji Kirana" in said[0][1] and sent["devOtp"] in said[0][1]
    # The shop writes a payment after the message: the code no longer fits.
    _entry(client, shop, supplier, "PAYMENT", 400)
    late = _verify(client, shop, supplier, sent["devOtp"])
    assert (late.status_code, late.json()["code"]) == (409, "CODE_OUTDATED")
    assert _home(client, ravi)["shops"] == []
    assert _ask(client, shop, supplier).json()["link"]["status"] == "ON"
    detail = _supplier_side(client, ravi, _home(client, ravi)["shops"][0]["linkId"])
    assert detail["shop"]["openingPaise"] == 10000 and detail["entries"] == []  # old entries stay private
    assert "secret" not in str(detail)


def test_a_code_for_adding_cannot_connect_an_old_account(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    _entry(client, shop, supplier, "PURCHASE", 500)
    code = client.post("/api/suppliers/otp", json={"name": "Someone", "mobile": RAVI}, headers=shop).json()["devOtp"]
    assert _verify(client, shop, supplier, code).json()["code"] == "CODE_OUTDATED"
    assert _home(client, ravi)["shops"] == []


def test_who_can_get_a_code(client):
    shop = _account(client, SHOP_A)
    none = _supplier(client, shop, "No number")["id"]
    assert _code(client, shop, none).json()["code"] == "NO_MOBILE"
    own = _supplier(client, shop, "Me", mobile=SHOP_A)["id"]
    assert _code(client, shop, own).json()["code"] == "OWN_NUMBER"
    for body, code in (({"name": "Me again", "mobile": SHOP_A}, "OWN_NUMBER"),
                       ({"name": "ME", "mobile": OTHER}, "SUPPLIER_EXISTS")):
        assert client.post("/api/suppliers/otp", json=body, headers=shop).json()["code"] == code
    assert client.post("/api/suppliers/otp", json={"name": "X", "mobile": "12"}, headers=shop).status_code == 400
    customer = _account(client, OTHER, roles=("CUSTOMER",))
    assert client.post("/api/suppliers/otp", json={"name": "X", "mobile": RAVI}, headers=customer).status_code == 403


def test_codes_are_limited_and_never_block_login(client, monkeypatch):
    shop = _account(client, SHOP_A)
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    assert _code(client, shop, supplier).status_code == 200
    assert _code(client, shop, supplier).json()["code"] == "OTP_TOO_SOON"
    for _ in range(4):
        assert _ask(client, shop, supplier).status_code in (200, 409)
    assert _ask(client, shop, supplier).status_code in (409, 429)
    # Their own sign-up code still comes.
    assert client.post("/api/auth/otp/send", json={"mobile": RAVI, "purpose": "SIGNUP"}).status_code == 200
    monkeypatch.setattr(get_settings(), "udhaar_invites_per_hour", 0)
    other = _supplier(client, shop, "Other", mobile=OTHER)["id"]
    assert _code(client, shop, other).json()["code"] == "INVITE_LIMIT"


def test_one_connection_for_a_number(client):
    shop, ravi, supplier, _ = _connected(client)
    twin = _supplier(client, shop, "Ravi again", mobile=RAVI)["id"]
    assert _code(client, shop, twin).json()["code"] == "ALREADY_CONNECTED"
    assert _code(client, shop, supplier).json()["code"] == "ALREADY_CONNECTED"
    assert client.post("/api/suppliers/otp", json={"name": "Third", "mobile": RAVI},
                       headers=shop).json()["code"] == "ALREADY_CONNECTED"


# ---------- verified before they joined QBOX ----------


def test_joining_later_they_say_yes_themselves(client):
    shop, ravi, supplier, link = _waiting(client, owed=500)
    request = _home(client, ravi)["requests"]
    assert (request[0]["shopName"], request[0]["balancePaise"]) == ("Sri Balaji Kirana", 50000)
    assert _bell(client, ravi, "SUPPLIER") == ["WANTS_TO_CONNECT"]
    assert client.get(f"/api/supply/shops/{link}", headers=ravi).status_code == 404  # nothing is readable yet
    _entry(client, shop, supplier, "PURCHASE", 100)
    late = _accept(client, ravi, link, 50000)
    assert (late.status_code, late.json()["code"]) == (409, "BALANCE_CHANGED")
    for _ in range(2):  # a retry
        assert _accept(client, ravi, link, 60000).status_code == 200
    _same_balance(client, shop, supplier, ravi, link, 600)


def test_saying_no_then_a_new_code(client):
    shop, ravi, supplier, link = _waiting(client)
    no = client.post(f"/api/supply/shops/{link}/decline", json={"reason": "You owe 600"}, headers=ravi)
    assert no.status_code == 204
    said = _shop_side(client, shop, supplier)["supplier"]["link"]
    assert (said["status"], said["reason"]) == ("DECLINED", "You owe 600")
    assert _accept(client, ravi, link, 0).status_code == 409
    assert _bell(client, shop, "BUSINESS") == ["NOT_CONNECTED"]
    assert _ask(client, shop, supplier).json()["link"]["status"] == "ON"


def test_a_code_while_they_are_still_thinking(client):
    shop, ravi, supplier, link = _waiting(client, owed=10)
    assert _ask(client, shop, supplier).json()["link"]["status"] == "ON"
    home = _home(client, ravi)
    assert home["requests"] == [] and home["shops"][0]["linkId"] == link


def test_adding_the_supplier_role_later(client):
    shop = _account(client, SHOP_A)
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    _ask(client, shop, supplier)
    ravi = _account(client, RAVI, roles=("CUSTOMER",))
    client.post("/api/me/roles", headers=ravi, json={"role": "SUPPLIER", "pin": "4826", "supplier": SUPPLIER})
    assert len(_home(client, ravi)["requests"]) == 1


def test_only_verified_numbers_are_asked(client):
    shop = _account(client, SHOP_A)
    _supplier(client, shop, mobile=RAVI)  # typed, never checked
    changed = _supplier(client, shop, "Changed", mobile=OTHER)["id"]
    _ask(client, shop, changed)
    client.put(f"/api/suppliers/{changed}", json={"name": "Changed", "mobile": "9000000006"}, headers=shop)
    for mobile in (RAVI, OTHER, "9000000006"):
        assert _home(client, _ravi(client, mobile))["requests"] == []


def test_taking_the_question_back(client):
    shop, ravi, supplier, link = _waiting(client)
    assert client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop).json()["link"]["status"] == "CANCELLED"
    assert _home(client, ravi)["requests"] == []
    assert _accept(client, ravi, link, 0).status_code == 409


# ---------- the account ----------


def test_a_purchase_counts_and_a_payment_waits(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    _entry(client, shop, supplier, "PURCHASE", 1000)
    _entry(client, shop, supplier, "PAYMENT", 400, method="UPI")
    _same_balance(client, shop, supplier, ravi, link, 1100)
    detail = _supplier_side(client, ravi, link)
    assert detail["shop"]["toConfirm"] == 2
    payment = next(e for e in detail["entries"] if e["kind"] == "PAYMENT")
    for _ in range(2):  # a retry changes nothing
        assert client.post(f"/api/supply/entries/{payment['id']}/confirm", headers=ravi).json()["confirm"] == "CONFIRMED"
    _same_balance(client, shop, supplier, ravi, link, 700)


def test_a_payment_that_never_came(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    payment = _entry(client, shop, supplier, "PAYMENT", 40).json()["id"]
    url = f"/api/supply/entries/{payment}/dispute"
    assert client.post(url, json={"reason": " "}, headers=ravi).status_code == 400
    assert client.post(url, json={"reason": "Not received"}, headers=ravi).json()["confirm"] == "DISPUTED"
    _same_balance(client, shop, supplier, ravi, link, 100)
    entry = next(e for e in _shop_side(client, shop, supplier)["entries"] if e["id"] == payment)
    assert (entry["confirm"], entry["disputeReason"]) == ("DISPUTED", "Not received")
    assert "NOT_RIGHT" in _bell(client, shop, "BUSINESS")
    # The supplier finds the money after all.
    client.post(f"/api/supply/entries/{payment}/confirm", headers=ravi)
    _same_balance(client, shop, supplier, ravi, link, 60)
    assert client.post(url, json={"reason": "x"}, headers=ravi).json()["code"] == "ALREADY_CONFIRMED"


def test_what_both_agreed_cannot_be_deleted(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    old = _shop_side(client, shop, supplier)["entries"][0]["id"]
    agreed = _entry(client, shop, supplier, "PURCHASE", 50).json()["id"]
    mistake = _entry(client, shop, supplier, "PURCHASE", 70).json()["id"]
    client.post(f"/api/supply/entries/{agreed}/confirm", headers=ravi)
    for entry in (old, agreed):
        answer = client.post(f"/api/suppliers/entries/{entry}/delete", json={"reason": "x"}, headers=shop)
        assert (answer.status_code, answer.json()["code"]) == (409, "AGREED")
    deleted = client.post(f"/api/suppliers/entries/{mistake}/delete", json={"reason": "typed twice"}, headers=shop)
    assert deleted.status_code == 200
    _same_balance(client, shop, supplier, ravi, link, 150)
    gone = next(e for e in _supplier_side(client, ravi, link)["entries"] if e["id"] == mistake)
    assert gone["deleteReason"] == "typed twice"  # the supplier still sees it
    assert client.post(f"/api/supply/entries/{mistake}/confirm", headers=ravi).json()["code"] == "ENTRY_DELETED"
    assert "ENTRY_DELETED" in _bell(client, ravi, "SUPPLIER")


def test_paid_on_the_spot_waits_too(client):
    shop, ravi, supplier, link = _connected(client)
    _entry(client, shop, supplier, "PURCHASE", 300, paidNow=True, method="CASH")
    _same_balance(client, shop, supplier, ravi, link, 300)
    payment = next(e for e in _supplier_side(client, ravi, link)["entries"] if e["kind"] == "PAYMENT")
    client.post(f"/api/supply/entries/{payment['id']}/confirm", headers=ravi)
    _same_balance(client, shop, supplier, ravi, link, 0)


# ---------- orders ----------


def _order(client, shop, supplier, *items):
    answer = client.post(f"/api/suppliers/{supplier}/orders", headers=shop, json={
        "lines": [{"itemId": i, "qtyMilli": q} for i, q in items], "note": "by Friday", "clientRef": _ref()})
    assert answer.status_code == 201, answer.text
    return answer.json()


def _answer(order, total, prices):
    """[prices]: paise for each line; None = not available."""
    return {"totalPaise": total, "note": "ok", "lines": [
        {"id": line["id"], "available": p is not None, "costPaise": p} for line, p in zip(order["lines"], prices)]}


def _theirs(client, ravi):
    return client.get("/api/supply/orders", headers=ravi).json()


def test_order_all_the_way(client):
    shop, ravi, supplier, link = _connected(client)
    rice, oil = _item(client, shop, "Rice")["id"], _item(client, shop, "Oil", unit="L")["id"]
    _order(client, shop, supplier, (rice, 25_000), (oil, 5_000))
    order = _theirs(client, ravi)[0]
    assert (order["shopName"], order["status"], order["note"]) == ("Sri Balaji Kirana", "SENT", "by Friday")
    assert [(x["name"], x["qtyMilli"]) for x in order["lines"]] == [("Rice", 25_000), ("Oil", 5_000)]
    url = f"/api/supply/orders/{order['id']}"
    assert client.post(f"{url}/dispatch", headers=ravi).status_code == 409  # accept first
    accepted = client.post(f"{url}/accept", json=_answer(order, 120_000, [4800, None]), headers=ravi)
    assert accepted.status_code == 200, accepted.text
    mine = _shop_side(client, shop, supplier)["orders"][0]
    assert (mine["status"], mine["totalPaise"], mine["shared"]) == ("ACCEPTED", 120_000, True)
    assert [(x["costPaise"], x["available"]) for x in mine["lines"]] == [(4800, True), (None, False)]
    # The price can be corrected until it is sent.
    client.post(f"{url}/accept", json=_answer(order, 118_000, [4720, None]), headers=ravi)
    for _ in range(2):
        assert client.post(f"{url}/dispatch", headers=ravi).json()["status"] == "DISPATCHED"
    assert client.post(f"{url}/accept", json=_answer(order, 1, [1, 1]), headers=ravi).status_code == 409
    assert client.post(f"/api/suppliers/orders/{order['id']}/cancel", headers=shop).json()["code"] == "ON_THE_WAY"
    assert _bell(client, shop, "BUSINESS") == ["ORDER_SENT", "ORDER_ACCEPTED", "CONNECTED"]
    # Received for the supplier's own bill: both agree already.
    client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": 118_000, "lines": [{"itemId": rice, "qtyMilli": 25_000, "costPaise": 4720}], "clientRef": _ref()})
    assert _qty(client, shop, rice) == 25_000
    entry = _supplier_side(client, ravi, link)["entries"][0]
    assert (entry["confirm"], entry["orderId"]) == ("CONFIRMED", order["id"])
    _same_balance(client, shop, supplier, ravi, link, 1180)
    assert _theirs(client, ravi)[0]["status"] == "RECEIVED"
    assert _bell(client, ravi, "SUPPLIER") == ["ORDER_RECEIVED"]


def test_received_for_another_amount_must_be_confirmed(client):
    shop, ravi, supplier, link = _connected(client)
    rice = _item(client, shop, "Rice")["id"]
    _order(client, shop, supplier, (rice, 10_000))
    order = _theirs(client, ravi)[0]
    client.post(f"/api/supply/orders/{order['id']}/accept", json=_answer(order, 48_000, [4800]), headers=ravi)
    client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": 40_000, "lines": [{"itemId": rice, "qtyMilli": 8_000}], "clientRef": _ref()})
    assert _supplier_side(client, ravi, link)["entries"][0]["confirm"] == "WAITING"
    assert "CONFIRM_PURCHASE" in _bell(client, ravi, "SUPPLIER")


def test_rejecting_and_cancelling(client):
    shop, ravi, supplier, link = _connected(client)
    rice = _item(client, shop, "Rice")["id"]
    first, second = (_order(client, shop, supplier, (rice, 1000)) for _ in range(2))
    no = f"/api/supply/orders/{first['id']}/reject"
    assert client.post(no, json={"reason": ""}, headers=ravi).status_code == 400
    for _ in range(2):
        assert client.post(no, json={"reason": "No stock"}, headers=ravi).json()["status"] == "REJECTED"
    closed = client.post(f"/api/suppliers/orders/{first['id']}/receive", headers=shop, json={
        "amountPaise": 100, "lines": [], "clientRef": _ref()})
    assert (closed.status_code, closed.json()["message"]) == (409, "The supplier rejected this order")
    assert client.post(f"/api/suppliers/orders/{second['id']}/cancel", headers=shop).json()["status"] == "CANCELLED"
    late = client.post(f"/api/supply/orders/{second['id']}/accept",
                       json=_answer(_theirs(client, ravi)[0], 100, [1]), headers=ravi)
    assert late.json()["message"] == "The shop cancelled this order"
    assert "ORDER_CANCELLED" in _bell(client, ravi, "SUPPLIER")
    assert "ORDER_REJECTED" in _bell(client, shop, "BUSINESS")
    assert client.get("/api/suppliers", headers=shop).json()["suppliers"][0]["openOrders"] == 0


def test_bad_answers_to_an_order(client):
    shop, ravi, supplier, _ = _connected(client)
    rice, oil = _item(client, shop, "Rice")["id"], _item(client, shop, "Oil", unit="L")["id"]
    _order(client, shop, supplier, (rice, 1000), (oil, 1000))
    order = _theirs(client, ravi)[0]
    good = _answer(order, 100, [1, 1])
    for bad in (
        {**good, "lines": good["lines"][:1]},
        {**good, "lines": [good["lines"][0]] * 2},
        {**good, "lines": [{**good["lines"][0], "id": 999_999}, good["lines"][1]]},
        _answer(order, 100, [None, None]),
        {**good, "totalPaise": 0},
        {**good, "lines": [{**good["lines"][0], "costPaise": -1}, good["lines"][1]]},
    ):
        assert client.post(f"/api/supply/orders/{order['id']}/accept", json=bad, headers=ravi).status_code == 400, bad


def test_orders_from_before_connecting_stay_private(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    rice = _item(client, shop, "Rice")["id"]
    old = _order(client, shop, supplier, (rice, 1000))
    assert old["shared"] is False
    _ask(client, shop, supplier)
    assert _theirs(client, ravi) == []
    assert client.post(f"/api/supply/orders/{old['id']}/reject", json={"reason": "x"}, headers=ravi).status_code == 404


# ---------- disconnecting ----------


def test_disconnecting_hides_nothing(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    _entry(client, shop, supplier, "PURCHASE", 50)
    waiting = _entry(client, shop, supplier, "PAYMENT", 30).json()["id"]
    assert client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop).json()["link"]["status"] == "ENDED"
    # The supplier keeps what was agreed; the payment was never confirmed.
    detail = _supplier_side(client, ravi, link)
    assert detail["shop"]["connected"] is False and detail["shop"]["balancePaise"] == 15000
    assert {e["confirm"] for e in detail["entries"]} == {"CLOSED"}
    # The shop's own book counts its payment.
    assert _shop_side(client, shop, supplier)["supplier"]["balancePaise"] == 12000
    assert client.post(f"/api/supply/entries/{waiting}/confirm", headers=ravi).json()["code"] == "DISCONNECTED"
    # What comes later is not shared.
    _entry(client, shop, supplier, "PURCHASE", 999)
    assert _supplier_side(client, ravi, link)["shop"]["balancePaise"] == 15000
    assert _bell(client, ravi, "SUPPLIER") == ["SHOP_LEFT"]
    # Connecting again starts a new account.
    _ask(client, shop, supplier)
    shops = _home(client, ravi)["shops"]
    assert [s["connected"] for s in shops] == [True, False]
    assert shops[0]["linkId"] != link and shops[0]["openingPaise"] == 111900


def test_the_supplier_can_leave(client):
    shop, ravi, supplier, link = _connected(client)
    rice = _item(client, shop, "Rice")["id"]
    order = _order(client, shop, supplier, (rice, 1000))
    for _ in range(2):
        assert client.post(f"/api/supply/shops/{link}/end", headers=ravi).status_code == 204
    assert _shop_side(client, shop, supplier)["supplier"]["link"]["status"] == "ENDED"
    assert client.post(f"/api/supply/orders/{order['id']}/reject", json={"reason": "x"},
                       headers=ravi).json()["code"] == "DISCONNECTED"
    assert _bell(client, shop, "BUSINESS")[0] == "SUPPLIER_LEFT"
    # The shop can still close its order itself.
    assert client.post(f"/api/suppliers/orders/{order['id']}/cancel", headers=shop).json()["status"] == "CANCELLED"


def test_removing_a_supplier_disconnects(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    changed = client.put(f"/api/suppliers/{supplier}", json={"name": "Ravi Traders", "mobile": OTHER}, headers=shop)
    assert changed.json()["code"] == "CONNECTED"
    assert client.put(f"/api/suppliers/{supplier}", json={"name": "Ravi & Sons", "mobile": RAVI},
                      headers=shop).status_code == 200
    client.post(f"/api/suppliers/{supplier}/archive", headers=shop)
    detail = _supplier_side(client, ravi, link)["shop"]
    assert detail["connected"] is False and detail["balancePaise"] == 10000


# ---------- privacy ----------


def test_private(client):
    shop, ravi, supplier, link = _connected(client)
    rice = _item(client, shop, "Rice")["id"]
    order = _order(client, shop, supplier, (rice, 1000))
    entry = _entry(client, shop, supplier, "PURCHASE", 50).json()["id"]
    stranger, other_shop = _ravi(client, OTHER), _account(client, SHOP_B)
    assert _home(client, stranger) == {"totalDuePaise": 0, "requests": [], "shops": []}
    assert _theirs(client, stranger) == []
    tries = [
        ("get", f"/api/supply/shops/{link}", None),
        ("post", f"/api/supply/shops/{link}/accept", {"balancePaise": 0}),
        ("post", f"/api/supply/shops/{link}/decline", {}),
        ("post", f"/api/supply/shops/{link}/end", None),
        ("post", f"/api/supply/entries/{entry}/confirm", None),
        ("post", f"/api/supply/entries/{entry}/dispute", {"reason": "x"}),
        ("post", f"/api/supply/orders/{order['id']}/accept", {"lines": [], "totalPaise": 5}),
        ("post", f"/api/supply/orders/{order['id']}/reject", {"reason": "x"}),
        ("post", f"/api/supply/orders/{order['id']}/dispatch", None),
    ]
    for who, code in ((stranger, 404), (shop, 403), (None, 401)):
        for method, url, body in tries:
            args = {"headers": who} if who else {}
            if method == "post":
                args["json"] = body or {}
            assert getattr(client, method)(url, **args).status_code == code, (url, code)
    for path, body in (("otp", None), ("verify", {"otp": "123456"}), ("disconnect", None)):
        url = f"/api/suppliers/{supplier}/{path}"
        assert client.post(url, json=body, headers=other_shop).status_code == 404
        assert client.post(url, json=body, headers=ravi).status_code == 403
    assert client.get(f"/api/suppliers/{supplier}/products", headers=other_shop).status_code == 404
    assert client.get("/api/supply/products", headers=shop).status_code == 403
    assert client.get("/api/supply/shops", headers=shop).status_code == 403
    assert _supplier_side(client, ravi, link)["shop"]["connected"] is True


def test_the_shop_private_note_is_not_shared(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    supplier = _supplier(client, shop, "Ravi (slow)", mobile=RAVI, note="never pay early")["id"]
    _ask(client, shop, supplier)
    link = _home(client, ravi)["shops"][0]["linkId"]
    seen = str(_home(client, ravi)) + str(_supplier_side(client, ravi, link))
    assert "never pay early" not in seen and "slow" not in seen


def test_deleting_accounts_cleans_up(client):
    _connected(client, owed=100)
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM users"))
        assert connection.execute(text("SELECT count(*) FROM supply_links")).scalar_one() == 0


# ---------- products ----------

PRODUCTS = "/api/supply/products"


def _product(name="Rice", unit="KG", price=4800, **extra):
    return {"name": name, "unit": unit, "pricePaise": price, "clientRef": _ref(), **extra}


def _sell(client, ravi, *products):
    answer = client.post(PRODUCTS, json={"products": list(products)}, headers=ravi)
    assert answer.status_code == 201, answer.text
    return answer.json()


def _seen(client, shop, supplier):
    answer = client.get(f"/api/suppliers/{supplier}/products", headers=shop)
    assert answer.status_code == 200, answer.text
    return answer.json()


def test_supplier_products(client):
    ravi = _ravi(client)
    body = _product(" Sona  rice ", catalogCode="rice")
    rice, oil = _sell(client, ravi, body, _product("Oil", "L", None, available=False))
    assert (rice["name"], rice["pricePaise"], rice["available"]) == ("Sona rice", 4800, True)
    assert (oil["pricePaise"], oil["available"]) == (None, False)
    assert _sell(client, ravi, body)[0]["id"] == rice["id"]  # a retry
    assert _sell(client, ravi, _product("sona RICE"))[0]["id"] == rice["id"]  # the same name and unit
    assert _sell(client, ravi, _product("Sona rice", "BAG", 120000))[0]["id"] != rice["id"]
    changed = client.put(f"{PRODUCTS}/{rice['id']}", headers=ravi,
                         json={"name": "Sona Masoori", "pricePaise": 5000, "available": False})
    assert (changed.json()["name"], changed.json()["pricePaise"], changed.json()["unit"]) == ("Sona Masoori", 5000, "KG")
    _sell(client, ravi, _product("Dal"))
    clash = client.put(f"{PRODUCTS}/{rice['id']}", headers=ravi, json={"name": "DAL"})
    assert clash.json()["code"] == "PRODUCT_EXISTS"
    assert client.delete(f"{PRODUCTS}/{oil['id']}", headers=ravi).status_code == 204
    assert client.delete(f"{PRODUCTS}/{oil['id']}", headers=ravi).status_code == 404
    assert [p["name"] for p in client.get(PRODUCTS, headers=ravi).json()] == ["Dal", "Sona Masoori", "Sona rice"]


def test_bad_products_are_refused(client, monkeypatch):
    ravi, other = _ravi(client), _ravi(client, OTHER)
    for bad in (_product(" "), _product("x" * 81), _product(unit="TON"), _product(price=-1),
                _product(catalogCode="Bad Code"), _product(clientRef="x")):
        assert client.post(PRODUCTS, json={"products": [bad]}, headers=ravi).status_code == 400, bad
    assert client.post(PRODUCTS, json={"products": []}, headers=ravi).status_code == 400
    mine = _sell(client, ravi, _product())[0]
    assert client.put(f"{PRODUCTS}/{mine['id']}", json={"name": "X"}, headers=other).status_code == 404
    assert client.delete(f"{PRODUCTS}/{mine['id']}", headers=other).status_code == 404
    assert client.get(PRODUCTS, headers=other).json() == []
    assert client.get(PRODUCTS).status_code == 401
    monkeypatch.setattr("app.supply.products.MAX_PRODUCTS", 1)
    full = client.post(PRODUCTS, json={"products": [_product("Dal")]}, headers=ravi)
    assert full.json()["code"] == "TOO_MANY_PRODUCTS"


def test_only_a_connected_shop_sees_them(client):
    shop, ravi = _account(client, SHOP_A), _ravi(client)
    _sell(client, ravi, _product())
    supplier = _supplier(client, shop, mobile=RAVI)["id"]
    url = f"/api/suppliers/{supplier}/products"
    assert client.get(url, headers=shop).json()["code"] == "NOT_CONNECTED"
    _ask(client, shop, supplier)
    assert [(p["name"], p["pricePaise"], p["available"]) for p in _seen(client, shop, supplier)] == [("Rice", 4800, True)]
    client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop)
    assert client.get(url, headers=shop).status_code == 409


def test_matching_the_shops_own_items(client):
    shop, ravi, supplier, _ = _connected(client)
    sold = _sell(client, ravi, _product("Rice", catalogCode="rice"), _product("Sugar", catalogCode="sugar"),
                 _product("Toor dal", catalogCode="toor_dal"), _product("Salt", "BAG"))
    sugar = _item(client, shop, "Sugar fine", catalogCode="sugar", openingMilli=1000, alertMilli=5000)["id"]
    _item(client, shop, "Sona rice", catalogCode="rice")
    _item(client, shop, "Basmati", catalogCode="rice")  # two kinds: neither is guessed
    _item(client, shop, "Salt", unit="PACKET")  # another unit
    dal = _item(client, shop, "Toor dal")["id"]
    order = _order_products(client, shop, supplier, *[(p["id"], 1000) for p in sold]).json()
    assert [(x["name"], x["itemId"]) for x in order["lines"]] == [
        ("Rice", None), ("Sugar", sugar), ("Toor dal", dal), ("Salt", None)]


def test_what_they_have_comes_first(client):
    shop, ravi, supplier, _ = _connected(client)
    _sell(client, ravi, _product("Almond", available=False), _product("Rice"), _product("Dal"))
    seen = _seen(client, shop, supplier)
    assert [p["name"] for p in seen] == ["Dal", "Rice", "Almond"]
    assert set(seen[0]) == {"id", "name", "catalogCode", "unit", "pricePaise", "available"}


def _order_products(client, shop, supplier, *lines):
    return client.post(f"/api/suppliers/{supplier}/orders", headers=shop, json={
        "lines": [{"productId": p, "qtyMilli": q} for p, q in lines], "clientRef": _ref()})


def test_order_from_products_and_new_items_join_the_stock(client):
    shop, ravi, supplier, link = _connected(client)
    rice, oil = _sell(client, ravi, _product("Rice", catalogCode="rice"), _product("Oil", "L", 15000))
    own = _item(client, shop, "Rice")["id"]
    order = _order_products(client, shop, supplier, (rice["id"], 25_000), (oil["id"], 5_000)).json()
    assert [(x["name"], x["itemId"], x["costPaise"]) for x in order["lines"]] == [
        ("Rice", own, 4800), ("Oil", None, 15000)]
    theirs = _theirs(client, ravi)[0]
    assert [x["costPaise"] for x in theirs["lines"]] == [4800, 15000]  # filled in for the supplier
    client.post(f"/api/supply/orders/{order['id']}/accept", json=_answer(theirs, 195_000, [4800, 15000]), headers=ravi)
    url = f"/api/suppliers/orders/{order['id']}/receive"
    body = {"amountPaise": 195_000, "clientRef": _ref(), "lines": [
        {"orderLineId": order["lines"][0]["id"], "qtyMilli": 25_000, "costPaise": 4800},
        {"orderLineId": order["lines"][1]["id"], "qtyMilli": 5_000, "costPaise": 15000}]}
    for _ in range(2):  # a retry adds nothing twice
        assert client.post(url, json=body, headers=shop).json()["status"] == "RECEIVED"
    assert _qty(client, shop, own) == 25_000
    stock = {i["name"]: i for i in client.get("/api/stock/items", headers=shop).json()["items"]}
    assert set(stock) == {"Rice", "Oil"}
    assert (stock["Oil"]["unit"], stock["Oil"]["quantityMilli"], stock["Oil"]["costPaise"]) == ("L", 5_000, 15000)
    _same_balance(client, shop, supplier, ravi, link, 1950)


def test_the_same_name_in_another_unit_is_a_new_item(client):
    shop, ravi, supplier, _ = _connected(client)
    salt = _sell(client, ravi, _product("Salt", "BAG"))[0]
    own = _item(client, shop, "Salt", unit="PACKET")["id"]
    for _ in range(2):  # the second time it is found again
        order = _order_products(client, shop, supplier, (salt["id"], 2_000)).json()
        done = client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
            "amountPaise": 100, "clientRef": _ref(),
            "lines": [{"orderLineId": order["lines"][0]["id"], "qtyMilli": 2_000}]})
        assert done.status_code == 200, done.text
    stock = {i["name"]: i["quantityMilli"] for i in client.get("/api/stock/items", headers=shop).json()["items"]}
    assert stock == {"Salt": 0, "Salt (bag)": 4_000}
    assert _qty(client, shop, own) == 0


def test_products_that_cannot_be_ordered(client):
    shop, ravi, supplier, _ = _connected(client)
    rice, oil = _sell(client, ravi, _product("Rice"), _product("Oil", "L", available=False))
    theirs = _sell(client, _ravi(client, OTHER), _product("Dal"))[0]
    assert _order_products(client, shop, supplier, (oil["id"], 1000)).json()["code"] == "NOT_AVAILABLE"
    assert _order_products(client, shop, supplier, (theirs["id"], 1000)).json()["code"] == "PRODUCT_NOT_FOUND"
    assert _order_products(client, shop, supplier, (rice["id"], 1000), (rice["id"], 1000)).status_code == 400
    url = f"/api/suppliers/{supplier}/orders"
    for line in ({"qtyMilli": 1000}, {"itemId": 1, "productId": rice["id"], "qtyMilli": 1000}):
        assert client.post(url, headers=shop, json={"lines": [line], "clientRef": _ref()}).status_code == 400
    client.delete(f"{PRODUCTS}/{rice['id']}", headers=ravi)
    assert _order_products(client, shop, supplier, (rice["id"], 1000)).json()["code"] == "PRODUCT_NOT_FOUND"
    assert _shop_side(client, shop, supplier)["orders"] == []
    # Not connected: products cannot be ordered at all.
    client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop)
    assert _order_products(client, shop, supplier, (rice["id"], 1000)).status_code == 404


def test_receiving_only_lines_of_that_order(client):
    shop, ravi, supplier, _ = _connected(client)
    rice = _sell(client, ravi, _product("Rice"))[0]
    first, second = (_order_products(client, shop, supplier, (rice["id"], 1000)).json() for _ in range(2))
    url = f"/api/suppliers/orders/{first['id']}/receive"
    line = {"orderLineId": first["lines"][0]["id"], "qtyMilli": 1000}
    for lines in ([{**line, "orderLineId": second["lines"][0]["id"]}], [line, line], [{"qtyMilli": 1000}]):
        answer = client.post(url, headers=shop, json={"amountPaise": 100, "lines": lines, "clientRef": _ref()})
        assert answer.status_code == 400, lines
    assert client.get("/api/stock/items", headers=shop).json()["items"] == []


# ---------- typed items (the shop's stock list is never needed) ----------


def _stock(client, shop):
    return {i["name"]: (i["unit"], i["quantityMilli"]) for i in client.get("/api/stock/items", headers=shop).json()["items"]}


def _named(name, qty, unit="KG", **extra):
    return {"name": name, "unit": unit, "qtyMilli": qty, **extra}


def test_goods_bought_by_name(client):
    shop = _account(client, SHOP_A)
    supplier = _supplier(client, shop)["id"]
    rice = _item(client, shop, "Rice", openingMilli=1000)["id"]
    _item(client, shop, "Sona sugar", catalogCode="sugar")
    ref = _ref()
    lines = [_named("  rice ", 5000, costPaise=4800), _named("Sugar", 2000, catalogCode="sugar"),
             _named("Soap", 12_000, "PIECE")]
    for _ in range(2):  # a retry adds nothing twice
        assert _entry(client, shop, supplier, "PURCHASE", 500, ref=ref, lines=lines).status_code == 201
    assert _stock(client, shop) == {"Rice": ("KG", 6000), "Sona sugar": ("KG", 2000), "Soap": ("PIECE", 12_000)}
    assert client.get(f"/api/stock/items/{rice}", headers=shop).json()["item"]["costPaise"] == 4800
    entry = _shop_side(client, shop, supplier)["entries"][0]["id"]
    client.post(f"/api/suppliers/entries/{entry}/delete", json={"reason": "x"}, headers=shop)
    assert _stock(client, shop)["Soap"] == ("PIECE", 0) and _qty(client, shop, rice) == 1000


def test_bad_typed_items(client):
    shop = _account(client, SHOP_A)
    supplier = _supplier(client, shop)["id"]
    item = _item(client, shop, "Rice")["id"]
    for lines in ([_named(" ", 1000)], [_named("x" * 81, 1000)], [{"name": "Dal", "qtyMilli": 1000}],
                  [{"unit": "KG", "qtyMilli": 1000}], [_named("Dal", 0)], [_named("Dal", 1000, "TON")],
                  [_named("Dal", 1000, itemId=item)], [_named("Dal", 1000), _named("DAL", 1000)],
                  [_named("rice", 1000), {"itemId": item, "qtyMilli": 1000}],
                  [_named("Dal", 1000, catalogCode="Not OK")]):
        assert _entry(client, shop, supplier, "PURCHASE", 5, lines=lines).status_code == 400, lines
    assert _stock(client, shop) == {"Rice": ("KG", 0)}
    assert _shop_side(client, shop, supplier)["entries"] == []


def test_an_order_by_name_then_received_with_something_extra(client):
    shop, ravi, supplier, link = _connected(client)
    order = client.post(f"/api/suppliers/{supplier}/orders", headers=shop, json={
        "lines": [_named("Rice", 10_000, catalogCode="rice"), _named("Biscuits", 5000, "BOX")], "clientRef": _ref()})
    assert order.status_code == 201, order.text
    order = order.json()
    theirs = _theirs(client, ravi)[0]
    assert [(x["name"], x["unit"], x["costPaise"]) for x in theirs["lines"]] == [("Rice", "KG", None), ("Biscuits", "BOX", None)]
    _item(client, shop, "Sona rice", catalogCode="rice")  # added meanwhile
    done = client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": 90_000, "clientRef": _ref(), "lines": [
            {"orderLineId": order["lines"][0]["id"], "qtyMilli": 10_000},
            {"orderLineId": order["lines"][1]["id"], "qtyMilli": 4000}, _named("Salt", 1000, "BAG")]})
    assert done.status_code == 200, done.text
    assert _stock(client, shop) == {"Sona rice": ("KG", 10_000), "Biscuits": ("BOX", 4000), "Salt": ("BAG", 1000)}


# ---------- paying ----------


def _upi(client, ravi, upi="ravi@okaxis", name="Ravi Traders"):
    return client.put("/api/supply/upi", json={"upiId": upi, "upiName": name}, headers=ravi)


def _placed(client, shop, ravi, supplier, **extra):
    """An order of one product, accepted by the supplier for Rs 480."""
    rice = _sell(client, ravi, _product("Rice"))[0]
    answer = client.post(f"/api/suppliers/{supplier}/orders", headers=shop, json={
        "lines": [{"productId": rice["id"], "qtyMilli": 10_000}], "clientRef": _ref(), **extra})
    if answer.status_code != 201:
        return answer.json()
    order = answer.json()
    client.post(f"/api/supply/orders/{order['id']}/accept", json=_answer(order, 48_000, [4800]), headers=ravi)
    return order


def _receive(client, shop, order, amount=48_000, **extra):
    return client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": amount, "clientRef": _ref(),
        "lines": [{"orderLineId": order["lines"][0]["id"], "qtyMilli": 10_000, "costPaise": 4800}], **extra})


def _paid(client, shop, supplier):
    order = _shop_side(client, shop, supplier)["orders"][0]
    return order["paidPaise"], order["payingPaise"]


def test_the_suppliers_upi_id(client):
    shop, ravi, supplier, link = _connected(client)
    url = f"/api/suppliers/{supplier}/pay"
    assert client.get(url, headers=shop).json()["upiId"] is None
    assert _shop_side(client, shop, supplier)["supplier"]["takesUpi"] is False
    for bad in ("ravi", "a@b", "ravi@ok axis", "x" * 61 + "@ok"):
        assert _upi(client, ravi, bad).status_code == 400, bad
    assert _upi(client, ravi).json()["upiId"] == "ravi@okaxis"
    assert client.get(url, headers=shop).json() == {"name": "Ravi Traders", "upiId": "ravi@okaxis"}
    assert _shop_side(client, shop, supplier)["supplier"]["takesUpi"] is True
    assert client.get("/api/suppliers", headers=shop).json()["suppliers"][0]["takesUpi"] is True
    # Only for shops connected with them.
    assert client.get(url, headers=_account(client, SHOP_B)).status_code == 404
    assert client.get(url, headers=ravi).status_code == 403
    assert client.get(url).status_code == 401
    assert _upi(client, shop).status_code == 403
    assert client.get("/api/supply/payments", headers=shop).status_code == 403
    assert _upi(client, ravi, "").json()["upiId"] is None
    _upi(client, ravi)
    client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop)
    assert client.get(url, headers=shop).json()["code"] == "NOT_CONNECTED"
    assert _shop_side(client, shop, supplier)["supplier"]["takesUpi"] is False


def test_pay_later_with_a_date(client):
    shop, ravi, supplier, link = _connected(client)
    _placed(client, shop, ravi, supplier, payPlan="LATER", payBy="2026-12-05")
    theirs = _theirs(client, ravi)[0]
    assert (theirs["payPlan"], theirs["payBy"], theirs["paidPaise"]) == ("LATER", "2026-12-05", 0)
    assert _shop_side(client, shop, supplier)["orders"][0]["payPlan"] == "LATER"
    for bad in ({"payPlan": "CASH", "payBy": "2026-12-05"}, {"payBy": "2026-12-05"}, {"payPlan": "CARD"}):
        assert _placed(client, shop, ravi, supplier, **bad).get("code") == "INVALID_INPUT", bad


def test_cash_on_delivery(client):
    shop, ravi, supplier, link = _connected(client)
    order = _placed(client, shop, ravi, supplier, payPlan="CASH")
    assert _receive(client, shop, order, paidNow=True, method="CASH").status_code == 200
    assert _paid(client, shop, supplier) == (0, 48_000)
    _same_balance(client, shop, supplier, ravi, link, 480)  # until the supplier says it came
    payment = client.get("/api/supply/payments", headers=ravi).json()["payments"][0]
    assert (payment["shopName"], payment["orderId"], payment["method"]) == ("Sri Balaji Kirana", order["id"], "CASH")
    client.post(f"/api/supply/entries/{payment['id']}/confirm", headers=ravi)
    assert _paid(client, shop, supplier) == (48_000, 0)
    _same_balance(client, shop, supplier, ravi, link, 0)


def test_pay_by_upi_after_they_accept(client):
    shop, ravi, supplier, link = _connected(client)
    assert _placed(client, shop, ravi, supplier, payPlan="UPI")["code"] == "NO_UPI"
    _upi(client, ravi)
    order = _placed(client, shop, ravi, supplier, payPlan="UPI")
    ref = _ref()
    for _ in range(2):  # the phone was offline and sends it again
        assert _entry(client, shop, supplier, "PAYMENT", 480, ref=ref, method="UPI", orderId=order["id"]).status_code == 201
    assert _paid(client, shop, supplier) == (0, 48_000)
    assert "CONFIRM_PAYMENT" in _bell(client, ravi, "SUPPLIER")
    assert (_theirs(client, ravi)[0]["paidPaise"], _theirs(client, ravi)[0]["payingPaise"]) == (0, 48_000)
    # Paid already: not a second time when the goods come.
    assert _receive(client, shop, order, paidNow=True).json()["code"] == "ALREADY_PAID"
    payment = client.get("/api/supply/payments", headers=ravi).json()["payments"][0]
    client.post(f"/api/supply/entries/{payment['id']}/confirm", headers=ravi)
    _same_balance(client, shop, supplier, ravi, link, -480)  # paid before the goods
    assert _receive(client, shop, order, paidNow=True).json()["code"] == "ALREADY_PAID"
    assert _receive(client, shop, order).status_code == 200
    _same_balance(client, shop, supplier, ravi, link, 0)
    assert _theirs(client, ravi)[0]["paidPaise"] == 48_000


def test_a_payment_that_never_came_for_an_order(client):
    shop, ravi, supplier, link = _connected(client)
    order = _placed(client, shop, ravi, supplier, payPlan="LATER")
    payment = _entry(client, shop, supplier, "PAYMENT", 480, method="UPI", orderId=order["id"]).json()["id"]
    client.post(f"/api/supply/entries/{payment}/dispute", json={"reason": "Not in my bank"}, headers=ravi)
    assert _paid(client, shop, supplier) == (0, 0)
    assert _receive(client, shop, order, paidNow=True, method="CASH").status_code == 200


def test_money_sent_is_written_even_if_they_reject(client):
    shop, ravi, supplier, link = _connected(client)
    order = _placed(client, shop, ravi, supplier, payPlan="LATER")
    client.post(f"/api/supply/orders/{order['id']}/reject", json={"reason": "No stock"}, headers=ravi)
    assert _entry(client, shop, supplier, "PAYMENT", 480, method="UPI", orderId=order["id"]).status_code == 201


def test_a_payment_only_for_this_suppliers_order(client):
    shop, ravi, supplier, link = _connected(client)
    order = _placed(client, shop, ravi, supplier, payPlan="LATER")
    other = _supplier(client, shop, "Other")["id"]
    assert _entry(client, shop, other, "PAYMENT", 5, orderId=order["id"]).status_code == 404
    assert _entry(client, shop, supplier, "PAYMENT", 5, orderId=999_999).status_code == 404
    assert _entry(client, shop, supplier, "PURCHASE", 5, orderId=order["id"]).status_code == 400


def test_the_suppliers_payments(client):
    shop, ravi, supplier, link = _connected(client, owed=1000)
    today = datetime.now(INDIA).isoformat()
    first = _entry(client, shop, supplier, "PAYMENT", 300, at=today).json()["id"]
    gone = _entry(client, shop, supplier, "PAYMENT", 50, at=today).json()["id"]
    _entry(client, shop, supplier, "PAYMENT", 200, at=today)
    client.post(f"/api/suppliers/entries/{gone}/delete", json={"reason": "x"}, headers=shop)
    client.post(f"/api/supply/entries/{first}/confirm", headers=ravi)
    seen = client.get("/api/supply/payments", headers=ravi).json()
    assert (seen["toGetPaise"], seen["receivedMonthPaise"]) == (70_000, 30_000)
    assert sorted((p["amountPaise"], p["confirm"], p["connected"]) for p in seen["payments"]) == [
        (20_000, "WAITING", True), (30_000, "CONFIRMED", True)]
    empty = client.get("/api/supply/payments", headers=_ravi(client, OTHER)).json()
    assert empty == {"upiId": None, "upiName": None, "toGetPaise": 0, "receivedMonthPaise": 0, "payments": []}


# ---------- the supplier's own stock count ----------


def _move(client, ravi, product, kind, qty, ref=None, **extra):
    return client.post(f"{PRODUCTS}/{product['id']}/moves", headers=ravi, json={
        "kind": kind, "qtyMilli": qty, "clientRef": ref or _ref(), **extra})


def _left(client, ravi, product):
    return client.get(f"{PRODUCTS}/{product['id']}/stock", headers=ravi).json()["product"]["quantityMilli"]


def test_counting_stock(client):
    ravi = _ravi(client)
    rice = _sell(client, ravi, _product("Rice"))[0]
    assert (rice["counted"], rice["quantityMilli"], rice["low"]) == (False, 0, False)
    ref = _ref()
    for _ in range(2):  # a retry
        seen = _move(client, ravi, rice, "COUNT", 50_000, ref=ref)
        assert seen.status_code == 201, seen.text
    assert (seen.json()["product"]["counted"], seen.json()["product"]["quantityMilli"]) == (True, 50_000)
    _move(client, ravi, rice, "IN", 25_000, note="From the mill")
    _move(client, ravi, rice, "OUT", 5_000)
    assert _move(client, ravi, rice, "COUNT", 68_500).json()["product"]["quantityMilli"] == 68_500
    assert _move(client, ravi, rice, "COUNT", 68_500).status_code == 201  # nothing to correct
    moves = client.get(f"{PRODUCTS}/{rice['id']}/stock", headers=ravi).json()["moves"]
    assert [(m["kind"], m["qtyMilli"], m["note"]) for m in moves] == [
        ("ADJUST", -1_500, "Counted"), ("OUT", 5_000, None), ("IN", 25_000, "From the mill"),
        ("ADJUST", 50_000, "First count")]
    url = f"{PRODUCTS}/{rice['id']}/stock"
    low = client.put(url, json={"counted": True, "alertMilli": 70_000}, headers=ravi).json()["product"]
    assert (low["low"], low["alertMilli"]) == (True, 70_000)
    assert "PRODUCT_LOW" in _bell(client, ravi, "SUPPLIER")
    off = client.put("/api/notices/off", json={"role": "SUPPLIER", "off": ["STOCK"]}, headers=ravi)
    assert off.status_code == 200, off.text
    assert "PRODUCT_LOW" not in _bell(client, ravi, "SUPPLIER")
    assert client.put(url, json={"counted": False}, headers=ravi).json()["product"]["low"] is False
    # Changing the price does not touch the count.
    client.put(f"{PRODUCTS}/{rice['id']}", json={"name": "Rice", "pricePaise": 1}, headers=ravi)
    assert _left(client, ravi, rice) == 68_500


def test_bad_counts_and_privacy(client):
    ravi, other, shop = _ravi(client), _ravi(client, OTHER), _account(client, SHOP_A)
    rice = _sell(client, ravi, _product("Rice"))[0]
    for kind, qty in (("IN", 0), ("OUT", 0), ("COUNT", -1), ("ADJUST", 5), ("IN", 10**10)):
        assert _move(client, ravi, rice, kind, qty).status_code == 400, (kind, qty)
    assert _move(client, ravi, rice, "IN", 5, ref="x").status_code == 400
    url = f"{PRODUCTS}/{rice['id']}/stock"
    assert client.put(url, json={"counted": True, "alertMilli": -1}, headers=ravi).status_code == 400
    for who, code in ((other, 404), (shop, 403), ({}, 401)):
        assert client.get(url, headers=who).status_code == code
        assert client.put(url, json={"counted": True}, headers=who).status_code == code
        assert _move(client, who, rice, "IN", 5).status_code == code
        if code != 404:
            assert client.get("/api/supply/report?start=2026-11-01&end=2026-11-30", headers=who).status_code == code


def test_shops_see_only_available_or_not(client):
    shop, ravi, supplier, _ = _connected(client)
    rice, dal = _sell(client, ravi, _product("Rice"), _product("Dal"))
    _move(client, ravi, rice, "COUNT", 0)
    _move(client, ravi, dal, "COUNT", 77_000)
    seen = _seen(client, shop, supplier)
    assert [(p["name"], p["available"]) for p in seen] == [("Dal", True), ("Rice", False)]
    assert "77000" not in str(seen)
    assert _order_products(client, shop, supplier, (rice["id"], 1000)).json()["code"] == "NOT_AVAILABLE"
    _move(client, ravi, rice, "IN", 1000)
    assert _order_products(client, shop, supplier, (rice["id"], 1000)).status_code == 201


def test_goods_sent_leave_the_count_once(client):
    shop, ravi, supplier, _ = _connected(client)
    rice, dal, oil = _sell(client, ravi, _product("Rice"), _product("Dal"), _product("Oil", "L"))
    _move(client, ravi, rice, "COUNT", 50_000)
    _move(client, ravi, dal, "COUNT", 9_000)
    order = client.post(f"/api/suppliers/{supplier}/orders", headers=shop, json={"clientRef": _ref(), "lines": [
        {"productId": rice["id"], "qtyMilli": 20_000}, _named("dal", 2_000), {"productId": oil["id"], "qtyMilli": 1_000}]}).json()
    theirs = _theirs(client, ravi)[0]
    assert [x["haveMilli"] for x in theirs["lines"]] == [50_000, 9_000, None]  # shown while answering
    url = f"/api/supply/orders/{order['id']}"
    client.post(f"{url}/accept", json=_answer(theirs, 100_000, [4800, None, 15000]), headers=ravi)
    assert _left(client, ravi, rice) == 50_000  # promised, not gone yet
    for _ in range(2):
        client.post(f"{url}/dispatch", headers=ravi)
    assert (_left(client, ravi, rice), _left(client, ravi, dal), _left(client, ravi, oil)) == (30_000, 9_000, 0)
    assert _theirs(client, ravi)[0]["lines"][0]["haveMilli"] is None
    _receive(client, shop, order, 100_000)
    assert _left(client, ravi, rice) == 30_000
    moves = client.get(f"{PRODUCTS}/{rice['id']}/stock", headers=ravi).json()["moves"]
    assert moves[0]["note"] == "To Sri Balaji Kirana"


def test_received_without_being_marked_sent(client):
    shop, ravi, supplier, _ = _connected(client)
    rice = _sell(client, ravi, _product("Rice"))[0]
    _move(client, ravi, rice, "COUNT", 50_000)
    order = _order_products(client, shop, supplier, (rice["id"], 10_000)).json()
    for _ in range(2):
        assert _receive(client, shop, order).status_code == 200
    assert _left(client, ravi, rice) == 40_000


def test_goods_given_without_an_order_leave_when_confirmed(client):
    shop, ravi, supplier, link = _connected(client)
    rice = _sell(client, ravi, _product("Rice"))[0]
    _move(client, ravi, rice, "COUNT", 50_000)
    entry = _entry(client, shop, supplier, "PURCHASE", 480, lines=[_named("rice", 10_000)]).json()["id"]
    assert _left(client, ravi, rice) == 50_000
    for _ in range(2):
        client.post(f"/api/supply/entries/{entry}/confirm", headers=ravi)
    assert _left(client, ravi, rice) == 40_000


# ---------- reports ----------


def _report(client, ravi, start="2026-11-01", end="2026-11-30"):
    answer = client.get(f"/api/supply/report?start={start}&end={end}", headers=ravi)
    assert answer.status_code == 200, answer.text
    return answer.json()


def test_report(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    other = _account(client, SHOP_B)
    second = _supplier(client, other, mobile=RAVI)["id"]
    _ask(client, other, second)
    _entry(client, shop, supplier, "PURCHASE", 500, lines=[_named("Rice", 10_000, costPaise=4800), _named("Salt", 1000)])
    _entry(client, shop, supplier, "PURCHASE", 50, lines=[_named("rice", 1_500, costPaise=5000)])
    _entry(client, other, second, "PURCHASE", 900)
    _entry(client, shop, supplier, "PURCHASE", 7777, at="2026-10-31T23:59:00+05:30")  # another month
    paid = _entry(client, shop, supplier, "PAYMENT", 200).json()["id"]
    _entry(client, shop, supplier, "PAYMENT", 70)
    gone = _entry(client, shop, supplier, "PURCHASE", 5000).json()["id"]
    client.post(f"/api/suppliers/entries/{gone}/delete", json={"reason": "x"}, headers=shop)
    client.post(f"/api/supply/entries/{paid}/confirm", headers=ravi)
    seen = _report(client, ravi)
    assert (seen["givenPaise"], seen["receivedPaise"], seen["waitingPaise"]) == (145_000, 20_000, 7_000)
    assert seen["toGetPaise"] == _home(client, ravi)["totalDuePaise"]
    assert [(s["givenPaise"], s["receivedPaise"], s["toGetPaise"]) for s in seen["shops"]] == [
        (90_000, 0, 90_000), (55_000, 20_000, 822_700)]
    assert [(p["name"], p["unit"], p["qtyMilli"], p["amountPaise"]) for p in seen["products"]] == [
        ("Rice", "KG", 11_500, 55_500), ("Salt", "KG", 1_000, None)]
    assert _report(client, ravi, "2026-10-01", "2026-10-31")["givenPaise"] == 777_700
    for bad in ("start=2026-11-30&end=2026-11-01", "start=2020-01-01&end=2026-01-01", "start=x&end=y", ""):
        assert client.get(f"/api/supply/report?{bad}", headers=ravi).status_code == 400, bad
    empty = _report(client, _ravi(client, OTHER))
    assert empty == {"givenPaise": 0, "receivedPaise": 0, "waitingPaise": 0, "toGetPaise": 0, "orders": {}, "shops": [],
                     "products": []}


def test_report_orders(client):
    shop, ravi, supplier, _ = _connected(client)
    rice = _sell(client, ravi, _product("Rice"))[0]
    for _ in range(2):
        _order_products(client, shop, supplier, (rice["id"], 1000))
    order = _theirs(client, ravi)[0]
    client.post(f"/api/supply/orders/{order['id']}/reject", json={"reason": "x"}, headers=ravi)
    today = datetime.now(INDIA).date().isoformat()
    assert _report(client, ravi, today, today)["orders"] == {"SENT": 1, "REJECTED": 1}


def test_connecting_again_counts_a_balance_once(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop)
    assert _home(client, ravi)["totalDuePaise"] == 10_000
    _ask(client, shop, supplier)
    assert len(_home(client, ravi)["shops"]) == 2
    assert _home(client, ravi)["totalDuePaise"] == 10_000
    assert [s["toGetPaise"] for s in _report(client, ravi)["shops"]] == [10_000]


# ---------- the supplier writes too ----------


def _write(client, ravi, link, kind, rupees, ref=None, **extra):
    return client.post(f"/api/supply/shops/{link}/entries", headers=ravi, json={
        "kind": kind, "amountPaise": rupees * 100, "entryAt": AT, "clientRef": ref or _ref(), **extra})


def _shop_answers(client, shop, entry, what, reason=None):
    return client.post(f"/api/suppliers/entries/{entry}/{what}", headers=shop, json={"reason": reason} if reason else None)


def test_goods_the_supplier_writes_wait_for_the_shop(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    rice = _sell(client, ravi, _product("Rice"))[0]
    _move(client, ravi, rice, "COUNT", 50_000)
    _item(client, shop, "Sona rice", catalogCode="rice")
    ref = _ref()
    lines = [_named("Rice", 10_000, catalogCode="rice", costPaise=4800), _named("Soap", 5000, "PIECE")]
    for _ in range(2):  # a retry
        wrote = _write(client, ravi, link, "PURCHASE", 480, ref=ref, note="Bill 9", lines=lines)
        assert wrote.status_code == 201, wrote.text
    entry = wrote.json()
    assert (entry["bySupplier"], entry["confirm"]) == (True, "WAITING")
    _same_balance(client, shop, supplier, ravi, link, 100)  # not counted
    assert _left(client, ravi, rice) == 40_000  # but the goods left the supplier
    assert _shop_side(client, shop, supplier)["supplier"]["toConfirm"] == 1
    assert _supplier_side(client, ravi, link)["shop"]["toConfirm"] == 0
    assert "THEY_GAVE" in _bell(client, shop, "BUSINESS")
    assert _stock(client, shop) == {"Sona rice": ("KG", 0)}
    assert _report(client, ravi)["givenPaise"] == 0 and _report(client, ravi)["products"] == []
    # The supplier cannot answer their own entry; the shop cannot delete it.
    assert client.post(f"/api/supply/entries/{entry['id']}/confirm", headers=ravi).json()["code"] == "NOT_YOURS"
    assert _shop_answers(client, shop, entry["id"], "delete", "x").json()["code"] == "NOT_YOURS"
    for _ in range(2):
        assert _shop_answers(client, shop, entry["id"], "confirm").json()["confirm"] == "CONFIRMED"
    _same_balance(client, shop, supplier, ravi, link, 580)
    assert _stock(client, shop) == {"Sona rice": ("KG", 10_000), "Soap": ("PIECE", 5_000)}
    assert _bell(client, ravi, "SUPPLIER").count("SHOP_AGREED") == 1
    assert "THEY_GAVE" not in _bell(client, shop, "BUSINESS") and "NOT_RIGHT" not in _bell(client, shop, "BUSINESS")
    assert _report(client, ravi)["givenPaise"] == 48_000
    gone = client.post(f"/api/supply/entries/{entry['id']}/delete", json={"reason": "x"}, headers=ravi)
    assert (gone.status_code, gone.json()["code"]) == (409, "AGREED")
    assert _shop_answers(client, shop, entry["id"], "dispute", "x").json()["code"] == "ALREADY_CONFIRMED"


def test_money_the_supplier_says_they_got_counts_at_once(client):
    shop, ravi, supplier, link = _connected(client, owed=1000)
    entry = _write(client, ravi, link, "PAYMENT", 400, method="CASH").json()
    assert entry["method"] == "CASH"
    _same_balance(client, shop, supplier, ravi, link, 600)
    assert "THEY_GOT" in _bell(client, shop, "BUSINESS")
    assert _shop_answers(client, shop, entry["id"], "confirm").status_code == 200
    _same_balance(client, shop, supplier, ravi, link, 600)
    assert _report(client, ravi)["receivedPaise"] == 40_000
    # A mistake, deleted before the shop answered.
    wrong = _write(client, ravi, link, "PAYMENT", 50).json()["id"]
    for _ in range(2):
        done = client.post(f"/api/supply/entries/{wrong}/delete", json={"reason": "other shop"}, headers=ravi)
        assert done.json()["deleteReason"] == "other shop"
    _same_balance(client, shop, supplier, ravi, link, 600)
    assert "THEY_DELETED" in _bell(client, shop, "BUSINESS")
    assert "ENTRY_DELETED" not in _bell(client, ravi, "SUPPLIER")
    assert _shop_answers(client, shop, wrong, "confirm").json()["code"] == "ENTRY_DELETED"


def test_goods_that_were_not_right(client):
    shop, ravi, supplier, link = _connected(client)
    rice = _sell(client, ravi, _product("Rice"))[0]
    _move(client, ravi, rice, "COUNT", 50_000)
    entry = _write(client, ravi, link, "PURCHASE", 480, lines=[_named("Rice", 10_000)]).json()["id"]
    assert client.post(f"/api/suppliers/entries/{entry}/dispute", json={"reason": " "}, headers=shop).status_code == 400
    said = _shop_answers(client, shop, entry, "dispute", "Never came").json()
    assert (said["confirm"], said["disputeReason"]) == ("DISPUTED", "Never came")
    _same_balance(client, shop, supplier, ravi, link, 0)
    assert "SHOP_NOT_RIGHT" in _bell(client, ravi, "SUPPLIER")
    for _ in range(2):
        client.post(f"/api/supply/entries/{entry}/delete", json={"reason": "wrong shop"}, headers=ravi)
    assert _left(client, ravi, rice) == 50_000  # back, once
    assert _stock(client, shop) == {}
    # Found after all: written again.
    again = _write(client, ravi, link, "PURCHASE", 480, lines=[_named("Rice", 10_000)]).json()["id"]
    _shop_answers(client, shop, again, "dispute", "Checking")
    assert _shop_answers(client, shop, again, "confirm").json()["confirm"] == "CONFIRMED"
    _same_balance(client, shop, supplier, ravi, link, 480)


def test_disconnecting_with_the_suppliers_entries_open(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    goods = _write(client, ravi, link, "PURCHASE", 500).json()["id"]
    _write(client, ravi, link, "PAYMENT", 30)
    client.post(f"/api/suppliers/{supplier}/disconnect", headers=shop)
    _same_balance(client, shop, supplier, ravi, link, 70)  # goods never agreed; the money was
    assert _shop_answers(client, shop, goods, "confirm").json()["code"] == "DISCONNECTED"
    assert client.post(f"/api/supply/entries/{goods}/delete", json={"reason": "x"}, headers=ravi).json()["code"] == "DISCONNECTED"
    assert _write(client, ravi, link, "PURCHASE", 5).json()["code"] == "DISCONNECTED"


def test_bad_entries_from_a_supplier_and_privacy(client):
    shop, ravi, supplier, link = _connected(client)
    for bad in ({"kind": "PAYMENT", "lines": [_named("Rice", 1000)]}, {"amountPaise": 0}, {"clientRef": "x"},
                {"entryAt": "2099-01-01T00:00:00Z"}, {"lines": [_named("Rice", 1000), _named("RICE", 1000)]},
                {"lines": [_named(" ", 1000)]}, {"lines": [_named("Rice", 0)]}, {"lines": [{"itemId": 1, "qtyMilli": 5}]}):
        body = {"kind": "PURCHASE", "amountPaise": 500, "entryAt": AT, "clientRef": _ref(), **bad}
        assert client.post(f"/api/supply/shops/{link}/entries", headers=ravi, json=body).status_code == 400, bad
    entry = _write(client, ravi, link, "PURCHASE", 5).json()["id"]
    theirs = _entry(client, shop, supplier, "PURCHASE", 7).json()["id"]
    for who, code in ((_ravi(client, OTHER), 404), (shop, 403), ({}, 401)):
        assert _write(client, who, link, "PURCHASE", 5).status_code == code
        assert client.post(f"/api/supply/entries/{entry}/delete", json={"reason": "x"}, headers=who).status_code == code
    for who, code in ((_account(client, SHOP_B), 404), (ravi, 403), ({}, 401)):
        assert _shop_answers(client, who, entry, "confirm").status_code == code
        assert _shop_answers(client, who, entry, "dispute", "x").status_code == code
    # Each side answers only what the other wrote.
    assert _shop_answers(client, shop, theirs, "confirm").status_code == 404
    assert client.post(f"/api/supply/entries/{theirs}/delete", json={"reason": "x"}, headers=ravi).json()["code"] == "NOT_YOURS"
