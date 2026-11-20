"""Udhaar API tests: adding customers with OTP, entries and balances, privacy
between shops, the customer's own view, checks and limits."""

import uuid

from sqlalchemy import text

from app.config import get_settings
from app.database import engine
from tests.test_calendar import _account

SHOP_A = "9876543210"
SHOP_B = "9123456780"
RAMESH = "9988776655"


def _add_customer(client, shop, mobile=RAMESH, name="Ramesh", limit=None):
    sent = client.post("/api/udhaar/customers/otp", json={"name": name, "mobile": mobile}, headers=shop)
    assert sent.status_code == 200, sent.text
    body = {"name": name, "mobile": mobile, "otp": sent.json()["devOtp"]}
    if limit is not None:
        body["creditLimitPaise"] = limit
    added = client.post("/api/udhaar/customers", json=body, headers=shop)
    assert added.status_code == 201, added.text
    return added.json()


def _entry(kind, rupees, note=None, at="2026-11-19T10:00:00+05:30", ref=None):
    return {
        "kind": kind,
        "amountPaise": rupees * 100,
        "note": note,
        "entryAt": at,
        "clientRef": ref or str(uuid.uuid4()),
    }


def _post_entry(client, shop, customer_id, entry):
    return client.post(f"/api/udhaar/customers/{customer_id}/entries", json=entry, headers=shop)


def test_add_customer_with_otp_then_credit_and_payment(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop, limit=200000)
    assert customer["name"] == "Ramesh"
    assert customer["balancePaise"] == 0
    assert customer["creditLimitPaise"] == 200000

    assert _post_entry(client, shop, customer["id"], _entry("CREDIT", 250, "rice 5 kg")).status_code == 201
    assert _post_entry(client, shop, customer["id"], _entry("PAYMENT", 100)).status_code == 201

    detail = client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop).json()
    assert detail["customer"]["balancePaise"] == 15000
    assert [e["kind"] for e in detail["entries"]] == ["PAYMENT", "CREDIT"]  # newest first
    assert {e["note"] for e in detail["entries"]} == {"rice 5 kg", None}

    book = client.get("/api/udhaar/customers", headers=shop).json()
    assert book["totalPendingPaise"] == 15000
    assert [c["name"] for c in book["customers"]] == ["Ramesh"]


def test_wrong_code_and_another_shops_code_do_not_work(client):
    shop_a = _account(client, SHOP_A)
    shop_b = _account(client, SHOP_B)
    code = client.post("/api/udhaar/customers/otp",
                       json={"name": "Ramesh", "mobile": RAMESH}, headers=shop_a).json()["devOtp"]

    wrong = "000000" if code != "000000" else "111111"
    response = client.post("/api/udhaar/customers",
                           json={"name": "Ramesh", "mobile": RAMESH, "otp": wrong}, headers=shop_a)
    assert response.json()["code"] == "OTP_WRONG"

    # Shop B never asked for a code, so shop A's code is useless to it.
    response = client.post("/api/udhaar/customers",
                           json={"name": "Ramesh", "mobile": RAMESH, "otp": code}, headers=shop_b)
    assert response.json()["code"] == "OTP_NOT_FOUND"

    # Shop A's code still works for shop A.
    response = client.post("/api/udhaar/customers",
                           json={"name": "Ramesh", "mobile": RAMESH, "otp": code}, headers=shop_a)
    assert response.status_code == 201


def test_cannot_add_own_number_or_same_customer_twice(client):
    shop = _account(client, SHOP_A)
    response = client.post("/api/udhaar/customers/otp", json={"name": "Me", "mobile": SHOP_A}, headers=shop)
    assert response.json()["code"] == "OWN_NUMBER"

    _add_customer(client, shop)
    response = client.post("/api/udhaar/customers/otp", json={"name": "R", "mobile": RAMESH}, headers=shop)
    assert response.status_code == 409
    assert response.json()["message"] == "Ramesh is already in your udhaar book with this number"


def test_sms_names_the_shop_and_warns_about_phone_calls(client, monkeypatch):
    shop = _account(client, SHOP_A)
    sent = []
    monkeypatch.setattr("app.auth.otp.send_sms", lambda mobile, message: sent.append((mobile, message)))
    code = client.post("/api/udhaar/customers/otp",
                       json={"name": "Ramesh", "mobile": RAMESH}, headers=shop).json()["devOtp"]
    [(mobile, sms)] = sent
    assert mobile == RAMESH
    assert sms.startswith(code)
    assert "Sri Balaji Kirana" in sms
    assert "udhaar book" in sms
    assert "Never share it on a phone call" in sms


def test_shops_never_see_or_touch_each_others_book(client):
    shop_a = _account(client, SHOP_A)
    shop_b = _account(client, SHOP_B)
    customer = _add_customer(client, shop_a)
    entry = _post_entry(client, shop_a, customer["id"], _entry("CREDIT", 500)).json()

    assert client.get("/api/udhaar/customers", headers=shop_b).json()["customers"] == []
    for response in (
        client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop_b),
        client.put(f"/api/udhaar/customers/{customer['id']}", json={"name": "X"}, headers=shop_b),
        _post_entry(client, shop_b, customer["id"], _entry("PAYMENT", 500)),
    ):
        assert response.status_code == 404
        assert response.json()["code"] == "CUSTOMER_NOT_FOUND"
    response = client.post(f"/api/udhaar/entries/{entry['id']}/delete", json={"reason": "x"}, headers=shop_b)
    assert response.status_code == 404
    assert response.json()["code"] == "ENTRY_NOT_FOUND"

    # Untouched for shop A.
    detail = client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop_a).json()
    assert detail["customer"]["balancePaise"] == 50000
    assert detail["entries"][0]["deletedAt"] is None


def test_same_entry_sent_twice_is_kept_once(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    entry = _entry("CREDIT", 250, ref="phone-entry-0001")
    first = _post_entry(client, shop, customer["id"], entry).json()
    again = _post_entry(client, shop, customer["id"], entry).json()
    assert first["id"] == again["id"]
    detail = client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop).json()
    assert len(detail["entries"]) == 1
    assert detail["customer"]["balancePaise"] == 25000


def test_deleted_entry_stays_in_history_but_not_in_balance(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    keep = _post_entry(client, shop, customer["id"], _entry("CREDIT", 300)).json()
    wrong = _post_entry(client, shop, customer["id"], _entry("CREDIT", 3000)).json()

    response = client.post(f"/api/udhaar/entries/{wrong['id']}/delete", json={"reason": "   "}, headers=shop)
    assert response.json()["message"] == "Write why this entry is being deleted"

    deleted = client.post(f"/api/udhaar/entries/{wrong['id']}/delete",
                          json={"reason": " typed extra zero "}, headers=shop).json()
    assert deleted["deletedAt"] is not None
    assert deleted["deleteReason"] == "typed extra zero"
    # Deleting again changes nothing.
    again = client.post(f"/api/udhaar/entries/{wrong['id']}/delete", json={"reason": "other"}, headers=shop).json()
    assert again["deleteReason"] == "typed extra zero"

    detail = client.get(f"/api/udhaar/customers/{customer['id']}", headers=shop).json()
    assert detail["customer"]["balancePaise"] == 30000
    assert {e["id"] for e in detail["entries"]} == {keep["id"], wrong["id"]}


def test_customer_sees_own_udhaar_in_every_shop_read_only(client):
    shop_a = _account(client, SHOP_A)
    shop_b = _account(client, SHOP_B)
    a = _add_customer(client, shop_a)
    b = _add_customer(client, shop_b, name="Ramesh K")
    _post_entry(client, shop_a, a["id"], _entry("CREDIT", 350))
    _post_entry(client, shop_b, b["id"], _entry("CREDIT", 120))

    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    books = client.get("/api/udhaar/mine", headers=ramesh).json()
    assert [b["balancePaise"] for b in books] == [35000, 12000]
    assert books[0]["shopName"] == "Sri Balaji Kirana"

    detail = client.get(f"/api/udhaar/mine/{a['id']}", headers=ramesh).json()
    assert detail["book"]["balancePaise"] == 35000
    assert len(detail["entries"]) == 1

    # The customer cannot use the shop's endpoints (no shop role) ...
    assert client.get(f"/api/udhaar/customers/{a['id']}", headers=ramesh).status_code == 403
    # ... and another customer sees none of it.
    other = _account(client, "9000000001", roles=("CUSTOMER",))
    assert client.get("/api/udhaar/mine", headers=other).json() == []
    assert client.get(f"/api/udhaar/mine/{a['id']}", headers=other).status_code == 404


def _dispute(client, shop):
    return client.get("/api/udhaar/customers", headers=shop).json()["customers"][0]["dispute"]


def test_not_me_is_only_a_report_until_the_shop_decides(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 250))
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    book_id = customer["id"]

    reported = client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=ramesh)
    assert reported.status_code == 200
    assert reported.json()["dispute"] == "REPORTED"
    assert reported.json()["verifiedAt"]  # shown to the customer: checked by code at the shop
    # Nothing is hidden, nothing changes in the balance.
    books = client.get("/api/udhaar/mine", headers=ramesh).json()
    assert [(b["dispute"], b["balancePaise"]) for b in books] == [("REPORTED", 25000)]
    assert _dispute(client, shop) == "REPORTED"

    # The customer can take it back while the shop has not decided.
    cancelled = client.post(f"/api/udhaar/mine/{book_id}/not-me/cancel", headers=ramesh)
    assert cancelled.json()["dispute"] == "NONE"
    assert _dispute(client, shop) == "NONE"


def test_shop_confirms_the_number_and_the_customer_cannot_report_again(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    book_id = customer["id"]

    # Nothing reported yet: nothing to confirm.
    response = client.post(f"/api/udhaar/customers/{book_id}/dispute/confirm", headers=shop)
    assert response.status_code == 409
    assert response.json()["code"] == "NO_DISPUTE"

    client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=ramesh)
    confirmed = client.post(f"/api/udhaar/customers/{book_id}/dispute/confirm", headers=shop)
    assert confirmed.json()["dispute"] == "CONFIRMED"

    assert client.get("/api/udhaar/mine", headers=ramesh).json()[0]["dispute"] == "CONFIRMED"
    again = client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=ramesh)
    assert again.status_code == 409
    assert again.json()["code"] == "DISPUTE_CLOSED"
    # Cancelling does not undo the shop's decision either.
    client.post(f"/api/udhaar/mine/{book_id}/not-me/cancel", headers=ramesh)
    assert _dispute(client, shop) == "CONFIRMED"


def test_shop_unlinks_then_moves_the_history_to_the_right_number(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 400))
    wrong = _account(client, RAMESH, roles=("CUSTOMER",))
    book_id = customer["id"]

    client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=wrong)
    unlinked = client.post(f"/api/udhaar/customers/{book_id}/dispute/unlink", headers=shop)
    assert unlinked.json()["dispute"] == "UNLINKED"
    assert unlinked.json()["balancePaise"] == 40000  # the shop keeps everything
    assert client.get("/api/udhaar/mine", headers=wrong).json() == []
    assert client.get(f"/api/udhaar/mine/{book_id}", headers=wrong).status_code == 404

    # The real customer's number, checked with a new code.
    right = "9000000005"
    sent = client.post(f"/api/udhaar/customers/{book_id}/number/otp", json={"mobile": right}, headers=shop)
    assert sent.status_code == 200
    moved = client.post(f"/api/udhaar/customers/{book_id}/number",
                        json={"mobile": right, "otp": sent.json()["devOtp"]}, headers=shop).json()
    assert moved["mobile"] == right
    assert moved["dispute"] == "NONE"
    assert moved["balancePaise"] == 40000

    real = _account(client, right, roles=("CUSTOMER",))
    assert [b["balancePaise"] for b in client.get("/api/udhaar/mine", headers=real).json()] == [40000]


def test_change_number_checks(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    other = _add_customer(client, shop, mobile="9000000006", name="Other")
    path = f"/api/udhaar/customers/{customer['id']}/number/otp"
    cases = [(RAMESH, "SAME_NUMBER"), (SHOP_A, "OWN_NUMBER"), (other["mobile"], "CUSTOMER_EXISTS")]
    for mobile, code in cases:
        assert client.post(path, json={"mobile": mobile}, headers=shop).json()["code"] == code
    # A code sent to the new number cannot be faked.
    client.post(path, json={"mobile": "9000000007"}, headers=shop)
    response = client.post(f"/api/udhaar/customers/{customer['id']}/number",
                           json={"mobile": "9000000007", "otp": "000000"}, headers=shop)
    assert response.json()["code"] in {"OTP_WRONG"}


def test_only_the_right_people_can_report_or_decide(client):
    shop_a = _account(client, SHOP_A)
    shop_b = _account(client, SHOP_B)
    customer = _add_customer(client, shop_a)
    ramesh = _account(client, RAMESH, roles=("CUSTOMER",))
    book_id = customer["id"]
    client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=ramesh)

    # Another shop cannot decide; the customer cannot decide their own report.
    assert client.post(f"/api/udhaar/customers/{book_id}/dispute/unlink", headers=shop_b).status_code == 404
    assert client.post(f"/api/udhaar/customers/{book_id}/dispute/confirm", headers=ramesh).status_code == 403
    # Another person cannot report someone else's book.
    stranger = _account(client, "9000000008", roles=("CUSTOMER",))
    assert client.post(f"/api/udhaar/mine/{book_id}/not-me", headers=stranger).status_code == 404
    assert _dispute(client, shop_a) == "REPORTED"


def test_roles_are_checked(client):
    customer_only = _account(client, "9000000001", roles=("CUSTOMER",))
    shop_only = _account(client, SHOP_A)
    assert client.get("/api/udhaar/customers", headers=customer_only).json()["code"] == "ROLE_NOT_HELD"
    assert client.post("/api/udhaar/customers/otp", json={"name": "R", "mobile": RAMESH},
                       headers=customer_only).status_code == 403
    assert client.get("/api/udhaar/mine", headers=shop_only).status_code == 403


def test_input_checks(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    cases = [
        ({**_entry("CREDIT", 1), "amountPaise": 0}, None),
        ({**_entry("CREDIT", 1), "amountPaise": -500}, None),
        ({**_entry("CREDIT", 1), "amountPaise": 100_000_001}, None),
        (_entry("CREDIT", 10, at="2099-01-01T10:00:00+05:30"), "The date cannot be in the future"),
        (_entry("CREDIT", 10, at="1999-01-01T10:00:00+05:30"), "Choose a date after the year 2000"),
        (_entry("CREDIT", 10, ref="bad ref!"), None),
        ({**_entry("CREDIT", 10), "kind": "GIFT"}, None),
        (_entry("CREDIT", 10, note="x" * 201), None),
    ]
    for body, message in cases:
        response = _post_entry(client, shop, customer["id"], body)
        assert response.status_code == 400, body
        assert response.json()["code"] == "INVALID_INPUT"
        if message:
            assert response.json()["message"] == message

    for body in ({"name": "  ", "mobile": "9000000002"}, {"name": "R", "mobile": "12345"}):
        response = client.post("/api/udhaar/customers/otp", json=body, headers=shop)
        assert response.status_code == 400


def test_login_otp_endpoint_cannot_send_udhaar_codes(client):
    for path, extra in (("/api/auth/otp/send", {}), ("/api/auth/otp/verify", {"otp": "123456"})):
        response = client.post(path, json={"mobile": RAMESH, "purpose": "UDHAAR_ADD", **extra})
        assert response.status_code == 400
        assert response.json()["code"] == "INVALID_INPUT"


def test_shop_invite_limit_per_hour(client, monkeypatch):
    shop = _account(client, SHOP_A)
    monkeypatch.setattr(get_settings(), "udhaar_invites_per_hour", 2)
    for i in range(2):
        mobile = f"900000001{i}"
        assert client.post("/api/udhaar/customers/otp",
                           json={"name": "C", "mobile": mobile}, headers=shop).status_code == 200
    response = client.post("/api/udhaar/customers/otp", json={"name": "C", "mobile": "9000000019"}, headers=shop)
    assert response.status_code == 429
    assert response.json()["code"] == "INVITE_LIMIT"


def test_udhaar_codes_never_block_the_persons_own_login_otp(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "otp_resend_seconds", 0)
    shop = _account(client, SHOP_A)
    for _ in range(get_settings().otp_max_per_hour):
        client.post("/api/udhaar/customers/otp", json={"name": "R", "mobile": RAMESH}, headers=shop)
    # Ramesh can still sign up himself.
    response = client.post("/api/auth/otp/send", json={"mobile": RAMESH, "purpose": "SIGNUP"})
    assert response.status_code == 200


def test_overdue_date_and_order_by_amount(client):
    shop = _account(client, SHOP_A)
    small = _add_customer(client, shop, mobile="9000000003", name="Small")
    big = _add_customer(client, shop, mobile="9000000004", name="Big")
    _post_entry(client, shop, small["id"], _entry("CREDIT", 100, at="2026-09-01T10:00:00+05:30"))
    _post_entry(client, shop, big["id"], _entry("CREDIT", 900, at="2026-10-01T10:00:00+05:30"))
    _post_entry(client, shop, big["id"], _entry("PAYMENT", 100, at="2026-11-01T10:00:00+05:30"))

    customers = client.get("/api/udhaar/customers", headers=shop).json()["customers"]
    assert [c["name"] for c in customers] == ["Big", "Small"]
    assert customers[0]["owingSince"].startswith("2026-11-01")  # last payment
    assert customers[1]["owingSince"].startswith("2026-09-01")  # never paid: first udhaar

    # Fully paid: nothing owed, no date.
    _post_entry(client, shop, small["id"], _entry("PAYMENT", 100))
    customers = client.get("/api/udhaar/customers", headers=shop).json()["customers"]
    assert customers[1]["balancePaise"] == 0
    assert customers[1]["owingSince"] is None


def test_change_name_and_limit(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    changed = client.put(f"/api/udhaar/customers/{customer['id']}",
                         json={"name": " Ramesh Kumar ", "creditLimitPaise": 500000}, headers=shop).json()
    assert changed["name"] == "Ramesh Kumar"
    assert changed["creditLimitPaise"] == 500000
    cleared = client.put(f"/api/udhaar/customers/{customer['id']}",
                         json={"name": "Ramesh Kumar", "creditLimitPaise": None}, headers=shop).json()
    assert cleared["creditLimitPaise"] is None


def test_udhaar_needs_login(client):
    assert client.get("/api/udhaar/customers").status_code == 401
    assert client.get("/api/udhaar/mine").status_code == 401


def test_deleting_a_shop_account_deletes_its_book(client):
    shop = _account(client, SHOP_A)
    customer = _add_customer(client, shop)
    _post_entry(client, shop, customer["id"], _entry("CREDIT", 100))
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM users"))
        assert connection.execute(text("SELECT count(*) FROM udhaar_customers")).scalar_one() == 0
        assert connection.execute(text("SELECT count(*) FROM udhaar_entries")).scalar_one() == 0
