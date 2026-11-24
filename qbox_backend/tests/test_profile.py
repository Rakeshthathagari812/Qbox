"""Profile: details, photos (who sees them, what is kept), PIN change, logging out everywhere."""

import base64

import pytest

from app import ratelimit
from app.users import photos
from tests.test_auth import SHOP, SUPPLIER
from tests.test_calendar import _account
from tests.test_udhaar import RAMESH, SHOP_A, _add_customer

ALL = ("BUSINESS", "CUSTOMER", "SUPPLIER")


@pytest.fixture(autouse=True)
def _fresh_counts():
    ratelimit.forget()
    yield
    ratelimit.forget()


def _segment(marker, body):
    return bytes([0xFF, marker]) + (len(body) + 2).to_bytes(2, "big") + body


def _jpeg(wide=512, high=512, extra=b"", frame=0xC0):
    size = b"\x08" + high.to_bytes(2, "big") + wide.to_bytes(2, "big") + b"\x01\x01\x11\x00"
    return (b"\xff\xd8" + _segment(0xE0, b"JFIF\x00") + extra + _segment(0xDB, b"\x00" * 65)
            + _segment(frame, size) + _segment(0xC4, b"\x00" * 20) + _segment(0xDA, b"\x01\x01\x00\x00\x3f\x00")
            + b"picture" + b"\xff\xd9")


def _set(client, who, role="BUSINESS", jpeg=None):
    body = {"jpeg": base64.b64encode(_jpeg() if jpeg is None else jpeg).decode()}
    return client.put(f"/api/me/photo/{role}", json=body, headers=who)


def _me(client, who):
    return client.get("/api/me", headers=who).json()


# ---------- details ----------


def test_change_details(client):
    me = _account(client, SHOP_A, roles=ALL)
    shop = {**SHOP, "shopName": " New Name ", "shopCategory": "Grocery & Daily Needs", "contactNumber": "9000000009"}
    changed = client.put("/api/me/shop", json=shop, headers=me).json()["shop"]
    assert (changed["shopName"], changed["contactNumber"]) == ("New Name", "9000000009")
    assert changed["shopCategoryDetail"] is None  # kept only with "Other"
    client.put("/api/me/customer", json={"fullName": "Ravi", "email": "a@b.in", "address": " "}, headers=me)
    client.put("/api/me/supplier", json={**SUPPLIER, "productsSupplied": "Rice"}, headers=me)
    now = _me(client, me)
    assert (now["customer"]["fullName"], now["customer"]["email"], now["customer"]["address"]) == ("Ravi", "a@b.in", None)
    assert now["supplier"]["productsSupplied"] == "Rice"
    assert now["mobile"] == SHOP_A and now["shop"]["qboxId"] == changed["qboxId"]


def test_bad_details_are_refused(client):
    me = _account(client, SHOP_A, roles=ALL)
    for path, body in (
        ("shop", {**SHOP, "shopName": " "}),
        ("shop", {**SHOP, "shopCategory": "Other", "shopCategoryDetail": ""}),
        ("shop", {**SHOP, "contactNumber": "123"}),
        ("customer", {"fullName": "\x00"}),
        ("customer", {"fullName": "Ravi", "email": "nope"}),
        ("supplier", {**SUPPLIER, "businessType": "Other"}),
    ):
        assert client.put(f"/api/me/{path}", json=body, headers=me).status_code == 400, body
    only = _account(client, RAMESH, roles=("CUSTOMER",))
    assert client.put("/api/me/shop", json=SHOP, headers=only).status_code == 403
    assert client.put("/api/me/shop", json=SHOP).status_code == 401


# ---------- photos ----------


def test_photo_set_changed_and_removed(client):
    me = _account(client, SHOP_A, roles=ALL)
    first = _set(client, me).json()
    assert len(first["shop"]["photo"]) == 32 and first["customer"]["photo"] is None
    got = client.get(f"/api/photos/{first['shop']['photo']}", headers=me).json()["jpeg"]
    assert base64.b64decode(got) == _jpeg()
    second = _set(client, me).json()["shop"]["photo"]
    assert second != first["shop"]["photo"]
    assert client.get(f"/api/photos/{first['shop']['photo']}", headers=me).status_code == 404
    assert client.delete("/api/me/photo/BUSINESS", headers=me).json()["shop"]["photo"] is None
    assert client.delete("/api/me/photo/BUSINESS", headers=me).status_code == 200
    assert client.get(f"/api/photos/{second}", headers=me).status_code == 404


def test_who_sees_a_photo(client):
    shop = _account(client, SHOP_A, roles=ALL)
    _add_customer(client, shop)
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    shop_photo = _set(client, shop).json()["shop"]["photo"]
    own_photo = _set(client, shop, "CUSTOMER").json()["customer"]["photo"]
    book = client.get("/api/udhaar/mine", headers=ramesh).json()[0]
    assert book["shopPhoto"] == shop_photo
    pay = client.get("/api/payments/shops", headers=ramesh).json()["shops"][0]
    assert pay["shopPhoto"] == shop_photo
    assert client.get(f"/api/photos/{shop_photo}", headers=ramesh).status_code == 200
    assert client.get(f"/api/photos/{own_photo}", headers=ramesh).status_code == 404
    assert client.get(f"/api/photos/{own_photo}", headers=shop).status_code == 200
    assert client.get(f"/api/photos/{shop_photo}").status_code == 401
    assert client.get("/api/photos/not-a-ref", headers=shop).status_code == 400
    assert _set(client, ramesh, "BUSINESS").status_code == 403


def test_only_the_picture_is_kept():
    place = _segment(0xE1, b"Exif\x00\x00 17.3850 N 78.4867 E") + _segment(0xFE, b"my phone")
    assert photos.clean_jpeg(_jpeg(extra=place)) == _jpeg()
    assert photos.clean_jpeg(_jpeg() + b"hidden") == _jpeg()
    assert photos.clean_jpeg(_jpeg(frame=0xC2)) == _jpeg(frame=0xC2)


def test_bad_photos_are_refused(client):
    me = _account(client, SHOP_A)
    whole = _jpeg()
    for data in (b"", b"GIF89a", b"\xff\xd8", whole[:60], whole[:-2], _jpeg(wide=1025), _jpeg(high=0),
                 b"\xff\xd8" + _segment(0xDA, b"x") + b"\xff\xd9", b"\xff\xd8\xff\xe0\x00\x01",
                 whole + b"\xff\xd9" * 150_000):
        answer = _set(client, me, jpeg=data)
        assert (answer.status_code, answer.json()["code"]) == (400, "BAD_PHOTO"), data[:40]
    assert client.put("/api/me/photo/BUSINESS", json={"jpeg": "not base64!"}, headers=me).status_code == 400
    assert client.put("/api/me/photo/OWNER", json={"jpeg": ""}, headers=me).status_code == 400
    assert _me(client, me)["shop"]["photo"] is None


def test_too_many_photos(client, monkeypatch):
    me = _account(client, SHOP_A)
    monkeypatch.setattr(ratelimit, "PHOTOS_PER_HOUR", 1)
    assert _set(client, me).status_code == 200
    assert _set(client, me).status_code == 429


# ---------- PIN and logging out ----------


def _pin(client, who, old, new):
    return client.post("/api/me/pin", json={"oldPin": old, "newPin": new}, headers=who)


def _login(client, pin):
    return client.post("/api/auth/login", json={"mobile": SHOP_A, "pin": pin})


def test_change_pin(client):
    me = _account(client, SHOP_A)
    other_phone = {"Authorization": f"Bearer {_login(client, '4826').json()['accessToken']}"}
    changed = _pin(client, me, "4826", "7391")
    assert changed.status_code == 200, changed.text
    assert client.get("/api/me", headers=other_phone).status_code == 401
    assert client.get("/api/me", headers=me).status_code == 401  # the old token
    assert _me(client, {"Authorization": f"Bearer {changed.json()['accessToken']}"})["mobile"] == SHOP_A
    assert _login(client, "4826").status_code == 401
    assert _login(client, "7391").status_code == 200


def test_bad_pin_changes(client):
    me = _account(client, SHOP_A)
    assert _pin(client, me, "4826", "4826").json()["code"] == "SAME_PIN"
    assert _pin(client, me, "4826", "1234").status_code == 400
    assert _pin(client, me, "4826", "12").status_code == 400
    wrong = _pin(client, me, "1111", "7391")
    assert (wrong.status_code, wrong.json()["code"]) == (400, "WRONG_PIN")
    assert _login(client, "4826").status_code == 200


def test_guessing_the_old_pin_locks_the_account(client):
    me = _account(client, SHOP_A)
    answers = [_pin(client, me, "1111", "7391").status_code for _ in range(5)]
    assert answers[-1] == 423
    assert _pin(client, me, "4826", "7391").status_code == 423  # even the right one, for a while
    assert _login(client, "4826").status_code == 423


def test_log_out_from_all_phones(client):
    me = _account(client, SHOP_A)
    other_phone = {"Authorization": f"Bearer {_login(client, '4826').json()['accessToken']}"}
    assert client.post("/api/me/logout-all", headers=me).status_code == 204
    assert client.get("/api/me", headers=me).status_code == 401
    assert client.get("/api/me", headers=other_phone).status_code == 401
    assert _login(client, "4826").status_code == 200


# ---------- adding a role ----------


def _add_role(client, who, role, pin="4826", **details):
    return client.post("/api/me/roles", json={"role": role, "pin": pin, **details}, headers=who)


def test_add_a_role(client):
    me = _account(client, RAMESH, roles=("CUSTOMER",))
    assert client.get("/api/suppliers", headers=me).status_code == 403
    added = _add_role(client, me, "BUSINESS", shop={**SHOP, "contactNumber": RAMESH})
    assert added.status_code == 200, added.text
    now = _me(client, me)  # the same login still works
    assert now == added.json()
    assert now["roles"] == ["BUSINESS", "CUSTOMER"] and now["shop"]["qboxId"] == "QBM10001"
    assert now["customer"]["qboxId"] == "QBC10001"
    assert client.get("/api/suppliers", headers=me).status_code == 200
    # A retry changes nothing.
    again = _add_role(client, me, "BUSINESS", shop={**SHOP, "shopName": "Another"}).json()
    assert again == now
    _add_role(client, me, "SUPPLIER", supplier=SUPPLIER)
    assert _me(client, me)["roles"] == ["BUSINESS", "CUSTOMER", "SUPPLIER"]


def test_a_new_customer_role_shows_their_udhaar(client):
    shop = _account(client, SHOP_A)
    _add_customer(client, shop, mobile=RAMESH)
    ramesh = _account(client, RAMESH)
    assert client.get("/api/udhaar/mine", headers=ramesh).status_code == 403
    _add_role(client, ramesh, "CUSTOMER", customer={"fullName": "Ramesh", "mobileNumber": RAMESH})
    assert len(client.get("/api/udhaar/mine", headers=ramesh).json()) == 1


def test_adding_a_role_needs_the_pin_and_details(client):
    me = _account(client, RAMESH, roles=("CUSTOMER",))
    assert _add_role(client, me, "BUSINESS", pin="1111", shop=SHOP).json()["code"] == "WRONG_PIN"
    assert _add_role(client, me, "BUSINESS").json()["message"] == "Please fill in your shop details"
    assert _add_role(client, me, "BUSINESS", customer={"fullName": "x", "mobileNumber": RAMESH}).status_code == 400
    assert _add_role(client, me, "BUSINESS", shop={**SHOP, "shopCategoryDetail": ""}).status_code == 400
    assert _add_role(client, me, "OWNER", shop=SHOP).status_code == 400
    assert client.post("/api/me/roles", json={"role": "BUSINESS", "pin": "4826", "shop": SHOP}).status_code == 401
    assert _me(client, me)["roles"] == ["CUSTOMER"]


def test_guessing_the_pin_for_a_role_locks_the_account(client):
    me = _account(client, RAMESH, roles=("CUSTOMER",))
    assert [_add_role(client, me, "BUSINESS", pin="1111", shop=SHOP).status_code for _ in range(5)][-1] == 423
    assert _add_role(client, me, "BUSINESS", shop=SHOP).status_code == 423
