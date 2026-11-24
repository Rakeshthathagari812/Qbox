"""Payments a customer adds, expense categories, leaving out, budget, privacy."""

import uuid

import pytest
from sqlalchemy import text

from app.database import engine
from tests.test_calendar import _account
from tests.test_customer import _history, _pay_online
from tests.test_payments import _customer_setup, test_account, world  # noqa: F401
from tests.test_udhaar import RAMESH, SHOP_A, _add_customer, _entry, _post_entry

RECORDS = "/api/customer/records"


def _body(**extra):
    return {"title": " Tea   stall ", "amountPaise": 2000, "category": "FOOD",
            "spentAt": "2026-11-20T09:00:00+05:30", "note": " two teas ", "clientRef": uuid.uuid4().hex, **extra}


def _add(client, who, **extra):
    return client.post(RECORDS, json=_body(**extra), headers=who)


def _ramesh(client):
    return _account(client, RAMESH, roles=("CUSTOMER",))


def _items(client, who, month="2026-11"):
    return _history(client, who, month)["transactions"]


def test_added_payment_shows_in_history(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    made = _add(client, ramesh)
    assert made.status_code == 201, made.text
    history = _history(client, ramesh, "2026-11")
    item = history["transactions"][0]
    assert (item["id"], item["shopName"], item["note"]) == (made.json()["id"], "Tea stall", "two teas")
    assert item["own"] is True and item["online"] is False and item["category"] == "FOOD"
    assert item["kind"] == "PAYMENT" and item["shopKey"] == "own" and item["status"] == "PAID"
    assert history["months"] == ["2026-11"]


def test_scanned_payment(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    item = _add(client, ramesh, scanned=True, upiId="tea@ybl").json()
    assert item["scanned"] is True and item["upiId"] == "tea@ybl"


def test_the_same_record_sent_twice_is_kept_once(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    body = _body()
    first = client.post(RECORDS, json=body, headers=ramesh).json()
    assert client.post(RECORDS, json=body, headers=ramesh).json()["id"] == first["id"]
    assert len(_items(client, ramesh)) == 1


def test_nothing_can_be_changed_or_deleted(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    number = _add(client, ramesh).json()["id"].split("-")[1]
    before = _items(client, ramesh)
    assert client.put(f"{RECORDS}/{number}", headers=ramesh, json=_body(amountPaise=4500)).status_code in (404, 405)
    assert client.delete(f"{RECORDS}/{number}", headers=ramesh).status_code in (404, 405)
    assert _items(client, ramesh) == before


def test_the_same_payment_or_not(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    number = _add(client, ramesh).json()["id"].split("-")[1]
    same = client.post(f"{RECORDS}/{number}/same", headers=ramesh).json()
    assert (same["same"], same["notSame"]) == (True, False)
    assert _items(client, ramesh)[0]["same"] is True  # still in the history
    back = client.post(f"{RECORDS}/{number}/different", headers=ramesh).json()
    assert (back["same"], back["notSame"]) == (False, True)
    assert client.post(f"{RECORDS}/999999/same", headers=ramesh).status_code == 404


def test_category_and_leaving_out_for_an_added_one(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    item = _add(client, ramesh).json()["id"]
    url = f"/api/customer/expenses/{item}"
    client.put(url, json={"category": "BILLS", "hidden": True}, headers=ramesh)
    now = _items(client, ramesh)[0]
    assert (now["category"], now["hidden"], now["amountPaise"]) == ("BILLS", True, 2000)
    client.put(url, json={}, headers=ramesh)
    assert (_items(client, ramesh)[0]["category"], _items(client, ramesh)[0]["hidden"]) == ("FOOD", False)
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    assert client.put(url, json={"hidden": True}, headers=stranger).status_code == 404


@pytest.mark.parametrize("bad", [
    {"title": "  "}, {"title": "x" * 81}, {"amountPaise": 99}, {"amountPaise": 100_000_001}, {"category": "CARS"},
    {"spentAt": "1999-01-01T00:00:00Z"}, {"spentAt": "2999-01-01T00:00:00Z"}, {"clientRef": "x"},
    {"note": "n" * 201}, {"upiId": "u" * 331},
])
def test_input_checks(client, world, bad):  # noqa: F811
    assert _add(client, _ramesh(client), **bad).status_code == 400


def test_records_are_private(client, world):  # noqa: F811
    ramesh, shop = _ramesh(client), _account(client, SHOP_A)
    number = _add(client, ramesh).json()["id"].split("-")[1]
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    for who, code in ((stranger, 404), (shop, 403)):
        assert client.post(f"{RECORDS}/{number}/same", headers=who).status_code == code
        assert client.post(f"{RECORDS}/{number}/different", headers=who).status_code == code
    assert _items(client, stranger) == []
    assert _add(client, shop).status_code == 403
    assert client.post(RECORDS, json=_body()).status_code == 401
    assert len(_items(client, ramesh)) == 1


# ---------- automatic expenses ----------


def test_udhaar_counts_when_it_is_paid(client, world):  # noqa: F811
    """Only payments carry a category; udhaar taken does not, so it counts once."""
    shop = _account(client, SHOP_A)
    with engine.begin() as connection:
        connection.execute(text("UPDATE shop_profiles SET shop_category = 'Medical & Healthcare'"))
    book = _add_customer(client, shop)["id"]
    _post_entry(client, shop, book, _entry("CREDIT", 500))
    _post_entry(client, shop, book, _entry("PAYMENT", 500))
    by_kind = {t["kind"]: t for t in _items(client, _ramesh(client))}
    assert by_kind["CREDIT"]["category"] is None
    assert by_kind["PAYMENT"]["category"] == "HEALTH" and by_kind["PAYMENT"]["hidden"] is False


def test_choose_a_category_or_leave_out(client, world, test_account):  # noqa: F811
    shop, book_id, ramesh = _customer_setup(client)
    _pay_online(client, world, book_id, ramesh, 300)
    paid = next(t for t in _history(client, ramesh)["transactions"] if t["kind"] == "PAYMENT")
    url = f"/api/customer/expenses/{paid['id']}"
    for body in ({"category": "BILLS"}, {"category": "FUN", "hidden": True}):
        assert client.put(url, json=body, headers=ramesh).status_code == 200
    now = next(t for t in _history(client, ramesh)["transactions"] if t["kind"] == "PAYMENT")
    assert now["category"] == "FUN" and now["hidden"] is True
    client.put(url, json={}, headers=ramesh)  # back to the usual
    back = next(t for t in _history(client, ramesh)["transactions"] if t["kind"] == "PAYMENT")
    assert back["category"] == paid["category"] and back["hidden"] is False
    # The shop's book is not changed by any of this.
    assert client.get(f"/api/udhaar/customers/{book_id}", headers=shop).json()["customer"]["balancePaise"] == 20000


def test_marks_only_on_your_own_items(client, world, test_account):  # noqa: F811
    _, book_id, ramesh = _customer_setup(client)
    _pay_online(client, world, book_id, ramesh, 300)
    item = next(t for t in _history(client, ramesh)["transactions"] if t["kind"] == "PAYMENT")["id"]
    stranger = _account(client, "9000000001", roles=("CUSTOMER",))
    assert client.put(f"/api/customer/expenses/{item}", json={"hidden": True}, headers=stranger).status_code == 404
    for bad in ("entry-999999", "payment-999999", "own-1", "entry-x", "entry-1'--"):
        assert client.put(f"/api/customer/expenses/{bad}", json={"hidden": True}, headers=ramesh).status_code == 404


def test_budget(client, world):  # noqa: F811
    ramesh, stranger = _ramesh(client), _account(client, "9000000001", roles=("CUSTOMER",))
    assert _history(client, ramesh)["budgetPaise"] is None
    for paise in (500000, 800000):
        assert client.put("/api/customer/budget", json={"monthPaise": paise}, headers=ramesh).status_code == 200
    assert _history(client, ramesh)["budgetPaise"] == 800000
    assert _history(client, stranger)["budgetPaise"] is None
    assert client.put("/api/customer/budget", json={"monthPaise": 5}, headers=ramesh).status_code == 400
    client.put("/api/customer/budget", json={}, headers=ramesh)
    assert _history(client, ramesh)["budgetPaise"] is None
    assert client.put("/api/customer/budget", json={}, headers=_account(client, SHOP_A)).status_code == 403


def test_deleting_the_account_deletes_the_records(client, world):  # noqa: F811
    ramesh = _ramesh(client)
    _add(client, ramesh)
    client.put("/api/customer/budget", json={"monthPaise": 5000}, headers=ramesh)
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM users"))
        assert connection.execute(text("SELECT count(*) FROM customer_records")).scalar_one() == 0
        assert connection.execute(text("SELECT count(*) FROM expense_budgets")).scalar_one() == 0
