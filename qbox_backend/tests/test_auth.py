"""End-to-end tests of every auth API against a real PostgreSQL test database."""

from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from app.database import engine

MOBILE = "9876543210"

SHOP = {
    "shopName": "Sri Balaji Kirana",
    "businessType": "Retail",
    "shopCategory": "Other",
    "shopCategoryDetail": "Kirana & Dairy",
    "address": "Bandlaguda, Hyderabad",
    "contactNumber": MOBILE,
}
CUSTOMER = {"fullName": "Ramu", "mobileNumber": MOBILE, "email": "", "address": "", "aadhaarLinkRequested": True}
SUPPLIER = {
    "supplierName": "Ramu Traders",
    "businessType": "Wholesale",
    "productsSupplied": "FMCG",
    "contactNumber": MOBILE,
    "address": "Jeedimetla",
}


def _verify(client, mobile=MOBILE, purpose="SIGNUP"):
    sent = client.post("/api/auth/otp/send", json={"mobile": mobile, "purpose": purpose})
    assert sent.status_code == 200, sent.text
    otp = sent.json()["devOtp"]
    verified = client.post("/api/auth/otp/verify", json={"mobile": mobile, "purpose": purpose, "otp": otp})
    assert verified.status_code == 200, verified.text
    return verified.json()["verificationToken"]


def _register(client, roles=("BUSINESS", "CUSTOMER", "SUPPLIER"), pin="4826"):
    body = {"verificationToken": _verify(client), "pin": pin, "roles": list(roles)}
    if "BUSINESS" in roles:
        body["shop"] = SHOP
    if "CUSTOMER" in roles:
        body["customer"] = CUSTOMER
    if "SUPPLIER" in roles:
        body["supplier"] = SUPPLIER
    response = client.post("/api/auth/register", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def test_health(client):
    assert client.get("/health").json() == {"status": "UP"}


def test_send_otp_returns_code_in_test_mode(client):
    response = client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"})
    body = response.json()
    assert response.status_code == 200
    assert body["mobile"] == MOBILE
    assert body["expiresInSeconds"] == 300
    assert body["resendInSeconds"] == 30
    assert len(body["devOtp"]) == 6 and body["devOtp"].isdigit()


def test_otp_is_stored_only_as_a_hash(client):
    code = client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"}).json()["devOtp"]
    with engine.connect() as connection:
        stored = connection.execute(text("SELECT code_hash FROM otp_codes")).scalar_one()
    assert stored.startswith("$2") and code not in stored


def test_resend_too_soon_is_refused(client):
    client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"})
    response = client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"})
    assert response.status_code == 429
    assert response.json()["code"] == "OTP_TOO_SOON"


def test_wrong_otp_and_attempt_limit(client):
    client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"})
    wrong = {"mobile": MOBILE, "purpose": "SIGNUP", "otp": "000000"}
    first = client.post("/api/auth/otp/verify", json=wrong)
    assert first.status_code == 400
    assert first.json() == {"code": "OTP_WRONG", "message": "Wrong OTP. Please check and try again"}
    for _ in range(4):
        client.post("/api/auth/otp/verify", json=wrong)
    blocked = client.post("/api/auth/otp/verify", json=wrong)
    assert blocked.status_code == 429
    assert blocked.json()["code"] == "OTP_TOO_MANY_ATTEMPTS"


def test_expired_otp_is_refused(client):
    code = client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"}).json()["devOtp"]
    with engine.begin() as connection:
        connection.execute(text("UPDATE otp_codes SET expires_at = :t"),
                           {"t": datetime.now(UTC) - timedelta(seconds=1)})
    response = client.post("/api/auth/otp/verify", json={"mobile": MOBILE, "purpose": "SIGNUP", "otp": code})
    assert response.status_code == 400
    assert response.json()["code"] == "OTP_EXPIRED"


def test_otp_can_be_used_only_once(client):
    code = client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"}).json()["devOtp"]
    body = {"mobile": MOBILE, "purpose": "SIGNUP", "otp": code}
    assert client.post("/api/auth/otp/verify", json=body).status_code == 200
    again = client.post("/api/auth/otp/verify", json=body)
    assert again.status_code == 400
    assert again.json()["code"] == "OTP_NOT_FOUND"


def test_validation_messages_are_for_people(client):
    bad_mobile = client.post("/api/auth/otp/send", json={"mobile": "12345", "purpose": "SIGNUP"})
    assert bad_mobile.status_code == 400
    assert bad_mobile.json() == {"code": "INVALID_INPUT", "message": "Enter a 10-digit mobile number"}

    bad_pin = client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "12"})
    assert bad_pin.json()["message"] == "Enter a 4-digit PIN"


def test_register_creates_all_profiles(client):
    body = _register(client)
    user = body["user"]
    assert body["accessToken"]
    assert user["id"] == 1
    assert user["mobile"] == MOBILE
    assert user["roles"] == ["BUSINESS", "CUSTOMER", "SUPPLIER"]
    assert user["shop"] == {**SHOP, "qboxId": "QBM10001", "businessTypeDetail": None}
    assert user["customer"] == {
        "qboxId": "QBC10001", "fullName": "Ramu", "mobileNumber": MOBILE,
        "email": None, "address": None, "aadhaarLinkRequested": True,
    }
    assert user["supplier"]["qboxId"] == "QBS10001"
    assert user["supplier"]["businessTypeDetail"] is None


def test_pin_is_stored_only_as_a_hash(client):
    _register(client, pin="4826")
    with engine.connect() as connection:
        stored = connection.execute(text("SELECT pin_hash FROM users")).scalar_one()
    assert stored.startswith("$2") and "4826" not in stored


def test_register_needs_details_for_each_role(client):
    body = {"verificationToken": _verify(client), "pin": "4826", "roles": ["BUSINESS"]}
    response = client.post("/api/auth/register", json=body)
    assert response.status_code == 400
    assert response.json()["message"] == "Please fill in your shop details"

    body["shop"] = {**SHOP, "shopCategoryDetail": ""}
    response = client.post("/api/auth/register", json=body)
    assert response.json()["message"] == "Enter your shop category"


def test_failed_register_saves_nothing(client):
    body = {"verificationToken": _verify(client), "pin": "4826", "roles": ["BUSINESS"]}
    client.post("/api/auth/register", json=body)
    with engine.connect() as connection:
        assert connection.execute(text("SELECT count(*) FROM users")).scalar_one() == 0


def test_mobile_can_register_only_once(client):
    _register(client)
    send = client.post("/api/auth/otp/send", json={"mobile": MOBILE, "purpose": "SIGNUP"})
    assert send.status_code == 409
    assert send.json()["code"] == "MOBILE_REGISTERED"


def test_register_rejects_a_bad_token(client):
    body = {"verificationToken": "not-a-token", "pin": "4826", "roles": ["CUSTOMER"], "customer": CUSTOMER}
    response = client.post("/api/auth/register", json=body)
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_INVALID"


def test_login_and_me(client):
    _register(client, roles=("CUSTOMER",))
    wrong = client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "1111"})
    assert wrong.status_code == 401
    assert wrong.json() == {"code": "LOGIN_FAILED", "message": "Mobile number or PIN does not match"}

    ok = client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "4826"})
    assert ok.status_code == 200
    token = ok.json()["accessToken"]
    assert ok.json()["user"]["roles"] == ["CUSTOMER"]

    me = client.get("/api/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["customer"]["qboxId"] == "QBC10001"
    assert me.json()["shop"] is None


def test_me_needs_a_valid_token(client):
    assert client.get("/api/me").json()["code"] == "TOKEN_MISSING"
    bad = client.get("/api/me", headers={"Authorization": "Bearer abc.def.ghi"})
    assert bad.status_code == 401
    assert bad.json()["code"] == "TOKEN_INVALID"


def test_unknown_mobile_cannot_log_in(client):
    response = client.post("/api/auth/login", json={"mobile": "9000000000", "pin": "1234"})
    assert response.status_code == 401
    assert response.json()["code"] == "LOGIN_FAILED"


def test_five_wrong_pins_lock_the_account(client):
    _register(client, roles=("CUSTOMER",))
    for _ in range(4):
        assert client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "0000"}).status_code == 401
    locked = client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "0000"})
    assert locked.status_code == 423
    assert locked.json()["code"] == "ACCOUNT_LOCKED"
    right_pin = client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "4826"})
    assert right_pin.status_code == 423


def test_reset_pin(client):
    _register(client, roles=("CUSTOMER",))
    unknown = client.post("/api/auth/otp/send", json={"mobile": "9000000000", "purpose": "RESET_PIN"})
    assert unknown.status_code == 404
    assert unknown.json()["code"] == "MOBILE_NOT_FOUND"

    token = _verify(client, purpose="RESET_PIN")
    response = client.post("/api/auth/pin/reset", json={"verificationToken": token, "newPin": "7391"})
    assert response.status_code == 204

    assert client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "4826"}).status_code == 401
    assert client.post("/api/auth/login", json={"mobile": MOBILE, "pin": "7391"}).status_code == 200


def test_signup_token_cannot_reset_pin(client):
    signup_token = _verify(client)
    response = client.post("/api/auth/pin/reset", json={"verificationToken": signup_token, "newPin": "7391"})
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_INVALID"


# --- Extra protections ---------------------------------------------------------

def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _login(client, pin="4826"):
    return client.post("/api/auth/login", json={"mobile": MOBILE, "pin": pin})


def _age_otps(seconds):
    with engine.begin() as connection:
        connection.execute(text("UPDATE otp_codes SET created_at = created_at - make_interval(secs => :s)"),
                           {"s": seconds})


def _end_lock():
    with engine.begin() as connection:
        connection.execute(text("UPDATE users SET locked_until = now() - interval '1 second'"))


def test_easy_pins_are_refused(client):
    token = _verify(client)
    for pin in ("1111", "1234", "9876"):
        body = {"verificationToken": token, "pin": pin, "roles": ["CUSTOMER"], "customer": CUSTOMER}
        response = client.post("/api/auth/register", json=body)
        assert response.status_code == 400
        assert response.json()["message"] == "This PIN is too easy to guess. Choose a different PIN"
    # Refused tries do not use up the verification.
    body = {"verificationToken": token, "pin": "4826", "roles": ["CUSTOMER"], "customer": CUSTOMER}
    assert client.post("/api/auth/register", json=body).status_code == 201


def test_only_plain_digits_are_accepted(client):
    other_script = client.post("/api/auth/otp/send", json={"mobile": "9८७६५४३२१०", "purpose": "SIGNUP"})
    assert other_script.status_code == 400
    assert _login(client, "१२३४").json()["message"] == "Enter a 4-digit PIN"


def test_signup_token_works_only_once(client):
    token = _verify(client)
    body = {"verificationToken": token, "pin": "4826", "roles": ["CUSTOMER"], "customer": CUSTOMER}
    assert client.post("/api/auth/register", json=body).status_code == 201
    with engine.begin() as connection:  # even if the account were removed, the token stays used
        connection.execute(text("DELETE FROM users"))
    again = client.post("/api/auth/register", json=body)
    assert again.status_code == 401
    assert again.json()["code"] == "TOKEN_USED"


def test_reset_token_works_only_once(client):
    _register(client, roles=("CUSTOMER",))
    token = _verify(client, purpose="RESET_PIN")
    assert client.post("/api/auth/pin/reset", json={"verificationToken": token, "newPin": "7391"}).status_code == 204
    again = client.post("/api/auth/pin/reset", json={"verificationToken": token, "newPin": "2580"})
    assert again.status_code == 401
    assert again.json()["code"] == "TOKEN_USED"
    assert _login(client, "7391").status_code == 200


def test_reset_pin_logs_out_old_sessions(client):
    old_token = _register(client, roles=("CUSTOMER",))["accessToken"]
    assert client.get("/api/me", headers=_auth(old_token)).status_code == 200
    reset = _verify(client, purpose="RESET_PIN")
    client.post("/api/auth/pin/reset", json={"verificationToken": reset, "newPin": "7391"})

    stale = client.get("/api/me", headers=_auth(old_token))
    assert stale.status_code == 401
    assert stale.json()["code"] == "TOKEN_INVALID"
    new_token = _login(client, "7391").json()["accessToken"]
    assert client.get("/api/me", headers=_auth(new_token)).status_code == 200


def test_verification_token_is_not_a_login(client):
    token = _verify(client)
    assert client.get("/api/me", headers=_auth(token)).json()["code"] == "TOKEN_INVALID"


def test_otp_hourly_limit(client):
    send = {"mobile": MOBILE, "purpose": "SIGNUP"}
    for _ in range(5):
        assert client.post("/api/auth/otp/send", json=send).status_code == 200
        _age_otps(31)  # skip the 30-second wait between OTPs
    sixth = client.post("/api/auth/otp/send", json=send)
    assert sixth.status_code == 429
    assert sixth.json()["code"] == "OTP_LIMIT"


def test_old_otps_are_cleaned_up(client):
    send = {"mobile": MOBILE, "purpose": "SIGNUP"}
    client.post("/api/auth/otp/send", json=send)
    _age_otps(2 * 24 * 3600)
    client.post("/api/auth/otp/send", json=send)
    with engine.connect() as connection:
        assert connection.execute(text("SELECT count(*) FROM otp_codes")).scalar_one() == 1


def test_repeated_wrong_pins_lock_for_a_day(client):
    _register(client, roles=("CUSTOMER",))
    for _ in range(5):
        _login(client, "0000")
    _end_lock()
    for _ in range(4):
        assert _login(client, "0000").status_code == 401
    locked = _login(client, "0000")
    assert locked.status_code == 423
    assert locked.json()["message"] == "Too many wrong PINs. Try again in 24 hours or reset your PIN"


def test_right_pin_clears_the_wrong_pin_count(client):
    _register(client, roles=("CUSTOMER",))
    for _ in range(4):
        _login(client, "0000")
    assert _login(client).status_code == 200
    for _ in range(4):
        assert _login(client, "0000").status_code == 401


def test_reset_pin_unlocks_the_account(client):
    _register(client, roles=("CUSTOMER",))
    for _ in range(5):
        _login(client, "0000")
    token = _verify(client, purpose="RESET_PIN")
    client.post("/api/auth/pin/reset", json={"verificationToken": token, "newPin": "7391"})
    assert _login(client, "7391").status_code == 200


def test_responses_never_include_secrets(client):
    body = _register(client)
    assert set(body) == {"accessToken", "user"}
    assert set(body["user"]) == {"id", "mobile", "roles", "shop", "customer", "supplier"}
    assert "$2" not in str(body)  # no bcrypt hash anywhere
    me = client.get("/api/me", headers=_auth(body["accessToken"])).json()
    assert set(me) == set(body["user"])


def test_production_refuses_development_settings():
    import pytest

    from app.config import Settings, check_settings

    strong = "x" * 40
    with pytest.raises(ValueError):
        check_settings(Settings(app_env="production", otp_expose=False))  # still the development key
    with pytest.raises(ValueError):
        check_settings(Settings(app_env="production", jwt_secret=strong))  # OTP still sent back to the app
    ready = {"app_env": "production", "jwt_secret": strong, "otp_expose": False, "ai_key": "y" * 40,
             "payment_secret_key": "p" * 40}
    check_settings(Settings(**ready))
    with pytest.raises(ValueError):  # still the development payment key
        check_settings(Settings(**{**ready, "payment_secret_key": Settings().payment_secret_key}))
    with pytest.raises(ValueError):  # one Razorpay account for every shop is not allowed
        check_settings(Settings(**ready, razorpay_key_id="rzp_live_abcdefgh12", razorpay_key_secret="s" * 24))
    assert not Settings(app_env="production", razorpay_key_id="rzp_test_x", razorpay_key_secret="y") \
        .razorpay_test_account_on


def test_otp_never_written_to_the_log_outside_test_mode(client, monkeypatch, caplog):
    import logging

    from app.auth import sms
    from app.config import get_settings

    # The test database setup (alembic) switches off existing loggers: switch this one back on.
    monkeypatch.setattr(logging.getLogger("qbox.sms"), "disabled", False)
    monkeypatch.setattr(get_settings(), "otp_expose", False)
    with caplog.at_level(logging.INFO, logger="qbox.sms"):
        sms.send_sms("9876543210", "123456 is your QBOX OTP")
    assert "123456" not in caplog.text
    assert "9876543210" not in caplog.text  # the number is masked too
    assert "98******10" in caplog.text

    caplog.clear()
    monkeypatch.setattr(get_settings(), "otp_expose", True)  # test mode: shown, on purpose
    with caplog.at_level(logging.INFO, logger="qbox.sms"):
        sms.send_sms("9876543210", "123456 is your QBOX OTP")
    assert "123456" in caplog.text


def test_one_device_cannot_try_a_pin_on_many_numbers(client, monkeypatch):
    from app import ratelimit
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "auth_requests_per_ip_10min", 5)
    ratelimit.forget()
    try:
        for i in range(5):
            r = client.post("/api/auth/login", json={"mobile": f"98765432{i:02d}", "pin": "1357"})
            assert r.status_code == 401  # wrong, but allowed to try
        r = client.post("/api/auth/login", json={"mobile": "9876543299", "pin": "1357"})
        assert r.status_code == 429
        assert r.json()["code"] == "TOO_MANY_REQUESTS"
        # OTP requests from the same device count too
        assert client.post("/api/auth/otp/send", json={"mobile": "9123456780", "purpose": "SIGNUP"}).status_code == 429
        # Logged-in features are not affected
        assert client.get("/health").status_code == 200
    finally:
        ratelimit.forget()
