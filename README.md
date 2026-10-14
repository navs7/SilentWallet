# Silent Wallet

An offline expense manager for Android. **Everything stays on the phone** — no account, no cloud, no analytics, and no internet permission.

## Download

**[Get the latest APK from Releases](https://github.com/navs7/SilentWallet/releases/latest)** — pick `arm64-v8a` unless your phone is very old. Checksums are in `SHA256SUMS.txt` on the same page; install steps are in [INSTALL-GUIDE.md](INSTALL-GUIDE.md).

## Features

- Expenses, income and transfers between accounts (Cash, Bank, Card, UPI / Wallet, …)
- Built-in categories plus your own (custom name, icon and colour)
- Recurring rules (daily / weekly / monthly / yearly) that post automatically when due
- Reports: income vs expense, category pie chart, 6-month trend
- Receipt photos attached to transactions
- App lock with fingerprint / face / phone PIN
- Password-encrypted backup and restore, with a weekly local reminder
- CSV export for spreadsheets
- Currency: INR (₹)

## Privacy and security design

| Goal | How it is done |
|---|---|
| Nothing leaves the device | The release build has no `INTERNET` permission (removed in `android/app/src/release/AndroidManifest.xml`), so Android blocks all network access. No analytics, crash reporting or cloud SDKs. |
| Encrypted data at rest | SQLite database encrypted with SQLCipher (AES-256). The key is random, created on first launch and stored in the Android Keystore via `flutter_secure_storage` — it is never shown or sent anywhere. |
| Encrypted receipts | Each photo is stored as an AES-256-GCM encrypted file in the app's private folder; the picked cache copy is deleted. |
| App lock | `local_auth` (biometric or device credential). The app re-locks when sent to the background. |
| Screen privacy | `FLAG_SECURE` blocks screenshots and hides the recent-apps preview. |
| No silent cloud copies | `allowBackup="false"` and data-extraction rules exclude all app data from Google backup and device transfer. |
| Backups you control | **More → Backup & restore** produces a `.swbak` file: a zip of the data and receipts, encrypted with AES-256-GCM using a key derived from your password (PBKDF2-HMAC-SHA256, 120,000 iterations, random salt). The password cannot be recovered. |

**Limits:** losing the phone without a backup file means losing the data. Uninstalling or clearing app data deletes the encryption key with it. The app lock protects the UI; the encryption protects the files at rest.

## Using the app

See [INSTALL-GUIDE.md](INSTALL-GUIDE.md) for sideloading steps, first-run setup and how to back up and restore.

## Building

Requirements: JDK 17, Android SDK (platform 35/36, build-tools 35), Flutter (stable).

```bash
flutter pub get
flutter analyze
flutter test
flutter run                                 # debug build on a connected phone
flutter build apk --release --split-per-abi # per-CPU release APKs
```

### Release signing

Release builds are signed with a key that is **not** in this repository. Create `android/key.properties` (git-ignored) pointing at your keystore:

```properties
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=<your key alias>
storeFile=<path to your .jks file>
```

Keep the keystore and its password backed up. Sideloaded updates only install over an existing copy if they are signed with the **same** key.

Bump `version:` in `pubspec.yaml` for every release (for example `1.0.1+2`); Android will not install a build with the same or lower version code.

## Project layout

```
lib/
  main.dart              app start-up, lock gate
  util.dart              money formatting / parsing, dialogs
  core/
    crypto.dart          Keystore keys, AES-GCM helpers, backup container
    models.dart          Account, Category, Tx, Recurring, date rules
    repo.dart            encrypted SQLite data layer, receipts, recurring engine
  services/              settings, app lock, local notifications, backup/CSV
  screens/               transactions, reports, accounts, categories,
                         recurring, backup, more, onboarding, lock
test/                    unit tests (money, recurring dates, models, encryption)
```

## Tests

`flutter test` runs unit tests for money parsing/formatting, recurring-date rules (month-end and leap years), model serialisation, and the encryption and backup format (wrong password, tampering, truncated files). Database-backed behaviour (balances, recurring catch-up, full restore) and the UI/biometric flows are checked manually on a device.

## Tech stack

Flutter · `sqflite_sqlcipher` · `flutter_secure_storage` · `local_auth` · `cryptography` · `archive` · `fl_chart` · `image_picker` · `file_picker` · `share_plus` · `flutter_local_notifications` · `provider`
