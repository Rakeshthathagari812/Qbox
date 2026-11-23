"""Supplier API tests: suppliers, the account (purchases and payments), purchases
adding to stock, orders, pay-by dates, checks and privacy."""

import uuid
from datetime import date, datetime, timedelta

from tests.test_calendar import _account
from tests.test_stock import _item

SHOP_A = "9876543210"
SHOP_B = "9123456780"
AT = "2026-11-20T10:00:00+05:30"


def _ref():
    return uuid.uuid4().hex


def _supplier(client, shop, name="Ravi Traders", **extra):
    response = client.post("/api/suppliers", json={"name": name, "clientRef": _ref(), **extra}, headers=shop)
    assert response.status_code == 201, response.text
    return response.json()


def _entry(client, shop, supplier_id, kind, rupees, at=AT, ref=None, **extra):
    return client.post(f"/api/suppliers/{supplier_id}/entries", headers=shop, json={
        "kind": kind, "amountPaise": rupees * 100, "entryAt": at, "clientRef": ref or _ref(), **extra,
    })


def _qty(client, shop, item_id):
    return client.get(f"/api/stock/items/{item_id}", headers=shop).json()["item"]["quantityMilli"]


def test_supplier_account_purchases_and_payments(client):
    shop = _account(client, SHOP_A)
    ravi = _supplier(client, shop, "  Ravi   Traders ", mobile="+91 98480 22338", supplies="Rice, dal")
    assert ravi["name"] == "Ravi Traders" and ravi["mobile"] == "9848022338" and ravi["balancePaise"] == 0

    assert _entry(client, shop, ravi["id"], "PURCHASE", 12000, note="Bill 45").status_code == 201
    assert _entry(client, shop, ravi["id"], "PAYMENT", 5000, method="UPI").status_code == 201
    detail = client.get(f"/api/suppliers/{ravi['id']}", headers=shop).json()
    assert detail["supplier"]["balancePaise"] == 700_000
    assert sorted((e["kind"], e["method"] or "") for e in detail["entries"]) == [("PAYMENT", "UPI"), ("PURCHASE", "")]
    assert {e["note"] for e in detail["entries"]} == {"Bill 45", None}

    listing = client.get("/api/suppliers", headers=shop).json()
    assert listing["totalDuePaise"] == 700_000 and [s["name"] for s in listing["suppliers"]] == ["Ravi Traders"]


def test_purchase_items_go_into_stock_and_back_out_when_deleted(client):
    shop = _account(client, SHOP_A)
    rice = _item(client, shop, "Rice", openingMilli=5_000, costPaise=4500)
    sugar = _item(client, shop, "Sugar")
    ravi = _supplier(client, shop)
    response = _entry(client, shop, ravi["id"], "PURCHASE", 1600, lines=[
        {"itemId": rice["id"], "qtyMilli": 25_000, "costPaise": 4800},
        {"itemId": sugar["id"], "qtyMilli": 10_000},
    ])
    assert response.status_code == 201, response.text
    entry = response.json()
    assert [(line["name"], line["qtyMilli"]) for line in entry["lines"]] == [("Rice", 25_000), ("Sugar", 10_000)]
    assert _qty(client, shop, rice["id"]) == 30_000 and _qty(client, shop, sugar["id"]) == 10_000
    rice_now = client.get(f"/api/stock/items/{rice['id']}", headers=shop).json()
    assert rice_now["item"]["costPaise"] == 4800  # the latest buying price
    assert "From Ravi Traders" in {m["note"] for m in rice_now["moves"]}

    deleted = client.post(f"/api/suppliers/entries/{entry['id']}/delete", json={"reason": "wrong bill"}, headers=shop)
    assert deleted.status_code == 200 and deleted.json()["deleteReason"] == "wrong bill"
    assert _qty(client, shop, rice["id"]) == 5_000 and _qty(client, shop, sugar["id"]) == 0
    # Deleting again changes nothing.
    client.post(f"/api/suppliers/entries/{entry['id']}/delete", json={"reason": "again"}, headers=shop)
    assert _qty(client, shop, rice["id"]) == 5_000
    assert client.get(f"/api/suppliers/{ravi['id']}", headers=shop).json()["supplier"]["balancePaise"] == 0


def test_purchase_paid_now_adds_its_payment(client):
    shop = _account(client, SHOP_A)
    ravi = _supplier(client, shop)
    ref = _ref()
    assert _entry(client, shop, ravi["id"], "PURCHASE", 800, ref=ref, paidNow=True, method="CASH").status_code == 201
    _entry(client, shop, ravi["id"], "PURCHASE", 800, ref=ref, paidNow=True, method="CASH")  # retry: kept once
    detail = client.get(f"/api/suppliers/{ravi['id']}", headers=shop).json()
    assert sorted(e["kind"] for e in detail["entries"]) == ["PAYMENT", "PURCHASE"]
    assert detail["supplier"]["balancePaise"] == 0


def test_pay_by_dates_oldest_paid_first(client):
    shop = _account(client, SHOP_A)
    ravi = _supplier(client, shop)
    past = (date.today() - timedelta(days=3)).isoformat()
    later = (date.today() + timedelta(days=10)).isoformat()
    _entry(client, shop, ravi["id"], "PURCHASE", 1000, at="2026-11-01T10:00:00+05:30", dueDate=past)
    _entry(client, shop, ravi["id"], "PURCHASE", 2000, at="2026-11-05T10:00:00+05:30", dueDate=later)
    supplier = client.get("/api/suppliers", headers=shop).json()["suppliers"][0]
    assert supplier["nextDue"] == past and supplier["overdue"] is True
    # Paying ₹1,000 clears the oldest purchase: the next pay-by date moves on.
    _entry(client, shop, ravi["id"], "PAYMENT", 1000)
    supplier = client.get("/api/suppliers", headers=shop).json()["suppliers"][0]
    assert supplier["nextDue"] == later and supplier["overdue"] is False
    _entry(client, shop, ravi["id"], "PAYMENT", 2000)
    assert client.get("/api/suppliers", headers=shop).json()["suppliers"][0]["nextDue"] is None


def test_order_then_received_as_a_purchase(client):
    shop = _account(client, SHOP_A)
    rice = _item(client, shop, "Rice")
    oil = _item(client, shop, "Oil", unit="L")
    ravi = _supplier(client, shop)
    order = client.post(f"/api/suppliers/{ravi['id']}/orders", headers=shop, json={
        "lines": [{"itemId": rice["id"], "qtyMilli": 25_000}, {"itemId": oil["id"], "qtyMilli": 15_000}],
        "clientRef": _ref(),
    })
    assert order.status_code == 201, order.text
    order = order.json()
    assert order["status"] == "SENT" and [line["unit"] for line in order["lines"]] == ["KG", "L"]
    assert client.get("/api/suppliers", headers=shop).json()["suppliers"][0]["openOrders"] == 1

    # Only 20 kg rice came, no oil; paid later by a date.
    received = client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": 96_000, "lines": [{"itemId": rice["id"], "qtyMilli": 20_000, "costPaise": 4800}],
        "dueDate": (date.today() + timedelta(days=7)).isoformat(), "clientRef": _ref(),
    })
    assert received.status_code == 200, received.text
    assert received.json()["status"] == "RECEIVED"
    assert _qty(client, shop, rice["id"]) == 20_000 and _qty(client, shop, oil["id"]) == 0
    detail = client.get(f"/api/suppliers/{ravi['id']}", headers=shop).json()
    assert detail["supplier"]["balancePaise"] == 96_000 and detail["supplier"]["openOrders"] == 0
    assert detail["entries"][0]["orderId"] == order["id"]

    # Receiving again does not add the stock twice; a received order cannot be cancelled.
    client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": 96_000, "lines": [{"itemId": rice["id"], "qtyMilli": 20_000}], "clientRef": _ref()})
    assert _qty(client, shop, rice["id"]) == 20_000
    assert client.post(f"/api/suppliers/orders/{order['id']}/cancel", headers=shop).json()["status"] == "RECEIVED"


def test_cancelled_order_cannot_be_received(client):
    shop = _account(client, SHOP_A)
    rice = _item(client, shop, "Rice")
    ravi = _supplier(client, shop)
    order = client.post(f"/api/suppliers/{ravi['id']}/orders", headers=shop, json={
        "lines": [{"itemId": rice["id"], "qtyMilli": 1000}], "clientRef": _ref()}).json()
    assert client.post(f"/api/suppliers/orders/{order['id']}/cancel", headers=shop).json()["status"] == "CANCELLED"
    response = client.post(f"/api/suppliers/orders/{order['id']}/receive", headers=shop, json={
        "amountPaise": 100, "lines": [], "clientRef": _ref()})
    assert response.status_code == 409 and response.json()["code"] == "ORDER_CLOSED"


def test_checks(client):
    shop = _account(client, SHOP_A)
    other = _account(client, SHOP_B)
    theirs = _item(client, other, "Rice")
    ravi = _supplier(client, shop)
    assert client.post("/api/suppliers", json={"name": "RAVI TRADERS", "clientRef": _ref()},
                       headers=shop).json()["code"] == "SUPPLIER_EXISTS"
    for body, message in [
        ({"name": " "}, "Enter the supplier's name"),
        ({"name": "X", "mobile": "12345"}, "Enter a valid 10-digit mobile number"),
    ]:
        response = client.post("/api/suppliers", json={**body, "clientRef": _ref()}, headers=shop)
        assert response.status_code == 400 and response.json()["message"] == message
    bad = [
        ({"kind": "PAYMENT", "lines": [{"itemId": 1, "qtyMilli": 1000}]}, "A payment has no items or due date"),
        ({"kind": "PURCHASE", "paidNow": True, "dueDate": "2026-12-01"}, "A purchase paid now has no due date"),
    ]
    for extra, message in bad:
        response = client.post(f"/api/suppliers/{ravi['id']}/entries", headers=shop, json={
            "amountPaise": 1000, "entryAt": AT, "clientRef": _ref(), **extra})
        assert response.status_code == 400 and response.json()["message"] == message
    assert _entry(client, shop, ravi["id"], "PAYMENT", 0).status_code == 400
    future = (datetime.now() + timedelta(days=3)).isoformat()
    assert _entry(client, shop, ravi["id"], "PAYMENT", 10, at=future).status_code == 400
    # Another shop's stock item cannot be bought into this shop's stock.
    response = _entry(client, shop, ravi["id"], "PURCHASE", 10, lines=[{"itemId": theirs["id"], "qtyMilli": 1000}])
    assert response.status_code == 404
    assert client.get(f"/api/stock/items/{theirs['id']}", headers=other).json()["item"]["quantityMilli"] == 0


def test_suppliers_are_private(client):
    shop = _account(client, SHOP_A)
    other = _account(client, SHOP_B)
    customer = _account(client, "9988776655", roles=("CUSTOMER",))
    rice = _item(client, shop, "Rice")
    ravi = _supplier(client, shop)
    entry = _entry(client, shop, ravi["id"], "PURCHASE", 100).json()
    order = client.post(f"/api/suppliers/{ravi['id']}/orders", headers=shop, json={
        "lines": [{"itemId": rice["id"], "qtyMilli": 1000}], "clientRef": _ref()}).json()
    assert client.get(f"/api/suppliers/{ravi['id']}", headers=other).status_code == 404
    assert client.put(f"/api/suppliers/{ravi['id']}", json={"name": "x"}, headers=other).status_code == 404
    assert _entry(client, other, ravi["id"], "PAYMENT", 10).status_code == 404
    assert client.post(f"/api/suppliers/entries/{entry['id']}/delete", json={"reason": "x"},
                       headers=other).status_code == 404
    assert client.post(f"/api/suppliers/orders/{order['id']}/cancel", headers=other).status_code == 404
    assert client.get("/api/suppliers", headers=other).json()["suppliers"] == []
    assert client.get("/api/suppliers", headers=customer).status_code == 403

    # Removed from the list: gone for the shop too, but the name is free again.
    assert client.post(f"/api/suppliers/{ravi['id']}/archive", headers=shop).status_code == 200
    assert client.get(f"/api/suppliers/{ravi['id']}", headers=shop).status_code == 404
    _supplier(client, shop, "Ravi Traders")
