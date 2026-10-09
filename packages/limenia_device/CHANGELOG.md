# Changelog

## 0.1.0 (2026-10-05)

First public version, for the device connector of Limenia (API version 0.20.0).

- `LimeniaDevice.isSupported()` and `LimeniaDevice.requestToken({requestHash, cloudProjectNumber})` return a `DeviceToken` (`platform`, `token`), errors as `LimeniaDeviceException` (`unsupported`, `invalid_argument`, `failed`, with `nativeCode`).
- Android: Play Integrity 1.6.0, standard request. The token provider is prepared once per Cloud project number and prepared again once on `INTEGRITY_TOKEN_PROVIDER_INVALID`. `isSupported()` checks for the Google Play Store (`<queries>` for `com.android.vending`). `minSdk` 24.
- iOS: DeviceCheck (`DCDevice.generateToken`, Base64). The request hash is ignored. iOS 15, CocoaPods and Swift Package Manager.
