"""Checklist & Notes: saving, retries, two phones, deleting, limits, privacy."""

import uuid
from datetime import datetime

from sqlalchemy import text

from app.customer import pages
from app.database import engine
from tests.test_calendar import _account
from tests.test_udhaar import RAMESH, SHOP_A

URL = "/api/customer/pages"
OTHER = "9000000001"


def _ref():
    return uuid.uuid4().hex


def _item(words, **extra):
    return {"ref": _ref(), "text": words, "qty": "", "done": False, **extra}


def _list(*items, base=0, **extra):
    return {"kind": "LIST", "title": " Groceries ", "items": list(items), "baseVersion": base,
            "saveRef": _ref(), **extra}


def _note(words, base=0, **extra):
    return {"kind": "NOTE", "title": "", "text": words, "baseVersion": base, "saveRef": _ref(), **extra}


def _put(client, who, ref, body):
    return client.put(f"{URL}/{ref}", json=body, headers=who)


def _all(client, who):
    return client.get(URL, headers=who).json()["pages"]


def _ramesh(client):
    return _account(client, RAMESH, roles=("CUSTOMER",))


def test_save_a_list_and_a_note(client):
    ramesh = _ramesh(client)
    one = _ref()
    made = _put(client, ramesh, one, _list(_item(" బియ్యం  ", qty=" 2  kg "), _item("Milk", done=True)))
    assert made.status_code == 200, made.text
    page = made.json()
    assert (page["title"], page["version"], page["kind"]) == ("Groceries", 1, "LIST")
    assert [(i["text"], i["qty"], i["done"]) for i in page["items"]] == [("బియ్యం", "2 kg", False), ("Milk", "", True)]
    _put(client, ramesh, _ref(), _note("Gas number\n 12345 ", pinned=True))
    notes, groceries = _all(client, ramesh)  # last changed first
    assert notes["text"] == "Gas number\n 12345 " and notes["pinned"] is True
    # The same moment, written in another time zone.
    assert datetime.fromisoformat(groceries.pop("updatedAt")) == datetime.fromisoformat(page.pop("updatedAt"))
    assert groceries == page


def test_a_save_sent_twice_counts_once(client):
    ramesh, ref = _ramesh(client), _ref()
    body = _list(_item("Rice"))
    _put(client, ramesh, ref, body)
    assert _put(client, ramesh, ref, body).json()["version"] == 1
    change = _list(_item("Rice"), _item("Dal"), base=1)
    assert _put(client, ramesh, ref, change).json()["version"] == 2
    assert _put(client, ramesh, ref, change).json()["version"] == 2
    assert len(_all(client, ramesh)) == 1


def test_another_phone_changed_it(client):
    ramesh, ref = _ramesh(client), _ref()
    _put(client, ramesh, ref, _list(_item("Rice")))
    _put(client, ramesh, ref, _list(_item("Rice"), _item("Dal"), base=1))
    late = _put(client, ramesh, ref, _list(_item("Rice", done=True), base=1))
    assert (late.status_code, late.json()["code"]) == (409, "PAGE_CHANGED")
    assert len(_all(client, ramesh)[0]["items"]) == 2
    # Never seen by the server, but the phone thinks it was.
    assert _put(client, ramesh, _ref(), _list(base=3)).status_code == 409


def test_a_deleted_page_stays_deleted_and_is_emptied(client):
    ramesh, ref = _ramesh(client), _ref()
    body = _note("Secret")
    _put(client, ramesh, ref, body)
    assert client.delete(f"{URL}/{ref}", headers=ramesh).status_code == 204
    assert client.delete(f"{URL}/{ref}", headers=ramesh).status_code == 204
    assert client.delete(f"{URL}/{_ref()}", headers=ramesh).status_code == 204
    assert _all(client, ramesh) == []
    assert _put(client, ramesh, ref, body).status_code == 409
    with engine.connect() as connection:
        assert connection.execute(text("SELECT text, title FROM customer_pages")).one() == ("", "")


def test_a_list_stays_a_list(client):
    ramesh, ref = _ramesh(client), _ref()
    _put(client, ramesh, ref, _list())
    assert _put(client, ramesh, ref, _note("x", base=1)).status_code == 400


def test_bad_pages_are_refused(client):
    ramesh = _ramesh(client)
    same = _item("Rice")
    for body in (
        _list(title="  "),
        _list(text="words"),
        _list(_item("  ")),
        _list(_item("x" * 121)),
        _list(_item("Rice", qty="1" * 31)),
        _list(same, same),
        _list(*[_item("Rice") for _ in range(201)]),
        _list(title="x" * 81),
        _list(base=-1),
        _note("  "),
        _note("x" * 10_001),
        _note("x", items=[_item("Rice")]),
        _note("x", saveRef="no"),
        _note("x", kind="OTHER"),
    ):
        assert _put(client, ramesh, _ref(), body).status_code == 400, body
    assert _put(client, ramesh, "a b!", _note("x")).status_code == 400
    assert _all(client, ramesh) == []


def test_characters_the_database_cannot_keep(client):
    ramesh = _ramesh(client)
    assert _put(client, ramesh, _ref(), _note("a\x00b")).json()["text"] == "ab"
    saved = _put(client, ramesh, _ref(), _list(_item("Ri\x00ce"), title="My\x00 list")).json()
    assert (saved["title"], saved["items"][0]["text"]) == ("My list", "Rice")
    assert _put(client, ramesh, _ref(), _list(_item("\x00"))).status_code == 400


def test_too_many(client, monkeypatch):
    ramesh = _ramesh(client)
    monkeypatch.setattr(pages, "MAX_PAGES", 1)
    ref = _ref()
    _put(client, ramesh, ref, _note("one"))
    assert _put(client, ramesh, _ref(), _note("two")).json()["code"] == "TOO_MANY_PAGES"
    assert _put(client, ramesh, ref, _note("one changed", base=1)).status_code == 200
    client.delete(f"{URL}/{ref}", headers=ramesh)
    assert _put(client, ramesh, _ref(), _note("two")).status_code == 200


def test_private_and_needs_the_customer_role(client):
    ramesh, ref = _ramesh(client), _ref()
    _put(client, ramesh, ref, _note("mine"))
    other = _account(client, OTHER, roles=("CUSTOMER",))
    assert _all(client, other) == []
    client.delete(f"{URL}/{ref}", headers=other)
    # The same id in another account is a different page.
    assert _put(client, other, ref, _note("theirs")).json()["version"] == 1
    assert _all(client, ramesh)[0]["text"] == "mine"
    shop = _account(client, SHOP_A)
    assert client.get(URL, headers=shop).status_code == 403
    assert _put(client, shop, _ref(), _note("x")).status_code == 403
    assert client.delete(f"{URL}/{ref}", headers=shop).status_code == 403
    assert client.get(URL).status_code == 401
