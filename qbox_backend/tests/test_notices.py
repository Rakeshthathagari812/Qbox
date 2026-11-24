"""The bell: what each side is told, reading, switching off, privacy."""

from datetime import datetime, timedelta

import pytest
from sqlalchemy import text

from app import ratelimit
from app.database import engine
from app.udhaar.schemas import INDIA
from tests.test_calendar import _account
from tests.test_customer import _pay_online
from tests.test_expenses import _add
from tests.test_pay_shop import UPI, _claimed, _pay
from tests.test_payments import test_account, world  # noqa: F401
from tests.test_stock import _item, _move
from tests.test_suppliers import _entry as _supplier_entry
from tests.test_suppliers import _supplier
from tests.test_udhaar import RAMESH, SHOP_A, SHOP_B, _add_customer, _entry, _post_entry

OTHER = "9000000001"


@pytest.fixture(autouse=True)
def _no_old_counts():
    ratelimit.forget()


def _bell(client, who, role="CUSTOMER"):
    answer = client.get(f"/api/notices?role={role}", headers=who)
    assert answer.status_code == 200, answer.text
    return answer.json()


def _kinds(client, who, role="CUSTOMER"):
    return [n["kind"] for n in _bell(client, who, role)["notices"]]


def _unread(client, who, role="CUSTOMER"):
    return client.get(f"/api/notices/unread?role={role}", headers=who).json()["unread"]


def _people(client):
    shop = _account(client, SHOP_A)
    book = _add_customer(client, shop)
    return shop, book, _account(client, RAMESH, roles=("CUSTOMER",))


def test_customer_is_told_what_the_shop_wrote(client):
    shop, book, ramesh = _people(client)
    credit = _post_entry(client, shop, book["id"], _entry("CREDIT", 250, "rice")).json()
    _post_entry(client, shop, book["id"], _entry("PAYMENT", 100))
    client.post(f"/api/udhaar/entries/{credit['id']}/delete", json={"reason": "by mistake"}, headers=shop)
    bell = _bell(client, ramesh)
    assert [n["kind"] for n in bell["notices"]] == ["DELETED", "RECORDED", "CREDIT", "ADDED"]
    assert bell["unread"] == 4 and _unread(client, ramesh) == 4
    deleted, recorded, wrote, _ = bell["notices"]
    assert (wrote["name"], wrote["amountPaise"], wrote["note"]) == ("Sri Balaji Kirana", 25000, "rice")
    assert deleted["note"] == "by mistake" and recorded["amountPaise"] == 10000
    assert _bell(client, shop, "BUSINESS")["notices"] == []  # its own doing


def test_not_my_number(client):
    shop, book, ramesh = _people(client)
    client.post(f"/api/udhaar/mine/{book['id']}/not-me", headers=ramesh)
    assert _kinds(client, shop, "BUSINESS") == ["NOT_ME"]
    client.post(f"/api/udhaar/customers/{book['id']}/dispute/unlink", headers=shop)
    assert _kinds(client, shop, "BUSINESS") == []
    _post_entry(client, shop, book["id"], _entry("CREDIT", 250))
    assert _kinds(client, ramesh) == ["NUMBER_REMOVED"]  # nothing else from a book that is not theirs


def test_the_shop_keeps_the_number(client):
    shop, book, ramesh = _people(client)
    client.post(f"/api/udhaar/mine/{book['id']}/not-me", headers=ramesh)
    client.post(f"/api/udhaar/customers/{book['id']}/dispute/confirm", headers=shop)
    assert _kinds(client, ramesh) == ["NUMBER_KEPT", "ADDED"]


def test_paying_udhaar_online(client, world, test_account):  # noqa: F811
    shop, book, ramesh = _people(client)
    _post_entry(client, shop, book["id"], _entry("CREDIT", 250))
    _pay_online(client, world, book["id"], ramesh, 100)
    paid = _bell(client, shop, "BUSINESS")["notices"]
    assert [(n["kind"], n["name"], n["amountPaise"], n["testMode"]) for n in paid] == [
        ("PAID_ONLINE", "Ramesh", 10000, True)]
    assert _kinds(client, ramesh) == ["CREDIT", "ADDED"]  # their own payment is not news


def test_paying_by_upi(client, world):  # noqa: F811
    shop = _account(client, SHOP_A)
    client.put("/api/payments/settings/upi", json={"upiId": UPI, "upiName": "Lakshmi"}, headers=shop)
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    _pay(client, ramesh, method="UPI")  # started only
    assert _kinds(client, shop, "BUSINESS") == []
    first, second = _claimed(client, ramesh), _claimed(client, ramesh, rupees=60)
    says = _bell(client, shop, "BUSINESS")["notices"]
    assert [(n["kind"], n["name"]) for n in says] == [("SAYS_PAID", "Ramu")] * 2
    assert _kinds(client, ramesh) == []
    client.post(f"/api/payments/{first['id']}/confirm", headers=shop)
    client.post(f"/api/payments/{second['id']}/not-received", headers=shop)
    assert _kinds(client, shop, "BUSINESS") == []
    answers = _bell(client, ramesh)["notices"]
    assert [(n["kind"], n["amountPaise"]) for n in answers] == [("NOT_RECEIVED", 6000), ("RECEIVED", 15000)]
    # A second answer changes nothing.
    client.post(f"/api/payments/{second['id']}/confirm", headers=shop)
    assert _bell(client, ramesh)["notices"] == answers


def test_low_stock_until_refilled(client):
    shop = _account(client, SHOP_A)
    rice = _item(client, shop, openingMilli=20_000, alertMilli=10_000)
    assert _kinds(client, shop, "BUSINESS") == []
    _move(client, shop, rice["id"], "OUT", 15_000)
    low = _bell(client, shop, "BUSINESS")["notices"][0]
    assert (low["kind"], low["name"], low["note"]) == ("LOW_STOCK", "Rice", "5000 KG")
    _move(client, shop, rice["id"], "IN", 15_000)
    assert _kinds(client, shop, "BUSINESS") == []


def test_supplier_due(client):
    shop = _account(client, SHOP_A)
    today = datetime.now(INDIA).date()
    for name, days in (("Today", 0), ("Late", -5), ("Later", 2)):
        s = _supplier(client, shop, name)
        _supplier_entry(client, shop, s["id"], "PURCHASE", 500, at="2026-11-01T10:00:00+05:30",
                        dueDate=str(today + timedelta(days=days)))
    assert [(n["kind"], n["name"]) for n in _bell(client, shop, "BUSINESS")["notices"]] == [
        ("SUPPLIER_DUE", "Today"), ("SUPPLIER_DUE", "Late")]


def test_budget(client):
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    now = datetime.now(INDIA).isoformat()
    client.put("/api/customer/budget", json={"monthPaise": 10000}, headers=ramesh)
    _add(client, ramesh, amountPaise=7900, spentAt=now)
    assert _kinds(client, ramesh) == []
    _add(client, ramesh, amountPaise=2100, spentAt=now)
    near = _bell(client, ramesh)["notices"]
    assert [(n["kind"], n["amountPaise"]) for n in near] == [("BUDGET_NEAR", 10000)]
    double = _add(client, ramesh, amountPaise=100, spentAt=now).json()["id"].split("-")[1]
    client.post(f"/api/customer/records/{double}/same", headers=ramesh)
    assert _kinds(client, ramesh) == ["BUDGET_NEAR"]  # not counted
    client.post(f"/api/customer/records/{double}/different", headers=ramesh)
    assert _kinds(client, ramesh) == ["BUDGET_OVER"]
    client.put("/api/customer/budget", json={"monthPaise": None}, headers=ramesh)
    assert _kinds(client, ramesh) == []


def test_reading_one_and_all(client):
    shop, book, ramesh = _people(client)
    _post_entry(client, shop, book["id"], _entry("CREDIT", 250))
    first = _bell(client, ramesh)["notices"][0]
    read = {"role": "CUSTOMER", "id": first["id"]}
    assert client.post("/api/notices/read", json=read, headers=ramesh).status_code == 204
    assert client.post("/api/notices/read", json=read, headers=ramesh).status_code == 204
    assert [n["unread"] for n in _bell(client, ramesh)["notices"]] == [False, True]
    client.post("/api/notices/read", json={"role": "CUSTOMER"}, headers=ramesh)
    assert _unread(client, ramesh) == 0
    _post_entry(client, shop, book["id"], _entry("CREDIT", 50))
    assert [n["unread"] for n in _bell(client, ramesh)["notices"]] == [True, False, False]


def test_old_things_are_read_at_first_and_dropped_later(client):
    shop, book, ramesh = _people(client)
    for days, rupees in ((5, 10), (91, 20)):
        entry = _post_entry(client, shop, book["id"], _entry("CREDIT", rupees)).json()
        with engine.begin() as connection:
            connection.execute(text("UPDATE udhaar_entries SET created_at = now() - make_interval(days => :d)"
                                    " WHERE id = :id"), {"d": days, "id": entry["id"]})
    assert [(n["kind"], n["amountPaise"], n["unread"]) for n in _bell(client, ramesh)["notices"]] == [
        ("ADDED", None, True), ("CREDIT", 1000, False)]


def test_switching_off(client):
    shop, book, ramesh = _people(client)
    answer = client.put("/api/notices/off", json={"role": "CUSTOMER", "off": ["UDHAAR", "STOCK"]}, headers=ramesh)
    assert answer.json() == ["UDHAAR"]  # stock is not a customer's
    bell = _bell(client, ramesh)
    assert (bell["off"], bell["notices"], bell["unread"]) == (["UDHAAR"], [], 0)
    client.put("/api/notices/off", json={"role": "CUSTOMER", "off": []}, headers=ramesh)
    assert _kinds(client, ramesh) == ["ADDED"]


def test_private(client):
    shop, book, ramesh = _people(client)
    _post_entry(client, shop, book["id"], _entry("CREDIT", 250))
    other = _account(client, OTHER, roles=("CUSTOMER", "SUPPLIER"))
    other_shop = _account(client, SHOP_B)
    assert _kinds(client, other) == [] and _kinds(client, other_shop, "BUSINESS") == []
    assert _kinds(client, other, "SUPPLIER") == []
    for path in ("/api/notices?role=BUSINESS", "/api/notices/unread?role=BUSINESS"):
        assert client.get(path, headers=ramesh).status_code == 403
    assert client.post("/api/notices/read", json={"role": "BUSINESS"}, headers=ramesh).status_code == 403
    assert client.put("/api/notices/off", json={"role": "BUSINESS", "off": []}, headers=ramesh).status_code == 403
    assert client.get("/api/notices?role=OWNER", headers=ramesh).status_code == 400
    assert client.get("/api/notices?role=CUSTOMER").status_code == 401
