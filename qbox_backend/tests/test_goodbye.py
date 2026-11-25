"""Deleting one's own account: what goes, what stays for others; and the help and
legal pages."""

import json
from pathlib import Path

import pytest
from sqlalchemy import text

from app import ratelimit
from app.config import get_settings
from app.database import engine
from app.legal.router import TEXTS
from tests.test_calendar import EVENT, _account
from tests.test_payments import _customer_setup, test_account, world  # noqa: F401 (fixtures)
from tests.test_profile import _set
from tests.test_stock import _item
from tests.test_suppliers import _entry, _supplier
from tests.test_supply import (
    RAVI,
    _ask,
    _connected,
    _home,
    _move,
    _order_products,
    _product,
    _sell,
    _shop_side,
    _supplier_side,
    _upi,
    _write,
)
from tests.test_udhaar import RAMESH, SHOP_A, _add_customer

PIN = {"pin": "4826"}


@pytest.fixture(autouse=True)
def _fresh_counts():
    ratelimit.forget()


def _delete(client, who, pin="4826"):
    return client.post("/api/me/delete", json={"pin": pin}, headers=who)


def _rows(sql):
    with engine.connect() as connection:
        return connection.execute(text(sql)).all()


def _everything():
    """Every value in the database, as text."""
    with engine.connect() as connection:
        tables = connection.execute(text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")).scalars().all()
        return "\n".join(str(connection.execute(text(f'SELECT * FROM "{t}"')).all()) for t in tables)


def test_wrong_pin_and_no_login(client):
    me = _account(client, SHOP_A)
    assert _delete(client, me, "0000").json()["code"] == "WRONG_PIN"
    assert _delete(client, me, "12").status_code == 400
    for _ in range(4):
        _delete(client, me, "0000")
    assert _delete(client, me).status_code == 423 or _delete(client, me).status_code == 429  # locked, like a wrong login
    assert client.post("/api/me/delete", json=PIN).status_code == 401
    assert client.get("/api/me/delete-check").status_code == 401
    assert client.get("/api/me", headers=me).status_code == 200


def test_logged_out_and_the_number_is_free(client):
    me = _account(client, SHOP_A, roles=("BUSINESS", "CUSTOMER", "SUPPLIER"))
    assert _delete(client, me).status_code == 204
    assert client.get("/api/me", headers=me).status_code == 401
    assert _delete(client, me).status_code == 401
    login = client.post("/api/auth/login", json={"mobile": SHOP_A, "pin": "4826"})
    assert login.status_code in (400, 401)
    again = _account(client, SHOP_A)
    assert client.get("/api/me", headers=again).json()["shop"]["shopName"] == "Sri Balaji Kirana"
    assert client.get("/api/stock/items", headers=again).json()["items"] == []
    assert _delete(client, again).status_code == 204
    _account(client, SHOP_A, roles=("CUSTOMER",))


def test_private_things_are_erased(client):
    me = _account(client, SHOP_A, roles=("BUSINESS", "CUSTOMER", "SUPPLIER"))
    secret = "Zebra"
    client.put("/api/me/customer", headers=me, json={"fullName": f"{secret} Name", "email": "zebra@x.in", "address": f"{secret} street"})
    client.post("/api/calendar/events", headers=me, json={**EVENT, "title": f"{secret} event"})
    _set(client, me)
    _item(client, me, f"{secret} item")
    _supplier(client, me, f"{secret} supplier", note=f"{secret} note")
    _sell(client, me, _product(f"{secret} product"))
    _upi(client, me, "zebra@okaxis", f"{secret} upi")
    client.put("/api/payments/settings/upi", headers=me, json={"upiId": "zebra@okaxis", "upiName": secret})
    _add_customer(client, me, name=f"{secret} nobody", mobile=RAMESH)  # no lines: nobody's record
    client.get("/api/notices?role=BUSINESS", headers=me)
    assert secret in _everything()
    assert _delete(client, me).status_code == 204
    left = _everything()
    assert secret not in left and "zebra" not in left and SHOP_A not in left
    assert _rows("SELECT count(*) FROM user_roles")[0][0] == 0
    assert _rows("SELECT count(*) FROM profile_photos")[0][0] == 0
    assert _rows("SELECT count(*) FROM notice_settings")[0][0] == 0


def test_a_customer_still_sees_a_shop_that_left(client, world, test_account):  # noqa: F811
    shop, book, customer = _customer_setup(client)
    assert client.get("/api/me/delete-check", headers=customer).json()["youOwePaise"] == 50_000
    assert client.get("/api/me/delete-check", headers=shop).json()["owedToYouPaise"] == 50_000
    assert _delete(client, shop).status_code == 204
    mine = client.get("/api/udhaar/mine", headers=customer).json()[0]
    assert (mine["closed"], mine["balancePaise"], mine["shopPhone"], mine["shopAddress"]) == (True, 50_000, None, None)
    assert mine["shopName"] == "Sri Balaji Kirana"
    assert client.get(f"/api/udhaar/mine/{mine['bookId']}", headers=customer).json()["entries"] != []
    # Nothing can be paid there any more.
    assert client.get("/api/payments/shops", headers=customer).json()["shops"] == []
    paid = client.post(f"/api/payments/udhaar/{mine['bookId']}", headers=customer,
                       json={"amountPaise": 100, "clientRef": "a" * 20})
    assert (paid.status_code, paid.json()["code"]) == (409, "SHOP_CLOSED")
    direct = client.post("/api/payments/shop", headers=customer, json={
        "ref": f"book:{mine['bookId']}", "amountPaise": 100, "method": "ONLINE", "clientRef": "b" * 20})
    assert direct.json()["code"] == "SHOP_CLOSED"


def test_a_shop_keeps_its_book_when_a_customer_leaves(client, world, test_account):  # noqa: F811
    shop, book, customer = _customer_setup(client)
    before = client.get("/api/udhaar/customers", headers=shop).json()
    assert _delete(client, customer).status_code == 204
    after = client.get("/api/udhaar/customers", headers=shop).json()
    assert [(c["name"], c["balancePaise"]) for c in after["customers"]] == [
        (c["name"], c["balancePaise"]) for c in before["customers"]]


def test_payments_on_the_way_must_be_finished(client, world, test_account):  # noqa: F811
    shop, book, customer = _customer_setup(client)
    client.put("/api/payments/settings/upi", headers=shop, json={"upiId": "shop@okaxis", "upiName": "Shop"})
    started = client.post("/api/payments/collect", headers=shop, json={"amountPaise": 5000, "clientRef": "c" * 20})
    assert started.status_code == 201, started.text
    assert client.get("/api/me/delete-check", headers=shop).json()["paymentsOpen"] is True
    assert _delete(client, shop).json()["code"] == "PAYMENTS_OPEN"
    client.post(f"/api/payments/{started.json()['id']}/cancel", headers=shop)
    assert _delete(client, shop).status_code == 204


def test_a_supplier_keeps_what_a_shop_shared(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    _entry(client, shop, supplier, "PURCHASE", 500, note="Bill 1")
    private = _supplier(client, shop, "Private seller", note="Zebra")["id"]
    _entry(client, shop, private, "PURCHASE", 70)
    assert client.get("/api/me/delete-check", headers=shop).json()["youOwePaise"] == 67_000
    assert client.get("/api/me/delete-check", headers=ravi).json()["owedToYouPaise"] == 60_000
    assert _delete(client, shop).status_code == 204
    seen = _supplier_side(client, ravi, link)
    assert (seen["shop"]["connected"], seen["shop"]["balancePaise"], seen["shop"]["shopPhone"]) == (False, 60_000, None)
    assert [e["note"] for e in seen["entries"]] == ["Bill 1"]
    assert seen["shop"]["shopName"] == "Sri Balaji Kirana"
    left = _everything()
    assert "Zebra" not in left and "Private seller" not in left
    # A new account with that number is not connected with anyone.
    _account(client, SHOP_A)
    assert len(_home(client, ravi)["shops"]) == 1


def test_a_shop_keeps_its_account_when_a_supplier_leaves(client):
    shop, ravi, supplier, link = _connected(client, owed=100)
    rice = _sell(client, ravi, _product("Rice"))[0]
    _move(client, ravi, rice, "COUNT", 5000)
    _order_products(client, shop, supplier, (rice["id"], 1000))
    _write(client, ravi, link, "PURCHASE", 40)
    assert _delete(client, ravi).status_code == 204
    detail = _shop_side(client, shop, supplier)
    assert (detail["supplier"]["link"]["status"], detail["supplier"]["balancePaise"]) == ("ENDED", 10_000)
    assert detail["supplier"]["toConfirm"] == 0 or detail["entries"][0]["confirm"] == "CLOSED"
    assert detail["orders"][0]["lines"][0]["name"] == "Rice"
    order = detail["orders"][0]["id"]
    assert client.post(f"/api/suppliers/orders/{order}/cancel", headers=shop).json()["status"] == "CANCELLED"
    assert "SUPPLIER_LEFT" in [n["kind"] for n in client.get("/api/notices?role=BUSINESS", headers=shop).json()["notices"]]
    # They join again: a new account, and the shop must connect again.
    again = _account(client, RAVI, roles=("SUPPLIER",))
    assert _home(client, again)["shops"] == []
    assert _ask(client, shop, supplier).json()["link"]["status"] == "ON"


# ---------- help and legal ----------


def test_pages_and_contact(client, monkeypatch):
    empty = client.get("/api/info").json()
    assert empty == {"supportName": None, "supportPhone": None, "supportEmail": None}
    monkeypatch.setattr(get_settings(), "support_phone", "<1800>")
    for path, words in (("/privacy", "Privacy Policy"), ("/terms", "Terms of Use"), ("/delete-account", "Delete your QBOX account")):
        page = client.get(path)
        assert page.status_code == 200 and words in page.text and "text/html" in page.headers["content-type"]
        assert "&lt;1800&gt;" in page.text and "<1800>" not in page.text
    assert client.get("/api/info").json()["supportPhone"] == "<1800>"


def test_the_app_has_the_same_words():
    copy = Path(__file__).parents[2] / "qbox_frontend/assets/legal/texts.json"
    if copy.exists():
        assert json.loads(copy.read_text(encoding="utf-8")) == TEXTS
    assert set(TEXTS) == {"privacy", "terms", "help"}
    for page in TEXTS.values():
        assert page["title"] and page["updated"] and all(len(s) == 2 and s[0] and s[1] for s in page["sections"])
