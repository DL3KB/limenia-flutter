# Changelog

## Unreleased

Documentation only; no change to the code or the native parts.

- README: clearer wording in the iOS setup: Limenia stores the DeviceCheck key encrypted and never shows it again.

## 0.1.1 (2026-10-09)

First release on pub.dev: install with `limenia_device: ^0.1.1`. No change to the code or the native parts.

- The plugin moved to the folder `packages/limenia_device` of the repo `DL3KB/limenia-flutter`, next to the package `limenia`. A git dependency now needs `path: packages/limenia_device`; the tag `v0.1.0` keeps the old layout.
- `pubspec.yaml` has the metadata for pub.dev (homepage, repository, issue tracker, documentation, topics) and the package folder has its own `LICENSE`.

## 0.1.0 (2026-10-05)

First public version, for the device connector of Limenia (API version 0.20.0).

- `LimeniaDevice.isSupported()` and `LimeniaDevice.requestToken({requestHash, cloudProjectNumber})` return a `DeviceToken` (`platform`, `token`), errors as `LimeniaDeviceException` (`unsupported`, `invalid_argument`, `failed`, with `nativeCode`).
- Android: Play Integrity 1.6.0, standard request. The token provider is prepared once per Cloud project number and prepared again once on `INTEGRITY_TOKEN_PROVIDER_INVALID`. `isSupported()` checks for the Google Play Store (`<queries>` for `com.android.vending`). `minSdk` 24.
- iOS: DeviceCheck (`DCDevice.generateToken`, Base64). The request hash is ignored. iOS 15, CocoaPods and Swift Package Manager.
