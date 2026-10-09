# limenia_device (Flutter)

Flutter plugin for the device connector of Limenia, the moderation service for apps (API version 0.20.0). It gets a fresh token of the device:

- **Android:** Play Integrity, standard request, with Device Recall.
- **iOS:** Apple DeviceCheck.

Your backend forwards the token to `POST /v1/devices/check`. Limenia reads the few bits Google and Apple keep per device, which survive a reinstall and a factory reset. It marks the device of a banned or suspended user and tells you when an account is used on a marked device. A marked device is a hint, never proof: devices are sold on, and Apple forbids using the bits as the only evidence. Your app decides what follows, e.g. more verification at registration.

The plugin does nothing else. It does not talk to Limenia and depends neither on the package [`limenia`](https://pub.dev/packages/limenia) nor on any package besides Flutter.

## Installation

```yaml
dependencies:
  limenia_device: ^0.1.1
```

The plugin is optional: add it only if your app uses the device connector. Reports, complaints, reviews, signals and the widgets come from the package [`limenia`](https://pub.dev/packages/limenia), which the plugin does not need. Both live in the repo [DL3KB/limenia-flutter](https://github.com/DL3KB/limenia-flutter), this one in `packages/limenia_device`.

Requirements: Android `minSdk` 24 (Play Integrity needs 23) and a device with Google Play; iOS 15. It works with CocoaPods and Swift Package Manager. Developed and tested with Flutter 3.47; the Dart code needs Dart 3.5, and the native code was not built with older versions of Flutter.

## The flow

The Limenia API key belongs in your backend, never in the app. The app never calls Limenia itself:

```
App                                   Your backend                         Limenia
 |  1. "start device check" ---------> |  nonce = random, once
 |                                     |  hash = deviceRequestHash(uid, nonce)
 | <--------------------------- hash   |  remember hash for uid (minutes)
 |  2. LimeniaDevice.requestToken(requestHash: hash)
 |  3. platform, token, hash --------> |  4. checks hash, uid from the login
 |                                     |  POST /v1/devices/check ----------> |
 | <------------------ your decision   | <------------ DeviceCheckResult --- |
```

1. The backend picks a random nonce for the signed-in user and computes the request hash with `deviceRequestHash(externalUserId, nonce)`: `base64url(SHA-256("limenia:" + externalUserId + ":" + nonce))` without padding (the package `limenia` has it as `deviceRequestHash`). It remembers the hash for a few minutes and returns it.
2. The app requests the token with this hash.
3. The app sends `platform`, `token` and the hash to the backend.
4. The backend takes the user from its own login, checks that it issued this hash to this user and drops it (single use), and forwards everything to `POST /v1/devices/check`. On Android Limenia checks that the token was requested with exactly this hash, for the package of the app and at most 15 minutes ago. That binds the token to the user and to this check: a token of another device cannot be passed off.

On iOS DeviceCheck has no request hash, so the plugin ignores it. The token is bound only by being single-use, and your backend still takes the user from its login.

```dart
import 'package:flutter/foundation.dart';
import 'package:limenia_device/limenia_device.dart';

Future<void> checkDevice(MyBackend backend, {required String event}) async {
  if (!await LimeniaDevice.isSupported()) {
    // Emulator, simulator or a device without Google Play: see "Test mode".
    return;
  }
  final hash = await backend.startDeviceCheck(); // step 1
  try {
    final token = await LimeniaDevice.requestToken(
      requestHash: hash,
      cloudProjectNumber: 123456789012, // Android: the Cloud project linked in the Play Console
    );
    await backend.checkDevice(
      platform: token.platform, // 'android' or 'ios'
      token: token.token, // single-use, never store or log it
      requestHash: hash,
      // iOS: builds signed for development (debug builds from Xcode) need the development environment of DeviceCheck.
      environment: token.platform == 'ios' && kDebugMode ? 'development' : null,
      event: event, // registration, login, report or other
    );
  } on LimeniaDeviceException catch (e) {
    // e.code: unsupported, invalid_argument or failed; e.nativeCode: the code of Play Integrity or DeviceCheck.
    debugPrint('No device token: ${e.code}');
  }
}
```

Your backend calls `POST /v1/devices/check` of Limenia with its API key, e.g. with the TypeScript or Dart client of Limenia (`checkDevice`).

When to check:

- At registration and at every login, **also the login of a banned account, before the app rejects it**: only with a fresh token of the device can Limenia mark it.
- Optionally when a user reports, so that a marked device of the reporter shows up.

What the backend does with the answer (`DeviceCheckResult`):

- `deviceFlag` is `banned` or `suspended`: a banned or suspended account has used this device (in any app of the same Play developer account or Apple team). Ask for more verification, hold the registration for review, or let a rule of Limenia open a case (the system signal `device_flagged`). Do not block on this alone.
- `status: unevaluated` (`deviceFlag: unknown`): Google or Apple could not be asked. Limenia fails open, and you decide whether to go on.
- `integrity` (Android only): the device verdict and risks such as apps that can control the device. The system signal `device_risk` lets rules react on them.
- Errors: 400 `invalid_device_token` (request a new token, never send one twice), 409 `device_connector_not_configured` (the connector of this platform is off or not set up for the app), 403 `feature_not_in_plan`.

## Setup

### Android

1. Play Console, *Test and release > App integrity > Play Integrity API*: link a Google Cloud project to the app. Its project number (Google Cloud console, project dashboard) is the `cloudProjectNumber` of `requestToken`.
2. Under *Change responses*, turn on Device Recall (beta, enabled through Google's interest form) and the optional verdicts you want (e.g. app access risk, Play Protect, recent device activity).
3. In the Limenia dashboard, app settings, section *Device connector*: enter the package name and a service account of the linked project, grant the roles shown there, and *Test connection*.

Notes:

- The plugin prepares Play Integrity (`prepareIntegrityToken`) on the first request and keeps the provider for the next ones. If Google invalidates it (`INTEGRITY_TOKEN_PROVIDER_INVALID`), the plugin prepares again, once. The first request can take a few seconds; you can call `requestToken` early, e.g. while the login screen is shown.
- Google allows 10,000 decodes per day per Cloud project by default; Limenia shows the number of checks of the day in the dashboard.
- Errors that Google recommends to retry with exponential backoff come as `failed` with `nativeCode` -3 (`NETWORK_ERROR`), -8 (`TOO_MANY_REQUESTS`), -12 (`GOOGLE_SERVER_UNAVAILABLE`) or -18 (`CLIENT_TRANSIENT_ERROR`). A device without Google Play gives `unsupported`, a wrong project number or a hash longer than 500 characters `invalid_argument`.
- `isSupported()` checks whether the Google Play Store is installed. For this the plugin adds a `<queries>` entry for `com.android.vending` to the manifest of the app.

### iOS

1. Apple Developer account, *Certificates, Identifiers & Profiles > Keys*: create a key with DeviceCheck and download the `.p8` file.
2. In the Limenia dashboard, app settings, section *Device connector*: enter the Team ID, the Key ID and the content of the `.p8` file, then *Test connection*. The key goes straight into Secret Manager and is never shown again. One key serves all apps of the team.
3. Send `environment: development` for builds signed for development (debug builds run from Xcode). TestFlight and App Store builds use `production`, the default.

The plugin links the DeviceCheck framework. Its privacy manifest is empty: DeviceCheck is no required reason API, and the plugin collects and stores nothing.

## Test mode

Simulators and emulators cannot give real tokens (`isSupported()` is `false` in the iOS simulator; Android emulators without Google Play fail). For them, and for automated tests, an admin turns on the test mode of the device connector for the app in the Limenia dashboard. Then your backend may send `platform: test` with a token `test:<device>`, where `<device>` matches `[a-z0-9-]{1,40}`, e.g. `test:pixel-emulator-1`. With `:risk` (`test:pixel-emulator-1:risk`) Limenia reports a device without integrity. Limenia simulates the bits per test device for 30 days, and marking, reset, signals and the user file behave as with real devices; the answer has `test: true`.

Only accept test tokens from debug builds or test accounts in your backend, and keep the test mode off for apps in production use.

## Privacy

- Tokens are single-use. The plugin never logs or stores them; your app and backend must not either. Limenia stores only the summarized result, never the token, the request hash or device identifiers.
- The bits survive a reinstall, so the tenant needs a basis under data protection law: the privacy policy, the privacy details in the stores (App Store privacy labels, Play data safety), the check under § 25 TDDDG for the access to the device, a contact for users who ask to reset a marking (e.g. after buying a used device; a moderator then requests a reset in the user file), and a data protection impact assessment. The Limenia integration guide has the details and a template for the impact assessment.

## API

- `LimeniaDevice.isSupported()`: `Future<bool>`, whether the device can give tokens. `false` on platforms other than Android and iOS.
- `LimeniaDevice.requestToken({required String requestHash, int? cloudProjectNumber})`: `Future<DeviceToken>` with `platform` (`android` or `ios`) and `token`. `cloudProjectNumber` is required on Android, the request hash must have 1 to 500 characters there; iOS ignores both.
- `LimeniaDeviceException`: `code` (`LimeniaDeviceException.unsupported`, `invalidArgument` or `failed`), `message` and `nativeCode`.

## Development

In `packages/limenia_device` of the repo:

```sh
flutter pub get
flutter analyze
flutter test
```

The tests mock the method channel `eu.limenia/limenia_device`. They do not run the native code, which needs a real device (Play Integrity) or an iPhone (DeviceCheck).

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Copyright 2026 Karim Belkacem. The license grants no rights to use the name "Limenia".
