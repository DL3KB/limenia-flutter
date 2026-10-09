# Limenia for Flutter

Flutter packages for apps that use [Limenia](https://limenia.eu), the moderation service for reports, decisions and complaints under the Digital Services Act (DSA).

| Package | Folder | What it is for |
|---|---|---|
| [`limenia`](https://pub.dev/packages/limenia) | [`packages/limenia`](packages/limenia) | Reports, complaints, review requests, signals, device checks, the status of a user and decisions with their statement of reasons (`package:limenia/limenia.dart`), plus ready-made widgets: report sheet, complaint form, statement of reasons and notices for restricted accounts (`package:limenia/ui.dart`). |
| [`limenia_device`](https://pub.dev/packages/limenia_device) | [`packages/limenia_device`](packages/limenia_device) | Optional plugin for the device connector: gets a device token from Play Integrity (Android) or DeviceCheck (iOS). |

## Which package do I need?

- Every app: `limenia`.
- Only if your app checks devices with the device connector: also `limenia_device`. It has native code and does not depend on `limenia`.

```yaml
dependencies:
  limenia: ^0.12.0
  limenia_device: ^0.1.1 # optional, for device checks only
```

The app never talks to Limenia directly and never holds the API key: it sends through your own backend, which forwards to the Limenia API. The [integration guide](https://limenia.eu/docs/integration.md) and the [OpenAPI description](https://limenia.eu/openapi/v1.yaml) describe the API and the webhooks; the README of each package describes its use.

## Development

Each package is checked on its own, in its folder:

```sh
cd packages/limenia # or packages/limenia_device
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

The CI (`.github/workflows/ci.yml`) runs these checks and `flutter pub publish --dry-run` for both packages on every push. Each package has its own `CHANGELOG.md`, and tags are named after the package: `limenia-vX.Y.Z` and `limenia_device-vX.Y.Z`.

## License

Apache License 2.0, see [LICENSE](LICENSE). Each package carries its own `LICENSE` and `NOTICE`. Copyright 2026 Karim Belkacem. The license grants no rights to use the name "Limenia".
