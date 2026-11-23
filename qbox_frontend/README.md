# QBOX App (Flutter)

The QBOX mobile app for shops, customers and suppliers.
It talks to the FastAPI backend in `../qbox_backend`.

## Run it

1. Start the backend (see `../qbox_backend/README.md`).
2. Start the Android emulator:
   ```powershell
   & "C:\Users\Quadrant\dev\tools\android-sdk\emulator\emulator.exe" -avd qbox_pixel -gpu swiftshader_indirect
   ```
3. From this folder (`QBOX\qbox_frontend`):
   ```powershell
   flutter run
   ```
   In that terminal: `r` = reload after a code change, `R` = restart, `q` = quit.

The emulator reaches the backend at `http://10.0.2.2:8080`. For a real phone or a live server:
`flutter run --dart-define=QBOX_API_URL=https://<server-address>`

## Check it

```powershell
flutter analyze   # code problems
flutter test      # automatic tests (use a pretend backend, no server needed)
```

## Folders

```
lib/
  main.dart               starts the app
  startup_gate.dart       first screen: logged in already? -> Choose Role, else Welcome
  *_screen.dart           one file per screen (welcome, OTP, sign-up, login, PIN, homes...)
  onboarding_draft.dart   what the user typed during sign-up, and the logged-in user
  calculator/             shop calculator (works offline, no backend needed)
    calculator_engine.dart  the maths: keys, %, GT, memory, history
    voice_math.dart         spoken words -> sum ("two fifty plus 180 into 3")
    spoken_operators.dart   plus/minus/into/divide in te/hi/kn/ta -> + − × ÷ (sums in
                            Indian languages are worked out on the phone, not translated)
    voice_services.dart     phone microphone (speech_to_text) and speaker (flutter_tts)
    calculator_store.dart   history/GT/memory saved on the phone, cleared on log out
    calculator_screen.dart  the screen
  calendar/               shop & personal calendar (backend + phone copy for offline)
    calendar_models.dart    events, repeats, festivals, date helpers
    voice_event.dart        spoken sentence -> event ("tomorrow 10 am supplier payment")
    calendar_api.dart       backend calls; calendar_store.dart = phone copy
    reminders.dart          phone notifications (flutter_local_notifications)
    calendar_screen.dart    month view; event_form_screen.dart = add/edit
  udhaar/                 credit book (backend + phone copy; entries saved offline sync later)
    udhaar_models.dart      customers, entries, money in paise (₹ helpers)
    udhaar_repository.dart  server + phone copy + offline queue (never doubles an entry)
    voice_udhaar.dart       "Ramesh 250 udhaar" / "Ramesh paid 100" -> entry
    udhaar_screen.dart      the book; customer_screen.dart = one customer
    add_customer_screen.dart  add with SMS code; entry_form_screen.dart = add entry
    my_udhaar_screen.dart   customer side: "My Udhaar" (with "Pay" when money is owed)
  stock/                  shop inventory (backend + phone copy; moves saved offline sync later)
    stock_models.dart       items, moves, units (quantities in thousandths: 1.5 kg = 1500)
    stock_catalog.dart      ~80 common shop items with names in all 5 languages
    voice_stock.dart        "rice 10 kg came" / "బియ్యం 10 కిలోలు వచ్చాయి" -> item, qty, in/out
    stock_repository.dart   server + phone copy + offline queue; low-stock count for the home badge
    stock_screen.dart       the list; item_screen.dart = one item and its history
    item_form_screen.dart   add / change an item; quick_start_screen.dart = tick common items
    stock_widgets.dart      the in / sold / correct sheet, low-stock notification
  suppliers/              who the shop buys from (backend + phone copy; entries saved offline)
    supplier_models.dart    suppliers, purchases/payments, orders, the WhatsApp order message
    supplier_repository.dart  server + phone copy + offline queue
    suppliers_screen.dart   the list (what you owe, pay-by dates); supplier_screen.dart = one supplier
    supplier_entry_screen.dart  purchase (items go into stock) / payment / goods received
    order_screen.dart       order from what is running low, sent on WhatsApp
  payments/               taking payments (shop) and paying udhaar (customer)
    payments_screen.dart    today's total and list; says new payments out loud
    collect_screen.dart     amount (keypad or voice) -> QR -> "₹250 received"
    payment_settings_screen.dart  own UPI ID, connect Razorpay
    pay_udhaar.dart         customer pays on Razorpay's screen; backend checks it
    checkout.dart           Razorpay's payment screen (razorpay_flutter)
    payment_models.dart     payments, UPI QR link, "received" words in 5 languages
  translator/             voice translator and the shared voice languages
    languages.dart          English, Telugu, Hindi, Kannada, Tamil (speech/voice/translate codes)
    translation_service.dart  IndicTrans2 online (QBOX server), else on-phone ML Kit
    speech_engines.dart     picks by itself: IndicConformer on the QBOX server for Indian
                            languages when reachable, else the phone's Google speech;
                            English always the phone's. Knows when you stopped talking
                            (learns how noisy the room is). No engine names in the app.
    indic_numbers.dart      spoken numbers in te/hi/kn/ta -> digits, on the phone, before
                            any translation ("రెండు వందల యాభై" -> 250), so amounts never change
    voice_language.dart     the shared "Speak in" language + engine choice
    language_packs.dart     asks, then downloads a language pack (~30 MB, once)
    transliterate.dart      Indian scripts -> English letters (to match spoken names)
    translator_screen.dart  two people, two mics, shown in both languages and spoken aloud
  models/                 data from the backend (QboxUser)
  services/               backend calls (auth_api.dart), saved login (session_store.dart),
                          device_actions.dart (WhatsApp / SMS / call links, contact picker)
  widgets/                shared pieces (digit boxes, wave footer, animations)
test/                     widget tests and the pretend backend (fake_auth_api.dart)
assets/                   images and Poppins font
android/                  Android build settings
```

## Security notes

- The login token is stored encrypted (Android Keystore) via `flutter_secure_storage`.
- App backups are switched off so the token never leaves the phone.
- Plain `http://` is allowed only in debug builds; release builds need HTTPS.
- Contacts: QBOX uses the phone's own contact picker, so it never asks for permission
  to read the address book; it only gets the one contact the shopkeeper taps.
- Log out wipes the calculator, calendar, udhaar and stock copies, including unsent entries.
- The stock copy on the phone is encrypted (Android Keystore), like the udhaar book.
- Translation: online, the text goes to the QBOX server (IndicTrans2 runs there);
  offline it stays on the phone (Google ML Kit). Speech: Google's service, or with
  IndicConformer the recording goes to the QBOX server and is deleted from the phone
  straight after. No outside company is involved, and nothing said is stored.
- Speaking aloud is always the phone's own Google voice (text-to-speech).
- Payments: the Razorpay secret key is typed once in Payment settings and kept only on
  the server (encrypted); the phone never stores it. Card and bank details are typed into
  Razorpay's own screen, never into QBOX. A payment counts only after the backend checks it.
