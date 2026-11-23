"""Stock API tests: items, moves and quantities, quick start, checks, privacy."""

import uuid

from tests.test_calendar import _account

SHOP_A = "9876543210"
SHOP_B = "9123456780"
NOW = "2026-11-23T10:00:00+05:30"


def _ref():
    return uuid.uuid4().hex


def _item(client, shop, name="Rice", unit="KG", **extra):
    body = {"name": name, "unit": unit, "clientRef": _ref(), **extra}
    response = client.post("/api/stock/items", json=body, headers=shop)
    assert response.status_code == 201, response.text
    return response.json()


def _move(client, shop, item_id, kind, qty_milli, note=None, ref=None):
    return client.post(f"/api/stock/items/{item_id}/moves", headers=shop, json={
        "kind": kind, "qtyMilli": qty_milli, "note": note, "moveAt": NOW, "clientRef": ref or _ref(),
    })


def test_item_with_opening_stock_then_in_out_and_correction(client):
    shop = _account(client, SHOP_A)
    rice = _item(client, shop, "  Sona  Masoori rice ", openingMilli=50_000, costPaise=4800,
                 pricePaise=5500, alertMilli=10_000, catalogCode="rice")
    assert rice["name"] == "Sona Masoori rice"
    assert rice["quantityMilli"] == 50_000 and rice["low"] is False
    assert rice["valuePaise"] == 240_000  # 50 kg x ₹48

    assert _move(client, shop, rice["id"], "OUT", 2_500).status_code == 201  # 2.5 kg sold
    assert _move(client, shop, rice["id"], "IN", 25_000, "Ravi Traders").status_code == 201
    assert _move(client, shop, rice["id"], "ADJUST", -500, "spilled").status_code == 201

    detail = client.get(f"/api/stock/items/{rice['id']}", headers=shop).json()
    assert detail["item"]["quantityMilli"] == 72_000
    assert sorted(m["kind"] for m in detail["moves"]) == ["ADJUST", "IN", "IN", "OUT"]
    assert {m["note"] for m in detail["moves"]} == {"Opening stock", None, "Ravi Traders", "spilled"}

    stock = client.get("/api/stock/items", headers=shop).json()
    assert stock["totalValuePaise"] == 72 * 4800 and stock["lowCount"] == 0


def test_low_stock(client):
    shop = _account(client, SHOP_A)
    sugar = _item(client, shop, "Sugar", openingMilli=6_000, alertMilli=5_000)
    _item(client, shop, "Salt", unit="PACKET", openingMilli=20_000)  # no alert level: never low
    _move(client, shop, sugar["id"], "OUT", 1_000)
    stock = client.get("/api/stock/items", headers=shop).json()
    assert stock["lowCount"] == 1
    assert [(i["name"], i["low"]) for i in stock["items"]] == [("Salt", False), ("Sugar", True)]  # by name
    assert stock["totalValuePaise"] == 0  # no buying prices given


def test_same_entry_twice_is_kept_once(client):
    shop = _account(client, SHOP_A)
    ref = _ref()
    body = {"name": "Oil", "unit": "L", "clientRef": ref, "openingMilli": 10_000}
    first = client.post("/api/stock/items", json=body, headers=shop).json()
    again = client.post("/api/stock/items", json=body, headers=shop)
    assert again.status_code == 201 and again.json()["id"] == first["id"]

    move_ref = _ref()
    a = _move(client, shop, first["id"], "OUT", 1_000, ref=move_ref).json()
    b = _move(client, shop, first["id"], "OUT", 1_000, ref=move_ref).json()
    assert a["id"] == b["id"]
    assert client.get(f"/api/stock/items/{first['id']}", headers=shop).json()["item"]["quantityMilli"] == 9_000


def test_names_are_unique_per_shop(client):
    shop = _account(client, SHOP_A)
    other = _account(client, SHOP_B)
    rice = _item(client, shop, "Rice")
    response = client.post("/api/stock/items", json={"name": "RICE", "unit": "KG", "clientRef": _ref()}, headers=shop)
    assert response.status_code == 409 and response.json()["code"] == "ITEM_EXISTS"
    _item(client, other, "Rice")  # another shop may have its own Rice

    dal = _item(client, shop, "Toor dal")
    renamed = client.put(f"/api/stock/items/{dal['id']}", json={"name": "rice"}, headers=shop)
    assert renamed.status_code == 409

    # Removed from the list: the name can be used again, the old history stays.
    assert client.post(f"/api/stock/items/{rice['id']}/archive", headers=shop).status_code == 200
    assert client.get(f"/api/stock/items/{rice['id']}", headers=shop).status_code == 404
    _item(client, shop, "Rice")
    stock = client.get("/api/stock/items", headers=shop).json()
    assert [i["name"] for i in stock["items"]] == ["Rice", "Toor dal"]
    assert stock["pastItems"] == []  # Rice is back in stock, so it is not offered again


def test_removed_items_are_offered_again(client):
    shop = _account(client, SHOP_A)
    other = _account(client, SHOP_B)
    mine = _item(client, shop, "Sona masoori", catalogCode="rice")
    soap = _item(client, shop, "Lux soap", unit="PIECE")
    for item in (mine, soap):
        client.post(f"/api/stock/items/{item['id']}/archive", headers=shop)
    past = client.get("/api/stock/items", headers=shop).json()["pastItems"]
    assert past == [
        {"name": "Lux soap", "unit": "PIECE", "catalogCode": None},  # newest first
        {"name": "Sona masoori", "unit": "KG", "catalogCode": "rice"},
    ]
    assert client.get("/api/stock/items", headers=other).json()["pastItems"] == []


def test_quick_start_adds_many_and_skips_existing(client):
    shop = _account(client, SHOP_A)
    _item(client, shop, "Sugar", openingMilli=3_000)
    items = [
        {"name": "Rice", "unit": "KG", "catalogCode": "rice", "openingMilli": 25_000, "clientRef": _ref()},
        {"name": "Sugar", "unit": "KG", "catalogCode": "sugar", "openingMilli": 9_000, "clientRef": _ref()},
        {"name": "Soap", "unit": "PIECE", "catalogCode": "bath_soap", "clientRef": _ref()},
    ]
    response = client.post("/api/stock/items/bulk", json={"items": items}, headers=shop)
    assert response.status_code == 201, response.text
    added = response.json()
    assert [i["name"] for i in added] == ["Rice", "Sugar", "Soap"]
    assert added[1]["quantityMilli"] == 3_000  # the existing Sugar, unchanged
    # Sent again (retry): nothing doubles.
    again = client.post("/api/stock/items/bulk", json={"items": items}, headers=shop).json()
    assert [i["id"] for i in again] == [i["id"] for i in added]
    assert len(client.get("/api/stock/items", headers=shop).json()["items"]) == 3


def test_change_item(client):
    shop = _account(client, SHOP_A)
    item = _item(client, shop, "Atta", openingMilli=10_000, costPaise=4000)
    changed = client.put(f"/api/stock/items/{item['id']}",
                         json={"name": "Aashirvaad atta", "costPaise": 4500, "alertMilli": 10_000}, headers=shop)
    assert changed.status_code == 200, changed.text
    body = changed.json()
    assert body["name"] == "Aashirvaad atta" and body["valuePaise"] == 45_000 and body["low"] is True
    assert body["unit"] == "KG" and body["pricePaise"] is None


def test_checks(client):
    shop = _account(client, SHOP_A)
    item = _item(client, shop, "Rice")
    bad_items = [
        ({"name": " ", "unit": "KG"}, "Enter the item name"),
        ({"name": "x" * 81, "unit": "KG"}, None),
        ({"name": "Rice2", "unit": "TONNE"}, None),
        ({"name": "Rice3", "unit": "KG", "costPaise": -1}, None),
        ({"name": "Rice4", "unit": "KG", "catalogCode": "Bad Code"}, None),
    ]
    for body, message in bad_items:
        response = client.post("/api/stock/items", json={**body, "clientRef": _ref()}, headers=shop)
        assert response.status_code == 400, body
        if message:
            assert response.json()["message"] == message
    for kind, qty, note, message in [
        ("OUT", 0, None, "Enter a quantity"),
        ("IN", -5, None, "Enter a quantity"),
        ("ADJUST", -500, None, "Write why the count changed (damaged, expired, counted wrong)"),
        ("ADJUST", 0, "x", "The count is already this"),
        ("OUT", 2_000_000_000, None, "This quantity is too large"),
    ]:
        response = _move(client, shop, item["id"], kind, qty, note)
        assert response.status_code == 400 and response.json()["message"] == message
    future = client.post(f"/api/stock/items/{item['id']}/moves", headers=shop, json={
        "kind": "IN", "qtyMilli": 1000, "moveAt": "2099-01-01T10:00:00+05:30", "clientRef": _ref()})
    assert future.status_code == 400


def test_stock_is_private(client):
    shop_a = _account(client, SHOP_A)
    shop_b = _account(client, SHOP_B)
    customer = _account(client, "9988776655", roles=("CUSTOMER",))
    item = _item(client, shop_a, "Rice", openingMilli=1_000)
    for path in [f"/api/stock/items/{item['id']}"]:
        assert client.get(path, headers=shop_b).status_code == 404
        assert client.put(path, json={"name": "Mine"}, headers=shop_b).status_code == 404
    assert _move(client, shop_b, item["id"], "OUT", 1_000).status_code == 404
    assert client.post(f"/api/stock/items/{item['id']}/archive", headers=shop_b).status_code == 404
    assert client.get("/api/stock/items", headers=shop_b).json()["items"] == []
    assert client.get("/api/stock/items", headers=customer).status_code == 403
    assert client.get("/api/stock/items").status_code == 401
