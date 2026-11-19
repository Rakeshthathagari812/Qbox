# QBOX Backend (FastAPI)

The QBOX backend: accounts, login and (later) udhaar, stock, suppliers, payments and AI voice.
Python + FastAPI + PostgreSQL.

## Run it

From this folder (`QBOX\qbox_backend`):

```powershell
.venv\Scripts\python -m uvicorn app.main:app --reload --port 8080
```

Always start tools as `.venv\Scripts\python -m <tool>`. Windows Smart App Control on
this PC blocks the small `.exe` launchers (uvicorn.exe, alembic.exe) inside `.venv\Scripts`.

- Ready when you see `Uvicorn running on http://127.0.0.1:8080`
- `--reload` restarts the server by itself when you save a Python file
- Stop with `Ctrl + C`
- Test-mode OTPs appear in this window as `[TEST SMS] ...`

## Check it

| Open in browser | What you get |
|---|---|
| http://localhost:8080/health | `{"status":"UP"}` |
| http://localhost:8080/docs | Every API, with **Try it out** buttons |

## APIs

| Method | Path | Login needed |
|---|---|---|
| POST | `/api/auth/otp/send` | No |
| POST | `/api/auth/otp/verify` | No |
| POST | `/api/auth/register` | No (verification token) |
| POST | `/api/auth/login` | No |
| POST | `/api/auth/pin/reset` | No (verification token) |
| GET | `/api/me` | Yes |
| GET | `/health` | No |

## Folders

```
app/
  main.py        starts the app, connects the routers
  config.py      settings (database address, OTP rules, token life)
  database.py    PostgreSQL connection
  models.py      database tables (one class = one table)
  security.py    PIN/OTP hashing and login tokens (JWT)
  errors.py      every error as {"code", "message"}
  deps.py        "needs login" check for protected APIs
  auth/          sign up, OTP, login, reset PIN   (router -> service)
  users/         GET /api/me
alembic/versions/  database table changes, applied in order
tests/             automatic tests (use the qbox_test database)
```

New features follow the same pattern: a folder such as `app/udhaar/` with
`router.py` (the API paths), `schemas.py` (request/response shapes) and
`service.py` (the rules), plus a new file in `alembic/versions/` for its tables.

## Database changes

```powershell
.venv\Scripts\python -m alembic upgrade head     # apply all table changes
.venv\Scripts\python -m alembic current          # which version the database is on
```

## Tests

```powershell
.venv\Scripts\python -m pytest
```

They run against a separate `qbox_test` database, so real data is never touched.

## First-time setup on a new PC

```powershell
python -m venv .venv
$env:DISABLE_SQLALCHEMY_CEXT="1"
.venv\Scripts\python -m pip install --no-binary SQLAlchemy -r requirements.txt
.venv\Scripts\python -m alembic upgrade head
```

`--no-binary SQLAlchemy` installs SQLAlchemy as pure Python. Windows Smart App
Control on this PC blocks SQLAlchemy's optional compiled speed-up files.

## Security rules already built in

| Rule | Where |
|---|---|
| PINs and OTPs stored only as bcrypt hashes | `security.py` |
| OTP: 5 min life, 30 s between sends, 5 per hour per number, 5 wrong tries | `auth/otp.py` |
| Verification token works once (sign-up or PIN reset) | `otp.use_verification` |
| PINs like 1111, 1234, 9876 refused | `auth/schemas.py` |
| 5 wrong PINs: 15 min lock. Every 5 more: 24 h lock | `auth/service.login` |
| PIN reset logs the account out on every phone | `users.token_version` |
| Wrong login takes the same time for unknown numbers | `security.DUMMY_HASH` |
| Responses never contain hashes, attempts or lock details | `users/service.to_me` |
| Server refuses to start in production with dev settings | `config.check_settings` |

## Before going live

- Set `QBOX_APP_ENV=production` (also hides `/docs`). The server then refuses to start until:
  - `QBOX_JWT_SECRET` is a private random value (32+ characters)
  - `QBOX_OTP_EXPOSE=false` (after an SMS provider is connected in `app/auth/sms.py`)
- Set a real `QBOX_DATABASE_URL` with a strong password
- Serve over HTTPS only, behind a proxy (e.g. Nginx/Cloudflare) that also limits requests per IP address
