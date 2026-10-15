# Changelog

## Unreleased

Documentation only; the API of the package is unchanged.

- README: the backend sketch drops `identifiers` sent by the device for reports (`subject.identifiers`), signals and device checks, as the section "Ban evasion across apps" requires; the backend adds them from its own user record.

## 0.12.1 (2026-10-12)

Documentation and spec copy only; the API of the package is unchanged.

- The spec copy is the public OpenAPI description at API version 0.28.0. It adds the optional field `identifiers` (schema `SubjectIdentifiers`, HMACs of e-mail address and phone number for ban evasion across apps) to report subjects (also of review requests), signals, device checks and `PUT /v1/subjects/{externalUserId}`, where `displayName` is now optional.
- The models deliberately do not map `identifiers`: the identifier key stays in the backend of the app, which adds them when it forwards a request. `test/spec_test.dart` lists these fields as left to the backend.
- README: section "Ban evasion across apps".
- README: links point to the pages of the developer docs at https://limenia.eu/docs/ instead of section numbers of the former single-page guide.

## 0.12.0 (2026-10-09)

First release on pub.dev. The widgets of the former package `limenia_ui` are now part of `limenia`, so one package covers the headless API and the widgets. The API is unchanged; it follows Limenia API version 0.22.0, and the spec copy is the public OpenAPI description at 0.25.0.

Breaking:

- `limenia` is now a Flutter package (Flutter 3.35 or newer). It depends only on Flutter. A pure Dart program, e.g. a Dart server, cannot depend on this version and can stay on 0.11.x.
- `limenia_ui` is part of `limenia`: import `package:limenia/ui.dart` instead of `package:limenia_ui/limenia_ui.dart`. The class and function names are the same (`showLimeniaReportSheet`, `LimeniaReportForm`, `showLimeniaAppealSheet`, `LimeniaAppealForm`, `LimeniaStatementOfReasonsView`, `LimeniaRestrictionNotice`, `LimeniaRestrictionScreen`, `LimeniaSubjectStatusBuilder`, `LimeniaUiStrings`, …), as are the texts in German and English. Errors of callbacks are reported to `FlutterError.reportError` with the library name `limenia` instead of `limenia_ui`.

Unchanged:

- The headless API stays at `package:limenia/limenia.dart`.
- The optional Flutter plugin `limenia_device` for device checks stays a package of its own and does not depend on `limenia`.

Also in this version:

- The package lives in the folder `packages/limenia` of the repo `DL3KB/limenia-flutter`, next to `limenia_device`. Tags are named `limenia-vX.Y.Z`.
- One example app in `example/` shows every widget with a fake backend; `example/bin/headless.dart` shows the headless API without widgets.
- The tests of both former packages run together with `flutter test`; the widget tests are in `test/ui`.

Migration:

- Remove `limenia_ui` from `pubspec.yaml`, depend on `limenia: ^0.12.0` and replace the import as above.

## Earlier versions

Versions before 0.12.0 were not published on pub.dev.

- 0.11.0 (2026-10-07): `ReportRequest.goodFaith`, the good-faith confirmation of the reporter (API version 0.22.0, Art. 16(2)(d) DSA).
- 0.10.0 (2026-10-05): device checks with `Limenia.checkDevice`, `DeviceCheckRequest`, `DeviceCheckResult` and `deviceRequestHash` (API version 0.20.0). `LimeniaTransport` got the method `checkDevice`.
- 0.9.0 (2026-10-05): `SorDetails.automation`, whether a decision used automated means (API version 0.19.0, Art. 17(3)(c) DSA).
- 0.8.0 (2026-10-05): signals about users with `Limenia.sendSignals` (API version 0.18.0). `LimeniaTransport` got the method `createSignals`.
- 0.7.0 (2026-10-05): trusted flaggers, warnings and suspension of reporters, and `noticeSource` (API version 0.16.0, Art. 22 and 23 DSA).
- 0.6.0 (2026-10-03): `restoreScope` of a `restore` decision (API version 0.13.2).
- 0.5.0 (2026-10-03): documentation in English; a 401 keeps a request in the queue, all 5xx except 501 and 505 are retried, and the checks follow the backend more closely.
- 0.4.1 (2026-10-03): `ModerationDecision.reviewId` and `ModerationDecision.changesUserStatus` (API version 0.12.2).
- 0.4.0 (2026-10-03): reviews (pre-moderation) with `Limenia.submitForReview` (API version 0.12.0).
- 0.3.1 (2026-10-02): `ModerationDecision.appealId` and `replacesDecisionId` (API version 0.11.0).
- 0.3.0 (2026-10-02): complaints against decisions (Art. 20 DSA) and the event `reports.resolved` for informing reporters (Art. 16(5) DSA).
- 0.2.0 (2026-10-02): classes renamed to the product name Limenia.
- 0.1.0: first version: reports with a queue and retries, the status of a user, decisions with their statement of reasons and webhook events.

The widgets were the separate package `limenia_ui` before 0.12.0:

- `limenia_ui` 0.1.1 (2026-10-07): the English label of `child_safety` is "Protection of minors"; the good-faith confirmation reaches Limenia as `ReportRequest.goodFaith`.
- `limenia_ui` 0.1.0 (2026-10-07): report sheet, complaint form, statement of reasons, restriction notices, texts in German and English, example app.
