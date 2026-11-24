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
| GET | `/api/calendar/events?role=BUSINESS` | Yes (own events only) |
| POST | `/api/calendar/events` | Yes |
| PUT | `/api/calendar/events/{id}` | Yes (owner only) |
| DELETE | `/api/calendar/events/{id}` | Yes (owner only) |
| GET | `/api/calendar/festivals` | Yes |
| GET | `/api/udhaar/customers` | Yes, shop (own book only) |
| POST | `/api/udhaar/customers/otp` | Yes, shop (sends the code to the customer) |
| POST | `/api/udhaar/customers` | Yes, shop (needs the customer's code) |
| GET / PUT | `/api/udhaar/customers/{id}` | Yes, shop (own customers only) |
| POST | `/api/udhaar/customers/{id}/entries` | Yes, shop |
| POST | `/api/udhaar/entries/{id}/delete` | Yes, shop (kept, with reason) |
| GET | `/api/udhaar/mine`, `/api/udhaar/mine/{id}` | Yes, customer (own udhaar only) |
| GET | `/api/customer/transactions?month=2026-11` | Yes, customer (own udhaar lines and payments; this month if empty) |
| POST | `/api/customer/records`, `/records/{id}/same`, `/different` | Yes, customer (payments they add; private to them) |
| PUT | `/api/customer/expenses/{item}`, `/api/customer/budget` | Yes, customer (category or leave out / monthly budget) |
| PUT | `/api/me/shop`, `/api/me/customer`, `/api/me/supplier` | Yes (own details) |
| POST | `/api/me/roles` | Yes (one more role; needs the PIN) |
| PUT / DELETE | `/api/me/photo/{role}` | Yes (own photo) |
| GET | `/api/photos/{ref}` | Yes (own photo, or a shop's) |
| POST | `/api/me/pin`, `/api/me/logout-all` | Yes (change PIN with the old one; log out everywhere) |
| GET / POST / PUT | `/api/notices`, `/unread`, `/read`, `/off` | Yes (the bell, own news only) |
| GET / PUT / DELETE | `/api/customer/pages`, `/pages/{ref}` | Yes, customer (checklists and notes; private to them) |
| POST | `/api/udhaar/mine/{id}/not-me` (and `/cancel`) | Yes, customer (only a report) |
| POST | `/api/udhaar/customers/{id}/dispute/confirm` or `/unlink` | Yes, shop (decides the report) |
| POST | `/api/udhaar/customers/{id}/number/otp`, `/number` | Yes, shop (new number, needs its code) |
| GET | `/api/language/status` | Yes (is the QBOX AI server running?) |
| POST | `/api/language/translate` | Yes (IndicTrans2 on the QBOX AI server) |
| POST | `/api/language/speech-to-text` | Yes (IndicConformer on the QBOX AI server, WAV) |
| GET | `/api/payments/settings` | Yes, shop (UPI ID, Razorpay status; never the secret) |
| PUT | `/api/payments/settings/upi` | Yes, shop |
| POST / DELETE | `/api/payments/settings/razorpay` | Yes, shop (keys checked with Razorpay, secret encrypted) |
| POST | `/api/payments/collect` | Yes, shop (one-time QR for an amount) |
| POST | `/api/payments/manual` | Yes, shop (paid to own UPI ID, confirmed by hand) |
| GET | `/api/payments?day=` | Yes, shop (paid that day; today if empty) |
| GET | `/api/payments/{id}` | Yes, the shop or the customer who paid (checks Razorpay while waiting) |
| POST | `/api/payments/{id}/cancel` | Yes, shop |
| POST | `/api/payments/udhaar/{book_id}` | Yes, customer (Razorpay order to pay udhaar) |
| GET | `/api/payments/shops` | Yes, customer (linked shops and shops paid before) |
| GET | `/api/payments/settings/qr` | Yes, shop (its own QR for customers to scan) |
| POST | `/api/payments/shops/scan` | Yes, customer (the shop whose QBOX QR was scanned) |
| POST | `/api/payments/shops/find` | Yes, customer (a shop by its login number; limited per hour) |
| POST | `/api/payments/shop` | Yes, customer (pay a shop: Razorpay, or the shop's own UPI ID) |
| POST | `/api/payments/{id}/claim`, `/drop` | Yes, customer (I paid by UPI / I did not) |
| POST | `/api/payments/{id}/confirm`, `/not-received` | Yes, shop (checks its bank, then answers) |
| POST | `/api/payments/{id}/verify` | Yes, customer (payment screen's signature checked) |
| GET | `/api/stock/items` | Yes, shop (own stock: quantities, value, low count) |
| POST | `/api/stock/items`, `/api/stock/items/bulk` | Yes, shop (one item, or many from the ready list) |
| GET / PUT | `/api/stock/items/{id}` | Yes, shop (item + history / change name, prices, alert) |
| POST | `/api/stock/items/{id}/archive` | Yes, shop (off the list, history kept) |
| POST | `/api/stock/items/{id}/moves` | Yes, shop (stock in, sold, or a correction with a reason) |
| GET / POST | `/api/suppliers` | Yes, shop (own suppliers: balance, pay-by date, open orders / add) |
| GET / PUT | `/api/suppliers/{id}` | Yes, shop (account history + orders / change details) |
| POST | `/api/suppliers/{id}/archive` | Yes, shop (off the list, history kept) |
| POST | `/api/suppliers/{id}/entries` | Yes, shop (purchase: items go into stock; or payment) |
| POST | `/api/suppliers/entries/{id}/delete` | Yes, shop (kept with reason; purchase stock taken back out) |
| POST | `/api/suppliers/{id}/orders` | Yes, shop (order sent on WhatsApp) |
| POST | `/api/suppliers/orders/{id}/receive`, `/cancel` | Yes, shop (received = purchase, stock goes up) |
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
  calendar/      events (per user and role) and the festival list
  udhaar/        credit book: customers (added by OTP), entries, "My Udhaar"
  customer/      the customer's transaction history and expenses (udhaar lines, payments
                 they made, and records they add themselves)
  language/      speech-to-text and translation (passes them to the QBOX AI server, ../qbox_ai)
  stock/         items and stock moves (in, sold, corrected); quantity = sum of moves
  suppliers/     suppliers, the shop's account with them, orders (purchases add stock via stock/)
  payments/      Razorpay QR / orders, the shop's UPI ID, payments list
                 (razorpay.py is the only file that talks to Razorpay; gateways.py picks the
                 shop's account and encrypts its secret key)
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
Control on this PC blocks SQLAlchemy's optional compiled speed-up files. For the
same reason the database driver is `pg8000` (pure Python), not psycopg: Smart App
Control blocks psycopg's `libpq` DLL.

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
| Udhaar: a customer is added only with the code sent to their phone (code works only for the shop that asked) | `udhaar/service.add_customer` |
| Udhaar: a shop sends at most 10 customer codes per hour; these never use up the person's own login-OTP limit | `udhaar/service.send_invite`, `auth/otp.py` |
| Udhaar: a shop sees only its own book; a customer sees only entries against their own login number | `udhaar/service.py` |
| Udhaar: money in whole paise, balance always calculated, entries never erased (deleted = kept with reason) | `udhaar_entries` table |
| Udhaar: the same entry sent twice (phone retry after offline) is kept once | `client_ref` |
| Udhaar: "This is not me" is only a report; nothing is hidden until the shop unlinks it. Once the shop confirms, it cannot be reported again | `udhaar/service.not_me`, `_resolve` |
| Transactions: a customer sees only lines against their own number and payments they made; a QBOX payment shows once | `customer/service.py` |
| Profile photos: only a plain JPEG is kept (no place or phone details); a shop's is seen by customers, others only by their owner | `users/photos.py` |
| Changing the PIN needs the old one; wrong tries lock the account like wrong logins | `users/profile.change_pin` |
| The bell only reads; nobody is told about another's book, payments or stock | `notices/service.py` |
| Checklists and notes: only their owner sees them; a retry counts once; two phones' changes are joined; a deleted one is emptied | `customer/pages.py` |
| Stock: quantities in thousandths of the unit (1.5 kg = 1500), always the sum of the moves; moves never erased, corrections need a reason | `stock/service.py`, `stock_moves` table |
| Stock: a shop sees only its own items; one live item per name; the same move sent twice is kept once | `stock/service.py`, `client_ref` |
| Suppliers: balance always from entries; entries never erased (deleted = kept with reason); payments pay off the oldest purchases first for the pay-by date | `suppliers/service.py` |
| Suppliers: a purchase's items go into stock through the stock rules; deleting it takes them back out with a correction | `stock.purchase_in`, `stock.purchase_undo` |
| Payments: money goes straight to the shop's own Razorpay account / UPI ID, never through QBOX | `payments/gateways.py` |
| Payments: the shop's Razorpay secret is stored encrypted and never sent to any phone | `gateways.lock`, `PaymentSettingsOut` |
| Payments: PAID only when Razorpay says captured, for exactly the amount asked | `service._mark_paid` |
| Payments: each Razorpay payment counted once; udhaar gets exactly one PAYMENT entry | `gateway_payment_id` unique, row lock, `client_ref` |
| Payments: a customer's payment is checked with Razorpay's signature, then with Razorpay itself | `service.verify` |
| Payments: a shop sees only its own payments; a customer only the ones they made | `service._visible` |
| Pay to Shop: a shop is found only by its OTP-checked login number, 20 look-ups per hour per account | `payments/direct.py`, `ratelimit.py` |
| Pay to Shop by UPI: the customer's "I paid" counts only after the shop confirms; the first answer stands | `direct.answer` |
| Payments: at most 60 QRs per shop / 10 udhaar payments per customer in 10 minutes | `service._check_rate` |

## Payments (Razorpay)

Each shop connects **its own** Razorpay account (Payment settings in the app), so money
goes straight to the shop's bank. QBOX never holds anyone's money (that would need an RBI
licence). A shop can also just save its own UPI ID: free, but the shop confirms each
payment by hand.

- **Counter:** a one-time UPI QR (Razorpay QR Codes). If QR Codes is not switched on for
  the account, a Razorpay payment link is shown as the QR instead (scanned with the camera).
- **Udhaar:** the customer pays in their QBOX app on Razorpay's own payment screen; the
  backend checks the signature and asks Razorpay before the book changes.
- **Testing on this PC:** put Razorpay **test** keys in `.env` as `QBOX_RAZORPAY_KEY_ID` /
  `QBOX_RAZORPAY_KEY_SECRET`. Shops without their own account then use it (pretend money).
  Refused in production.
- Razorpay cannot reach this PC, so the backend asks Razorpay "is it paid?" while the app
  waits. On the live server, add Razorpay webhooks and phone notifications (next phase).

## Festival list (update every year)

Festivals live in the `festivals` table (first filled by `alembic/versions/0003_calendar.py`).
When the official Telangana / AP holiday list for a new year is published (usually December),
add a new migration that inserts that year's rows. The app picks them up with no app update.
2027 still needs: Islamic festivals, Bonalu and Bathukamma.

## Online speech and translation (QBOX AI server)

The app's voice features use AI4Bharat **IndicConformer** (speech-to-text) and
**IndicTrans2** (translation), running on our own machine in `../qbox_ai`
(see its README). Free, MIT licence, and nothing said leaves our servers.

The phone -> this backend (login, daily limit) -> the AI server (`QBOX_AI_URL`, default
`http://127.0.0.1:8090`). The two servers share a key: `QBOX_AI_KEY` here must equal
`QBOX_AI_KEY` in `qbox_ai/.env`. When the AI server is not running, `/api/language/status`
answers `{"online": false}` and the app uses the phone's own speech and translation.

Each person may make 300 speech/translation requests a day (`QBOX_LANGUAGE_DAILY_LIMIT`).
Set `QBOX_AI_URL=` (empty) to switch it off completely.

## Before going live

- Set `QBOX_APP_ENV=production` (also hides `/docs`). The server then refuses to start until:
  - `QBOX_JWT_SECRET` is a private random value (32+ characters)
  - `QBOX_OTP_EXPOSE=false` (after an SMS provider is connected in `app/auth/sms.py`)
  - `QBOX_AI_KEY` is a private random value (32+ characters), the same in `qbox_ai/.env`
  - `QBOX_PAYMENT_SECRET_KEY` is a private random value (32+ characters). Keep a safe copy:
    without it, the saved Razorpay keys cannot be read and every shop must connect again
  - `QBOX_RAZORPAY_KEY_ID` / `QBOX_RAZORPAY_KEY_SECRET` are removed (each shop uses its own account)
- Set a real `QBOX_DATABASE_URL` with a strong password
- Serve over HTTPS only, behind a proxy (e.g. Nginx/Cloudflare) that also limits requests per IP address
