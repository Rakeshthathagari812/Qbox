"""The customer's shops (extra details) and transaction history: what is shown,
shown once, months in India time, privacy."""

import pytest
from sqlalchemy import text

from app.database import engine
from tests.test_calendar import _account
from tests.test_payments import _customer_setup, _forget_last_check, _ref, _sign, test_account, world  # noqa: F401
from tests.test_udhaar import RAMESH, SHOP_A, SHOP_B, _add_customer, _entry, _post_entry

URL = "/api/customer/transactions"


def _history(client, who, month=None):
    response = client.get(URL, params={"month": month} if month else None, headers=who)
    assert response.status_code == 200, response.text
    return response.json()


def _short(history):
    return [(t["kind"], t["amountPaise"] // 100, t["online"]) for t in history["transactions"]]


def _pay_online(client, world, book_id, who, rupees):  # noqa: F811
    body = client.post(f"/api/payments/udhaar/{book_id}",
                       json={"amountPaise": rupees * 100, "clientRef": _ref()}, headers=who).json()
    paid = world.pay(body["orderId"])
    done = client.post(f"/api/payments/{body['payment']['id']}/verify", headers=who, json={
        "razorpayPaymentId": paid.payment_id, "razorpayOrderId": body["orderId"],
        "razorpaySignature": _sign(body["orderId"], paid.payment_id)})
    assert done.json()["status"] == "PAID", done.text
    return body["payment"]["id"]


def test_my_shops_have_contact_details(client):
    shop = _account(client, SHOP_A)
    _add_customer(client, shop)
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    mine = client.get("/api/udhaar/mine", headers=ramesh).json()[0]
    assert mine["shopPhone"] == SHOP_A and mine["shopAddress"] and mine["shopCategory"]


def test_history_from_every_shop_newest_first(client, world):  # noqa: F811
    a, b = _account(client, SHOP_A), _account(client, SHOP_B)
    in_a, in_b = _add_customer(client, a), _add_customer(client, b)
    _post_entry(client, a, in_a["id"], _entry("CREDIT", 250, "rice", at="2026-11-19T10:00:00+05:30"))
    _post_entry(client, b, in_b["id"], _entry("CREDIT", 90, at="2026-11-20T09:00:00+05:30"))
    _post_entry(client, a, in_a["id"], _entry("PAYMENT", 100, at="2026-11-21T09:00:00+05:30"))
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))

    history = _history(client, ramesh, "2026-11")
    assert _short(history) == [("PAYMENT", 100, False), ("CREDIT", 90, False), ("CREDIT", 250, False)]
    assert history["month"] == "2026-11" and history["months"] == ["2026-11"]
    first, second, third = history["transactions"]
    assert first["shopKey"] == third["shopKey"] != second["shopKey"]
    assert third["note"] == "rice" and third["bookId"] == in_a["id"]


def test_months_use_india_time(client, world):  # noqa: F811
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    # 31 Oct 20:00 UTC is already 1 November, 1:30 AM in India.
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 10, at="2026-10-31T20:00:00+00:00"))
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 20, at="2026-10-31T18:00:00+00:00"))
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 30, at="2025-12-31T23:30:00+05:30"))
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    november = _history(client, ramesh, "2026-11")
    assert november["months"] == ["2026-11", "2026-10", "2025-12"]
    assert _short(november) == [("CREDIT", 10, False)]
    assert _short(_history(client, ramesh, "2026-10")) == [("CREDIT", 20, False)]
    assert _short(_history(client, ramesh, "2025-12")) == [("CREDIT", 30, False)]
    assert _history(client, ramesh, "2024-01")["transactions"] == []


def test_a_qbox_payment_shows_once(client, world, test_account):  # noqa: F811
    _, book_id, ramesh = _customer_setup(client)
    _pay_online(client, world, book_id, ramesh, 300)
    items = [t for t in _history(client, ramesh)["transactions"] if t["kind"] == "PAYMENT"]
    assert len(items) == 1
    assert items[0]["amountPaise"] == 30000 and items[0]["online"] is True and items[0]["testMode"] is True
    assert items[0]["bookId"] == book_id


def test_a_payment_not_reported_by_the_app_is_found(client, world, test_account):  # noqa: F811
    _, book_id, ramesh = _customer_setup(client)
    body = client.post(f"/api/payments/udhaar/{book_id}",
                       json={"amountPaise": 20000, "clientRef": _ref()}, headers=ramesh).json()
    assert all(t["kind"] == "CREDIT" for t in _history(client, ramesh)["transactions"])
    world.pay(body["orderId"])
    _forget_last_check(body["payment"]["id"])
    assert ("PAYMENT", 200, True) in _short(_history(client, ramesh))


def test_money_paid_stays_when_the_shop_deletes_the_line(client, world, test_account):  # noqa: F811
    shop, book_id, ramesh = _customer_setup(client)
    _pay_online(client, world, book_id, ramesh, 300)
    line = client.get(f"/api/udhaar/customers/{book_id}", headers=shop).json()["entries"][0]
    client.post(f"/api/udhaar/entries/{line['id']}/delete", json={"reason": "by mistake"}, headers=shop)
    item = next(t for t in _history(client, ramesh)["transactions"] if t["kind"] == "PAYMENT")
    assert item["online"] is True and item["deletedAt"] and item["deleteReason"] == "by mistake"


def test_unlinked_book_is_hidden_but_my_own_payment_stays(client, world, test_account):  # noqa: F811
    shop, book_id, ramesh = _customer_setup(client)
    _pay_online(client, world, book_id, ramesh, 300)
    client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=ramesh)
    client.post(f"/api/udhaar/customers/{book_id}/dispute/unlink", headers=shop)
    history = _history(client, ramesh)
    assert _short(history) == [("PAYMENT", 300, True)]
    assert history["transactions"][0]["id"].startswith("payment-") and history["transactions"][0]["bookId"] is None
    assert len(history["months"]) == 1


def test_waiting_and_failed_payments_are_not_shown(client, world, test_account):  # noqa: F811
    _, book_id, ramesh = _customer_setup(client)
    client.post(f"/api/payments/udhaar/{book_id}", json={"amountPaise": 100, "clientRef": _ref()}, headers=ramesh)
    with engine.begin() as connection:
        connection.execute(text("UPDATE payments SET expires_at = now() - interval '2 days'"))
    assert all(t["kind"] == "CREDIT" for t in _history(client, ramesh)["transactions"])


def test_a_payment_is_still_found_days_later(client, world, test_account):  # noqa: F811
    shop, book_id, ramesh = _customer_setup(client)
    body = client.post(f"/api/payments/udhaar/{book_id}",
                       json={"amountPaise": 20000, "clientRef": _ref()}, headers=ramesh).json()
    world.pay(body["orderId"])
    with engine.begin() as connection:
        connection.execute(text("UPDATE payments SET expires_at = now() - interval '3 days', checked_at = NULL"))
    assert ("PAYMENT", 200, True) in _short(_history(client, ramesh))
    assert client.get(f"/api/udhaar/customers/{book_id}", headers=shop).json()["customer"]["balancePaise"] == 30000


def test_history_is_private(client, world, test_account):  # noqa: F811
    shop, book_id, ramesh = _customer_setup(client)
    _pay_online(client, world, book_id, ramesh, 100)
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    nothing = _history(client, stranger, "2026-11")
    assert nothing["transactions"] == [] and nothing["months"] == []
    assert client.get(URL, headers=shop).status_code == 403
    assert client.get(URL).status_code == 401


@pytest.mark.parametrize("month", ["2026-13", "2026-00", "nov", "2026-1", "1999-05", "2026-11-01"])
def test_bad_month_is_refused(client, world, month):  # noqa: F811
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    assert client.get(URL, params={"month": month}, headers=ramesh).status_code == 400