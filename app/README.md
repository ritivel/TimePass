# Nakul Flutter app

The Android/web client for Nakul. It renders server-authored A2UI surfaces through a closed
component catalog and adds the Monogram-inspired shell, voice input, cloud-synced chat history,
bookmarks, dark mode, dynamic generated visuals, and Supabase accounts. Product builds start with
an invisible anonymous session: five questions require no login, then the same user can attach
email or Google without losing chats.

## Run locally

```sh
flutter pub get
flutter run --dart-define=NAKUL_API=http://127.0.0.1:8000
```

To exercise product auth locally, also pass `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY`. A build without those two values intentionally uses
the device-only development path. Production builds also pass the public
`TURNSTILE_SITE_KEY` and the matching HTTPS `TURNSTILE_BASE_URL`; only enable
CAPTCHA in Supabase after those values are present in every shipped client.

For a physical Android phone, point `NAKUL_API` at the laptop's LAN address and run the server
on `0.0.0.0`. USB/emulator testing can instead use `adb reverse tcp:8000 tcp:8000`.

## Verify and build

```sh
flutter analyze
flutter test
flutter build apk --release
```

Release artifact: `build/app/outputs/flutter-apk/app-release.apk`.

The repository also contains `../output/android/Nakul-phone-192.168.1.6.apk`, built against this
laptop's current LAN address and verified without `adb reverse`. Rebuild with a new
`--dart-define=NAKUL_API=http://<LAN-IP>:8000` whenever that address changes.

The Android application id is `app.nakul.mobile`. The repository's release build deliberately
uses the debug keystore so it is directly installable for private testing. Configure an owner-held
release keystore before Play Store distribution: copy `android/key.properties.example` to
`android/key.properties`, fill in the owner-held keystore values, and rebuild. The real properties
file and `.jks`/`.keystore` files are gitignored.
