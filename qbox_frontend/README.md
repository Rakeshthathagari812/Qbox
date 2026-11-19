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
    voice_services.dart     phone microphone (speech_to_text) and speaker (flutter_tts)
    calculator_store.dart   history/GT/memory saved on the phone, cleared on log out
    calculator_screen.dart  the screen
  models/                 data from the backend (QboxUser)
  services/               backend calls (auth_api.dart), saved login (session_store.dart)
  widgets/                shared pieces (digit boxes, wave footer, animations)
test/                     widget tests and the pretend backend (fake_auth_api.dart)
assets/                   images and Poppins font
android/                  Android build settings
```

## Security notes

- The login token is stored encrypted (Android Keystore) via `flutter_secure_storage`.
- App backups are switched off so the token never leaves the phone.
- Plain `http://` is allowed only in debug builds; release builds need HTTPS.
