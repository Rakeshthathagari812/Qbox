"""Calendar API tests: events per role, ownership, checks, festivals."""

from tests.test_auth import CUSTOMER, SHOP, SUPPLIER


def _account(client, mobile, roles=("BUSINESS",)):
    """Signs up a user and returns the auth header."""
    sent = client.post("/api/auth/otp/send", json={"mobile": mobile, "purpose": "SIGNUP"}).json()
    token = client.post(
        "/api/auth/otp/verify", json={"mobile": mobile, "purpose": "SIGNUP", "otp": sent["devOtp"]}
    ).json()["verificationToken"]
    body = {"verificationToken": token, "pin": "4826", "roles": list(roles)}
    if "BUSINESS" in roles:
        body["shop"] = {**SHOP, "contactNumber": mobile}
    if "CUSTOMER" in roles:
        body["customer"] = {**CUSTOMER, "mobileNumber": mobile}
    if "SUPPLIER" in roles:
        body["supplier"] = {**SUPPLIER, "contactNumber": mobile}
    response = client.post("/api/auth/register", json=body)
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


EVENT = {
    "role": "BUSINESS",
    "title": "  Supplier payment  ",
    "category": "PAYMENT",
    "day": "2026-11-25",
    "time": "10:30",
    "repeat": "MONTHLY",
    "remindMinutes": 60,
    "note": "Ravi Traders",
}


def test_create_list_update_delete(client):
    me = _account(client, "9876543210")
    created = client.post("/api/calendar/events", json=EVENT, headers=me)
    assert created.status_code == 201, created.text
    event = created.json()
    assert event["title"] == "Supplier payment"  # spaces trimmed
    assert event["time"] == "10:30:00"
    assert event["remindMinutes"] == 60

    listed = client.get("/api/calendar/events?role=BUSINESS", headers=me).json()
    assert [e["id"] for e in listed] == [event["id"]]

    changed = client.put(f"/api/calendar/events/{event['id']}",
                         json={**EVENT, "title": "Rent", "time": None, "repeat": "NONE"}, headers=me)
    assert changed.status_code == 200
    assert changed.json()["title"] == "Rent"
    assert changed.json()["time"] is None  # all day

    assert client.delete(f"/api/calendar/events/{event['id']}", headers=me).status_code == 204
    assert client.get("/api/calendar/events?role=BUSINESS", headers=me).json() == []


def test_nobody_sees_or_changes_another_users_events(client):
    owner = _account(client, "9876543210")
    stranger = _account(client, "9123456780")
    event_id = client.post("/api/calendar/events", json=EVENT, headers=owner).json()["id"]

    assert client.get("/api/calendar/events?role=BUSINESS", headers=stranger).json() == []
    for response in (
        client.put(f"/api/calendar/events/{event_id}", json=EVENT, headers=stranger),
        client.delete(f"/api/calendar/events/{event_id}", headers=stranger),
    ):
        assert response.status_code == 404
        assert response.json()["code"] == "EVENT_NOT_FOUND"
    # Still there for the owner.
    assert len(client.get("/api/calendar/events?role=BUSINESS", headers=owner).json()) == 1


def test_shop_and_customer_calendars_are_separate(client):
    me = _account(client, "9876543210", roles=("BUSINESS", "CUSTOMER"))
    client.post("/api/calendar/events", json=EVENT, headers=me)
    client.post("/api/calendar/events", json={**EVENT, "role": "CUSTOMER", "title": "Doctor"}, headers=me)
    shop = client.get("/api/calendar/events?role=BUSINESS", headers=me).json()
    personal = client.get("/api/calendar/events?role=CUSTOMER", headers=me).json()
    assert [e["title"] for e in shop] == ["Supplier payment"]
    assert [e["title"] for e in personal] == ["Doctor"]


def test_role_must_belong_to_the_account(client):
    shop_only = _account(client, "9876543210")
    response = client.post("/api/calendar/events", json={**EVENT, "role": "SUPPLIER"}, headers=shop_only)
    assert response.status_code == 403
    assert response.json()["code"] == "ROLE_NOT_HELD"
    assert client.get("/api/calendar/events?role=SUPPLIER", headers=shop_only).status_code == 403


def test_input_checks(client):
    me = _account(client, "9876543210")
    cases = [
        ({**EVENT, "title": "   "}, "Enter a title"),
        ({**EVENT, "day": "1990-01-01"}, "Choose a date between 2000 and 2100"),
        ({**EVENT, "remindMinutes": 20000}, None),
        ({**EVENT, "category": "PARTY"}, None),
        ({**EVENT, "title": "x" * 121}, None),
    ]
    for body, message in cases:
        response = client.post("/api/calendar/events", json=body, headers=me)
        assert response.status_code == 400, body
        assert response.json()["code"] == "INVALID_INPUT"
        if message:
            assert response.json()["message"] == message


def test_calendar_needs_login(client):
    assert client.get("/api/calendar/events?role=BUSINESS").status_code == 401
    assert client.get("/api/calendar/festivals").status_code == 401
    assert client.post("/api/calendar/events", json=EVENT).status_code == 401


def test_events_come_back_in_date_order(client):
    me = _account(client, "9876543210")
    for day, time in (("2026-12-01", "09:00"), ("2026-11-20", None), ("2026-11-20", "08:00")):
        client.post("/api/calendar/events", json={**EVENT, "day": day, "time": time}, headers=me)
    listed = client.get("/api/calendar/events?role=BUSINESS", headers=me).json()
    assert [(e["day"], e["time"]) for e in listed] == [
        ("2026-11-20", None), ("2026-11-20", "08:00:00"), ("2026-12-01", "09:00:00"),
    ]


def test_festivals_include_telugu_and_all_india(client):
    me = _account(client, "9876543210")
    festivals = client.get("/api/calendar/festivals", headers=me).json()
    by_name = {(f["day"], f["name"]): f["region"] for f in festivals}
    assert by_name[("2026-03-19", "Ugadi")] == "TELUGU"
    assert by_name[("2026-11-08", "Deepavali")] == "ALL"
    assert by_name[("2027-01-15", "Makar Sankranti / Pongal")] == "ALL"
    assert [f["day"] for f in festivals] == sorted(f["day"] for f in festivals)


def test_deleting_an_account_deletes_its_events(client):
    from sqlalchemy import text

    from app.database import engine

    me = _account(client, "9876543210")
    client.post("/api/calendar/events", json=EVENT, headers=me)
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM users"))
        assert connection.execute(text("SELECT count(*) FROM calendar_events")).scalar_one() == 0
