# limenia

Flutter package for apps that use [Limenia](https://limenia.eu), the moderation service for reports, decisions and complaints under the Digital Services Act (DSA). It has two parts:

- **`package:limenia/limenia.dart`**, the headless API: build, validate and reliably send reports, complaints (appeals), review requests and signals about users, check devices with the device connector, track a user's moderation status, read decisions with their statement of reasons, and inform reporters about the outcome.
- **`package:limenia/ui.dart`**, ready-made widgets for the parts users see: report sheet, complaint form, statement of reasons and notices for restricted accounts (see [Widgets](#widgets-packagelimeniauidart)).

The Flutter plugin [`limenia_device`](https://pub.dev/packages/limenia_device) is optional and only needed for the device connector: it gets the token of the device for a device check (Play Integrity on Android, DeviceCheck on iOS). It is a package of its own, so apps without device checks carry no native code. Both packages live in the repo [DL3KB/limenia-flutter](https://github.com/DL3KB/limenia-flutter).

## What the package is and what it is not

- It is a Flutter package without native code and without runtime dependencies besides Flutter. The only platform code, the device token for device checks, lives in the separate plugin `limenia_device`, which apps add only if they use the device connector.
- Up to 0.11.0 the API was a pure Dart package and the widgets were the separate package `limenia_ui`. Since 0.12.0 both are in this package; see [Upgrading from `limenia_ui`](#upgrading-from-limenia_ui).
- The headless API (`package:limenia/limenia.dart`) contains no widgets. Use the widgets of `package:limenia/ui.dart`, or build the dialog, the report form and the notice for a suspension yourself.
- The Limenia API key stays in the backend ([integration guide](https://limenia.eu/docs/integration.md), section 2.2). The app never talks to Limenia directly, only through the app's backend. For this, you implement the interface `LimeniaTransport`.
- The package is written by hand, not generated. A test compares enums and limits with a copy of the API specification in `spec/openapi.yaml` (see [API specification](#api-specification)).

The API itself, the webhooks and example backends are described in the [integration guide of Limenia](https://limenia.eu/docs/integration.md) and the [OpenAPI description](https://limenia.eu/openapi/v1.yaml).

## Installation

Add the package from pub.dev to the app's `pubspec.yaml`:

```yaml
dependencies:
  limenia: ^0.12.0

flutter:
  uses-material-design: true # the widgets use Material icons
```

For device checks, also add the optional plugin (see [Device checks](#device-checks)):

```yaml
dependencies:
  limenia_device: ^0.1.1
```

- Requires Flutter 3.35 or newer.
- The widgets are Material widgets and need `MaterialLocalizations` for the locales of your app. Apps in German usually have them already through `flutter_localizations` (`GlobalMaterialLocalizations.delegates`).
- New versions are listed in `CHANGELOG.md`.

### Upgrading from `limenia_ui`

- Remove `limenia_ui` from `pubspec.yaml` and depend on `limenia: ^0.12.0` alone.
- Replace `import 'package:limenia_ui/limenia_ui.dart';` with `import 'package:limenia/ui.dart';`. The class and function names are the same.
- `limenia` now depends on Flutter. A pure Dart program (e.g. a Dart server) cannot depend on 0.12.0; it can stay on `limenia` 0.11.x.

## Quick start

```dart
import 'package:limenia/limenia.dart';

final limenia = Limenia(
  transport: MyBackendTransport(), // see the next section
  pendingReports: MyPendingStore(), // optional, otherwise in memory only
);

// When the app starts: send reports that are still pending.
await limenia.sendPendingReports();

final result = await limenia.report(
  ReportRequest.content(
    reasonCategory: ReasonCategory.harassmentHate,
    reasonText: 'Insult in the comment',
    content: ReportedContent(
      externalContentId: 'comment_5521',
      contentType: 'comment',
      text: 'Text of the comment',
    ),
    author: ReportedUser('u_112', displayName: 'maxi_99'),
  ),
);
```

Or let the report sheet of the widgets collect category, text and the good-faith confirmation, and send through the same `limenia`:

```dart
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

final result = await showLimeniaReportSheet(
  context,
  goodFaith: GoodFaithConfirmation.optional,
  onSubmit: (draft) => limenia.report(
    ReportRequest.content(
      reasonCategory: draft.reasonCategory,
      reasonText: draft.reasonText,
      goodFaith: draft.goodFaithConfirmed,
      content: ReportedContent(externalContentId: comment.id, contentType: 'comment'),
      author: ReportedUser(comment.authorId),
    ),
  ),
);
```

## Implementing `LimeniaTransport`

The interface has eight methods: `createReport(request, {idempotencyKey})`, `getSubjectStatus(externalUserId)`, `createAppeal(request, {idempotencyKey})`, `getAppealStatus(appealId)`, `createReview(request, {idempotencyKey})`, `getReviewStatus(reviewId)`, from 0.8.0 `createSignals(request, {idempotencyKey})` and from 0.10.0 `checkDevice(request)`. It is the only place where the app talks to its backend.

Error contract the package relies on:

- On an error response, throw a `LimeniaException`, preferably with `LimeniaException.fromResponse(status:, body:, retryAfter:)`. Status and code decide what happens: errors that may pass later (`isRetryable`: 408, 429, 5xx except 501 and 505, 403 `tenant_not_active`) are retried, a 401 keeps the request in the queue without retrying it right away, and every other error rejects it (403 `reporter_suspended` too: nothing is kept, and the `suspendedUntil` of the problem is in `LimeniaException.suspendedUntil`). Map errors of your own backend to a `LimeniaException` with a matching status as well. Map an expired login of the app to 401: the request then waits until the user is logged in again and you call `sendPending…`.
- On network errors and timeouts, simply let the exception propagate. The package retries and holds on to the request.
- If the answer of your backend cannot be read, let the `FormatException` of `fromJson` propagate. The request is rejected, because sending it again would get the same answer.
- An `Error` (programming error) is never retried. The package removes the request from its queue, so that it does not block the others, and throws the error on.

The contract is the same for reports, complaints, review requests and signals. Device checks use the same exceptions, but `limenia.checkDevice` never retries or queues: it throws them to the caller, because a device token is single-use.

The two examples are only templates. The app adds the required dependencies (`http`, `cloud_functions`) itself. The package depends on none of them.

### Example 1: `package:http` against your own REST backend

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limenia/limenia.dart';

final class HttpTransport implements LimeniaTransport {
  HttpTransport({required this.baseUrl, required this.sessionToken, http.Client? client})
      : _client = client ?? http.Client();

  final Uri baseUrl; // e.g. https://api.my-app.example/
  final Future<String> Function() sessionToken; // token from the app's login
  final http.Client _client;

  Future<Map<String, String>> _headers({String? idempotencyKey}) async => {
        'Authorization': 'Bearer ${await sessionToken()}',
        'Content-Type': 'application/json',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };

  @override
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey}) async {
    final response = await _client
        .post(
          baseUrl.resolve('moderation/reports'),
          headers: await _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 15)); // TimeoutException is an Exception and is retried
    _check(response);
    return ReportReceipt.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<SubjectStatus> getSubjectStatus(String externalUserId) async {
    final response = await _client.get(
      baseUrl.resolve('moderation/subjects/${Uri.encodeComponent(externalUserId)}/status'),
      headers: await _headers(),
    );
    _check(response);
    return SubjectStatus.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey}) async {
    final response = await _client
        .post(
          baseUrl.resolve('moderation/appeals'),
          headers: await _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 15));
    _check(response);
    return AppealReceipt.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<AppealStatusInfo> getAppealStatus(String appealId) async {
    final response = await _client.get(
      baseUrl.resolve('moderation/appeals/${Uri.encodeComponent(appealId)}'),
      headers: await _headers(),
    );
    _check(response);
    return AppealStatusInfo.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) async {
    final response = await _client
        .post(
          baseUrl.resolve('moderation/reviews'),
          headers: await _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 15));
    _check(response);
    return ReviewReceipt.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<ReviewStatusInfo> getReviewStatus(String reviewId) async {
    final response = await _client.get(
      baseUrl.resolve('moderation/reviews/${Uri.encodeComponent(reviewId)}'),
      headers: await _headers(),
    );
    _check(response);
    return ReviewStatusInfo.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) async {
    final response = await _client
        .post(
          baseUrl.resolve('moderation/signals'),
          headers: await _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 15));
    _check(response);
    return SignalsReceipt.fromJson(jsonDecode(response.body) as JsonMap);
  }

  @override
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) async {
    final response = await _client
        .post(baseUrl.resolve('moderation/devices/check'), headers: await _headers(), body: jsonEncode(request.toJson()))
        .timeout(const Duration(seconds: 15));
    _check(response);
    return DeviceCheckResult.fromJson(jsonDecode(response.body) as JsonMap);
  }

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw LimeniaException.fromResponse(
      status: response.statusCode,
      body: response.body,
      retryAfter: response.headers['retry-after'],
    );
  }
}
```

### Example 2: `cloud_functions` (callable)

A callable has no HTTP headers. The example therefore passes the Idempotency-Key in the payload, and the function sets the header from it. The function knows the user from the login (`request.auth`).

```dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:limenia/limenia.dart';

final class CallableTransport implements LimeniaTransport {
  CallableTransport([FirebaseFunctions? functions]) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey}) async {
    final data = await _call('createReport', {'idempotencyKey': idempotencyKey, 'report': request.toJson()});
    return ReportReceipt.fromJson(data);
  }

  @override
  Future<SubjectStatus> getSubjectStatus(String externalUserId) async =>
      SubjectStatus.fromJson(await _call('getSubjectStatus', {'externalUserId': externalUserId}));

  @override
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey}) async =>
      AppealReceipt.fromJson(
          await _call('createAppeal', {'idempotencyKey': idempotencyKey, 'appeal': request.toJson()}));

  @override
  Future<AppealStatusInfo> getAppealStatus(String appealId) async =>
      AppealStatusInfo.fromJson(await _call('getAppealStatus', {'appealId': appealId}));

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) async =>
      ReviewReceipt.fromJson(
          await _call('createReview', {'idempotencyKey': idempotencyKey, 'review': request.toJson()}));

  @override
  Future<ReviewStatusInfo> getReviewStatus(String reviewId) async =>
      ReviewStatusInfo.fromJson(await _call('getReviewStatus', {'reviewId': reviewId}));

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) async =>
      SignalsReceipt.fromJson(
          await _call('createSignals', {'idempotencyKey': idempotencyKey, 'signals': request.toJson()}));

  @override
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) async =>
      DeviceCheckResult.fromJson(await _call('checkDevice', {'check': request.toJson()}));

  Future<JsonMap> _call(String name, Map<String, Object?> payload) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(payload);
      return Map<String, Object?>.from(result.data! as Map);
    } on FirebaseFunctionsException catch (e) {
      // Best: the function passes on Limenia's problem with its HTTP status
      // in `details`, e.g. {status: 409, code: 'appeal_already_open', ...}.
      final details = e.details;
      final status = details is Map && details['status'] is int ? details['status'] as int : _status(e.code);
      throw LimeniaException.fromResponse(status: status, body: details);
    }
  }

  // The HTTP status of each callable error code. Network errors show up as
  // 'unavailable' and are retried with 503.
  static int _status(String code) => switch (code) {
        'invalid-argument' || 'failed-precondition' || 'out-of-range' => 400,
        'unauthenticated' => 401,
        'permission-denied' => 403,
        'not-found' => 404,
        'already-exists' || 'aborted' => 409,
        'resource-exhausted' => 429,
        'unimplemented' => 501,
        'unavailable' => 503,
        'deadline-exceeded' => 504,
        _ => 500, // internal, unknown, data-loss, cancelled
      };
}
```

`fromResponse` reads `details` as a problem object if it is a map with string keys, also the `Map<Object?, Object?>` that `cloud_functions` returns. Let your function put Limenia's HTTP status and problem body into `details`: then Limenia's own status and code decide, e.g. 403 `tenant_not_active` keeps a request in the queue while 403 `appeal_not_allowed` rejects it. Without them, only the callable error code is left, and the table above maps it.

## What your backend must do

The backend is the trust boundary. The reporter's device can send arbitrary data.

- It checks the app's login itself.
- It sets the reporter from the signed-in user, with `ReportRequest.withReporter(uid)` or by overwriting `reporter.externalUserId`. It never takes this value from the client.
- It sets `trustedFlaggerId` (API version 0.16.0) only from its own records of who acts for a trusted flagger (`ReportRequest.withTrustedFlagger(id)`, or `null` for everyone else), and overwrites whatever the device sent. Otherwise any device could claim the priority of a trusted flagger.
- Likewise, for a complaint it sets `appellant.externalUserId` from the login (`AppealRequest.withAppellantUser(uid)`). Limenia then checks whether exactly this person is affected or reported the case.
- For a review request, it sets the author (`subject.externalUserId`) from the login (`ReviewRequest.withAuthor(...)`).
- For signals (API version 0.18.0), it sets the user of every signal from the login (`SignalsRequest.withExternalUserId(uid)`) and forwards the request to `POST /v1/signals`, which is a new endpoint of your backend. Better still, it derives the values from its own data and lets the device send nothing but the trigger, see [Signals](#signals).
- For device checks (API version 0.20.0), it issues the request hash itself (`deviceRequestHash(uid, newDeviceNonce())`, single use, kept for a few minutes), sets the user from the login (`DeviceCheckRequest.withExternalUserId(uid)`), forwards only a request hash it issued to this user and forwards the request to `POST /v1/devices/check`, a new endpoint of your backend, without an `Idempotency-Key`. It accepts `platform: test` only where test tokens make sense (debug builds, test accounts). It never stores or logs the token. See [Device checks](#device-checks).
- Where possible, it loads the snapshot (text, media URLs, author) from its own database instead of trusting the device.
- It passes the `Idempotency-Key` header on to Limenia unchanged.
- For ban evasion across apps (API version 0.28.0), it adds `identifiers` from its own user record when it forwards a request and drops any `identifiers` the device sent. See [Ban evasion across apps](#ban-evasion-across-apps).
- It returns Limenia's status, problem body and `Retry-After` unchanged. The problem body of 403 `reporter_suspended` carries `suspendedUntil`; without it the app only knows that the reporter is suspended, not until when.
- For the status, it only answers for the signed-in user. It returns the status of a complaint only to the person who filed it, and the status of a review only to the author. For this, it remembers which `appealId` or `reviewId` belongs to which user.
- It keeps the API key in a secret store.

Sketch with a small TypeScript client for the Limenia API (`@limenia/client`, not published on npm; the same calls are plain HTTP requests, see the reference backends in [DL3KB/limenia-examples](https://github.com/DL3KB/limenia-examples)) as Express handlers (Cloud Functions work the same way):

```ts
import express from "express";
import {
  createLimeniaClient,
  LimeniaError,
  type CreateAppealRequest,
  type CreateReportRequest,
  type CreateReviewRequest,
  type CreateSignalsRequest,
  type DeviceCheckRequest,
} from "@limenia/client";

const limenia = createLimeniaClient({ apiKey: process.env.LIMENIA_API_KEY!, baseUrl: process.env.LIMENIA_BASE_URL! });
const app = express();
app.use(express.json());

function sendError(res: express.Response, err: unknown) {
  if (!(err instanceof LimeniaError)) throw err; // network error: 500, the app retries
  if (err.retryAfter !== undefined) res.set("Retry-After", String(err.retryAfter));
  const { status, code, title, detail, errors } = err; // errors: the field errors, if any
  const suspendedUntil = err.problem?.suspendedUntil; // with 403 reporter_suspended
  res.status(status).json({ status, code, title, detail, errors, suspendedUntil });
}

app.post("/moderation/reports", requireLogin, async (req, res) => {
  const uid = req.user.uid; // from your own login
  const body = req.body as CreateReportRequest;
  // Reporter from the login, load the snapshot from your own database where possible.
  // trustedFlaggerId only from your own records (undefined for everyone else), never from the device.
  const report: CreateReportRequest = {
    ...body,
    reporter: { externalUserId: uid },
    trustedFlaggerId: await trustedFlaggerOf(uid),
  };
  try {
    res.status(201).json(await limenia.createReport(report, { idempotencyKey: req.get("Idempotency-Key")! }));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/moderation/subjects/:id/status", requireLogin, async (req, res) => {
  if (req.params.id !== req.user.uid) return res.status(403).json({ status: 403, code: "forbidden" });
  try {
    res.json(await limenia.getSubjectStatus(req.params.id));
  } catch (err) {
    sendError(res, err);
  }
});

app.post("/moderation/appeals", requireLogin, async (req, res) => {
  const body = req.body as CreateAppealRequest;
  // The person who complains comes from the login, never from the device.
  const appeal: CreateAppealRequest = { ...body, appellant: { type: body.appellant.type, externalUserId: req.user.uid } };
  try {
    const created = await limenia.createAppeal(appeal, { idempotencyKey: req.get("Idempotency-Key")! });
    await rememberAppeal(created.appealId, req.user.uid); // for the status and appeal.resolved
    res.status(201).json(created);
  } catch (err) {
    sendError(res, err);
  }
});

app.post("/moderation/reviews", requireLogin, async (req, res) => {
  const body = req.body as CreateReviewRequest;
  // The author comes from the login, never from the device. Load the content from your own database where possible.
  const review: CreateReviewRequest = {
    ...body,
    subject: { externalUserId: req.user.uid, displayName: body.subject?.displayName },
  };
  try {
    const created = await limenia.createReview(review, { idempotencyKey: req.get("Idempotency-Key")! });
    await rememberReview(created.reviewId, req.user.uid); // for the status and review.decided
    res.status(201).json(created);
  } catch (err) {
    sendError(res, err);
  }
});

app.post("/moderation/signals", requireLogin, async (req, res) => {
  const body = req.body as CreateSignalsRequest;
  // The user comes from the login, never from the device. Recompute values from your own data where possible.
  const signals: CreateSignalsRequest = {
    signals: body.signals.map((s) => ({ ...s, externalUserId: req.user.uid })),
  };
  try {
    res.status(202).json(await limenia.sendSignals(signals, { idempotencyKey: req.get("Idempotency-Key")! }));
  } catch (err) {
    sendError(res, err);
  }
});

app.post("/moderation/devices/check/start", requireLogin, async (req, res) => {
  // Request hash for the device token (the formula of deviceRequestHash in the Dart package).
  const nonce = crypto.randomBytes(32).toString("base64url");
  const hash = crypto.createHash("sha256").update(`limenia:${req.user.uid}:${nonce}`).digest("base64url");
  await rememberDeviceHash(req.user.uid, hash); // single use, a few minutes
  res.json({ requestHash: hash });
});

app.post("/moderation/devices/check", requireLogin, async (req, res) => {
  const body = req.body as DeviceCheckRequest;
  // The user comes from the login. Android: only a request hash this backend issued to this user counts, once.
  if (body.platform === "android" && !(body.requestHash && (await takeDeviceHash(req.user.uid, body.requestHash)))) {
    return res.status(400).json({ status: 400, code: "validation_failed" });
  }
  try {
    res.json(await limenia.checkDevice({ ...body, externalUserId: req.user.uid }));
  } catch (err) {
    sendError(res, err);
  }
});
```

`trustedFlaggerOf`, `rememberAppeal`, `rememberReview`, `rememberDeviceHash` and `takeDeviceHash` are your own storage and records (`crypto` is `node:crypto`). `limenia.checkDevice` is the helper of `@limenia/client` for `POST /v1/devices/check` (API version 0.20.0). Pass on `GET /v1/appeals/{appealId}` the same way with `limenia.getAppeal(appealId)`, after you have checked that the complaint belongs to the signed-in user. Likewise `GET /v1/reviews/{reviewId}` with `limenia.getReview(reviewId)`, only for the author.

The field format of the problem body is in Limenia's [integration guide](https://limenia.eu/docs/integration.md), section 3.1. `LimeniaException.fromResponse` reads `code`, `title`, `detail` and `errors`. `LimeniaError` of `@limenia/client` keeps the field errors as `err.errors` (as of API version 0.13.2), and the sketch passes them on. `fieldErrors` then holds them for `validation_failed` and also for the more specific codes that name a field, such as `review_type_unknown` (`/type` with `unknown`). With an older client, `errors` is missing and `fieldErrors` stays empty for errors of Limenia. The check in the package covers the same fields before anything is sent.

## Reports

- `ReportRequest.content(...)` reports a piece of content. Always set the `author`, otherwise moderators cannot warn or suspend the user.
- `ReportRequest.user(...)` reports a user without a single piece of content, e.g. a profile.
- `externalReportId` (optional, at most 128 characters) is the ID of the report in the app. Limenia sends it back in the event `reports.resolved` so that the app can tell the reporters the outcome (see [Informing reporters](#informing-reporters)).
- `source` is `ReportSource.user` (default) or `ReportSource.system` for your own detection. With `system`, leave out the reporter, `goodFaith` and `trustedFlaggerId`.
- `goodFaith` (optional, API version 0.22.0) says that the reporting person confirmed in good faith that the information and allegations in the report are accurate and complete (Art. 16(2)(d) DSA), e.g. with the checkbox of the [report sheet](#report-sheet) (`goodFaith: draft.goodFaithConfirmed`). `null` (the default) leaves the field out, which Limenia counts as not confirmed, the same as `false`. Only with `ReportSource.user`: with `system`, `validateReport` rejects any value, also `false` (`/goodFaith` with `invalid`), as Limenia does (`validation_failed`). Limenia stores the confirmation and shows it to moderators, but does not treat the report differently. Unlike the reporter, it is a statement of the person on the device, so your backend can pass it on. Limenia before 0.22.0 ignores the field.
- `trustedFlaggerId` (optional, ULID, API version 0.16.0) marks a report of a trusted flagger (Art. 22 DSA), see [Trusted flaggers, warnings and suspension](#trusted-flaggers-warnings-and-suspension).
- `ReasonCategory` contains the codes of the default policies (`spam`, `harassmentHate`, `violence`, `sexualContent`, `childSafety`, `fraud`, `copyright`, `privacy`, `selfHarm`, `other`) and `defaults` in the order of the onboarding. Limenia only checks the pattern `^[a-z0-9_]{2,40}$` (`ReasonCategory.isValid`). Tenants can change and add codes, so agree on them with the tenant.
- `ReasonCategory.childSafetyCategories` (`child_safety`, `protection_of_minors`) are child safety categories. The case becomes urgent immediately, and Limenia never downloads the media. It only keeps the URL.

### Handling the result

`limenia.report(...)` does not throw on transport errors. Instead, it returns a `ReportResult`:

```dart
switch (await limenia.report(request)) {
  case ReportSent(:final receipt, :final reporterWarning):
    showSnackBar('Thanks, your report was received (${receipt.reportId}).');
    if (reporterWarning != null) showReporterWarning(); // see "Trusted flaggers, warnings and suspension"
  case ReportQueued():
    showSnackBar('We will send your report as soon as you are online again.');
  case ReportFailed(isReporterSuspended: true, :final suspendedUntil):
    // Not stored and not queued. suspendedUntil can be null.
    showSnackBar('You cannot report until ${suspendedUntil ?? 'later'}.');
  case ReportFailed(:final fieldErrors):
    // Not stored. An unchanged second attempt fails again.
    showSnackBar('The report was rejected.'); // fieldErrors: invalid fields, from the package or from Limenia
  case ReportExpired():
    break; // only comes from sendPending()
}
```

`report(...)` includes the `idempotencyKey` in every result. If the report already has an ID in the app, pass `idempotencyKey: 'report-<id>'`. Otherwise the package creates a ULID (`newIdempotencyKey()`). A key may only belong to one report.

### Retries: `RetryPolicy`

Defaults:

- `maxAttempts`: 3 attempts per call of `report`, then the report stays in the queue.
- `initialDelay` 1 s, doubled up to `maxDelay` 8 s.
- `maxInlineWait`: 10 s. If Limenia asks for a longer pause via `Retry-After`, the report is queued immediately instead of making the user wait.
- `maxPendingAge`: 7 days. `sendPending()` drops older reports as `ReportExpired`.

What happens after an error:

- Network errors, timeouts and errors that may pass later (`LimeniaException.isRetryable`: 408, 429, 5xx except 501 and 505, also those of a CDN in front of your backend, and 403 `tenant_not_active`) are retried with backoff and then queued.
- A 401 is queued at once, without retrying right away: the login of the app (or the API key of its backend) has to be renewed first. Call `sendPending…` again after the login.
- All other errors reject the request (`ReportFailed`), as does an answer that cannot be read (`FormatException`). Sending it again unchanged would fail again.
- 403 `reporter_suspended` (API version 0.16.0) is one of those: the request is dropped from the queue at once, not kept like a 401 or a 5xx, and `ReportFailed.isReporterSuspended` and `ReportFailed.suspendedUntil` tell the app (see below). This also holds for a queued report that `sendPending()` finds suspended, and it holds whatever status your backend gives the problem. The other queued reports of the same person are dropped the same way as `sendPending()` reaches them.

Limenia keeps an Idempotency-Key for at least 24 hours. If a report is sent again after that, it counts as a new one. That matters only in the rare case that the first attempt reached Limenia and only the response was lost: the report then arrives twice, and Limenia attaches it to the same case, as long as that case is open. For complaints and review requests, see their sections.

### Trusted flaggers, warnings and suspension

Art. 22 and 23 DSA, API version 0.16.0. Limenia knows reporters only by a pseudonym, so the app takes part in three places:

- **Trusted flaggers.** If the reporting person acts for a trusted flagger of the tenant (an organisation recognised under Art. 22), the backend of the app sets `trustedFlaggerId` (the ULID of the flagger in Limenia). The app decides who that is, e.g. through its own account of the organisation. Limenia then gives the case at least the priority `high` and marks it; the statement of reasons names `NoticeSource.trustedFlagger` (see [Decisions](#decisions-and-statement-of-reasons)). `trustedFlaggerId` is only allowed with `ReportSource.user`; `validateReport` checks that and the ULID format before anything is sent (`/trustedFlaggerId` with `invalid`). Whether the flagger exists and is active only Limenia checks (`validation_failed`, field error `unknown` at `/trustedFlaggerId`). Never let the device choose the value: use `ReportRequest.withTrustedFlagger(...)` in your backend, as you use `withReporter(...)`.
- **Warning.** A moderator can warn a reporter for frequently submitting manifestly unfounded reports. While the warning stands, every answer to a report of this person carries `reporterWarning` (`ReportReceipt.reporterWarning`, also `ReportSent.reporterWarning`, with `issuedAt`). Show the person a notice from your terms that further unfounded reports can lead to a suspension. The first answer with the warning counts as delivered; only then can a moderator suspend. It also arrives in the results of `sendPendingReports()`. A repeated request with the same idempotency key gets the original answer, so show the warning whenever it is set instead of remembering that you showed it.
- **Suspension.** After a warning a moderator can suspend the processing of the person's reports for a time. Limenia then refuses `POST /v1/reports` and the complaints of that person as a reporter (`POST /v1/appeals`, `AppealRequest.reporter`) with 403 `reporter_suspended`, and stores nothing. The package drops such a request instead of queuing it, because it would only be refused again: `ReportFailed` or `AppealFailed` with `code == 'reporter_suspended'`, `isReporterSuspended` and `suspendedUntil` (the end of the suspension, `null` if your backend did not pass `suspendedUntil` of the problem on). The affected user can always complain against a decision about them (`AppealRequest.subject`): that is never suspended.

```dart
switch (await limenia.appeal(request)) {
  case AppealFailed(isReporterSuspended: true, :final suspendedUntil):
    showSnackBar('You cannot file complaints as a reporter until ${suspendedUntil ?? 'later'}.');
  case AppealSent() || AppealQueued() || AppealFailed() || AppealExpired():
    break; // as above
}
```

`LimeniaException.isReporterSuspended` and `LimeniaException.suspendedUntil` give the same on the exception itself. `reporter_suspended` is never retryable (`isRetryable` is `false`).

### `sendPending()`

`limenia.sendPendingReports()` sends the queue, oldest first, one attempt per report. It stops at the first report that is queued again, e.g. after a network error or a 401. Call it when the app starts (after the login is restored), when it returns to the foreground and when the connection is restored. If the transport throws an `Error` for one report, that report is removed and the error is thrown; the next call goes on with the others.

### `PendingReportStore`

Without a store of your own, the package keeps the queue in memory only (`InMemoryPendingReportStore`), and the queue is lost when the app exits. For persistence, implement `load()`, `put()` and `remove()`. Sketch with `shared_preferences`, one JSON list under one key:

```dart
final class PrefsPendingStore implements PendingReportStore {
  PrefsPendingStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'limenia.pendingReports';

  List<PendingReport> _read() => [
        for (final e in jsonDecode(_prefs.getString(_key) ?? '[]') as List)
          PendingReport.fromJson(e as JsonMap),
      ];

  Future<void> _write(List<PendingReport> all) =>
      _prefs.setString(_key, jsonEncode([for (final r in all) r.toJson()]));

  @override
  Future<List<PendingReport>> load() async => _read()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> put(PendingReport report) =>
      _write([..._read().where((r) => r.idempotencyKey != report.idempotencyKey), report]);

  @override
  Future<void> remove(String idempotencyKey) =>
      _write(_read().where((r) => r.idempotencyKey != idempotencyKey).toList());
}
```

Privacy: pending reports contain content and user IDs. The package deletes them after sending (and after `maxPendingAge`). Never log them. If possible, use encrypted storage.

### Validation

`validateReport(request, idempotencyKey:)` checks Limenia's limits (`ReportLimits`) with the same fields and codes as the backend and returns a list of `FieldError`. `report(...)` calls it itself and, on errors, returns `ReportFailed` with a `ReportValidationException` without queuing anything. To pre-check media links, there is `isAllowedMediaUrl(url)`: https, no credentials, no private or internal addresses, at most 2048 characters.

Lengths count characters (Unicode code points), not bytes or UTF-16 code units, as the backend does. From API version 0.13.2 this also holds for media URLs: a URL of 2048 characters with umlauts or emoji passes, a longer one gets the code `too_long` (field e.g. `/content/media/0/url`), any other rejected one `invalid`.

The check in the package only saves a round trip. The server remains authoritative. The check may be more lenient than the backend in rare cases, but never stricter, so it never blocks a report that Limenia would accept. Tests pin it to the verdicts of the backend (see [Tests](#tests)).

## Complaints

Two groups can file a complaint against a decision (Art. 20 DSA):

- `AppealRequest.subject(...)`: the affected user, against a restrictive decision, i.e. removing or restricting content, warning, suspending, or rejecting a review request (`rejectSubmission`). The affected user cannot complain against `dismiss` and `restore`.
- `AppealRequest.reporter(...)`: a person who reported the case, against any decision about it, especially against a dismissal. Limenia recognizes them by the hash of their ID from the report and does not store the ID.

The deadline is six calendar months from the decision. There is at most one open complaint per decision and person.

```dart
final result = await limenia.appeal(
  AppealRequest.subject(
    decisionId: decision.id, // from decision.created
    externalUserId: currentUserId, // the backend sets it from the login
    text: complaintText, // 1 to 5000 characters, plain text
    externalAppealId: 'appeal-$localId', // optional, comes back in appeal.resolved
  ),
  idempotencyKey: 'appeal-$localId', // optional, otherwise a new ULID
);
switch (result) {
  case AppealSent(:final receipt):
    showSnackBar('Your complaint was received.'); // remember receipt.appealId
  case AppealQueued():
    showSnackBar('We will send your complaint as soon as you are online again.');
  case AppealFailed(:final code):
    showSnackBar(switch (code) {
      'appeal_window_closed' => 'The deadline for a complaint has passed.',
      'appeal_already_open' => 'You have already filed a complaint against this decision.',
      'appeal_not_allowed' => 'No complaint is possible against this decision.',
      _ => 'The complaint was rejected.', // not_found, validation_failed (fieldErrors) or the check in the package
    });
  case AppealExpired():
    break; // only comes from sendPendingAppeals()
}
```

- Sending, retries and the queue work as for reports: the same `RetryPolicy`, the same Idempotency-Key on every retry, and `Retry-After` is respected. `limenia.sendPendingAppeals()` sends complaints that are still pending. Call it together with `sendPendingReports()`.
- For a persistent queue, pass `Limenia(pendingAppeals: ...)` with your own `PendingAppealStore` implementation (same methods as `PendingReportStore`, JSON from `PendingAppeal.toJson()`). Without it, complaints are kept in memory only. They contain the person's text: do not log them, delete them after sending.
- `AppealFailed.code` gives the reason: `appeal_not_allowed` (403), `appeal_window_closed` (409), `appeal_already_open` (409), `idempotency_key_reused` (409, the key was used for another complaint), `not_found` (404, decision unknown), `reporter_suspended` (403, API version 0.16.0: a complaint of a reporter whose reports are suspended, see `AppealFailed.isReporterSuspended` and `suspendedUntil`; never for the affected user) or `validation_failed` (400). If the check in the package fails, `code` is `null` and `fieldErrors` is filled.
- A complaint sent again from the queue more than 24 hours after the first attempt counts as a new one. If the first attempt had arrived (and only the answer was lost), Limenia answers `appeal_already_open` while that complaint is open, and the app does not learn its `appealId`; once it is resolved, a second complaint is created. Set `externalAppealId`, so that `appeal.resolved` can be matched either way.
- `validateAppeal(request, idempotencyKey:)` checks the limits from `AppealLimits` up front: decision ID in ULID format, user ID and `externalAppealId` 1 to 128 characters, text 1 to 5000 characters. Only Limenia checks whether the complaint is admissible.
- `limenia.appealStatus(appealId)` returns `AppealStatusInfo` with `status` (`open`, `inReview`, `resolved`) and, once resolved, `outcome`, `statementText`, `resolvedAt` and, if applicable, `newDecisionId`. This is the fallback in case `appeal.resolved` was lost. The method throws transport errors.

### Result of a complaint

The backend receives the event `appeal.resolved` (`AppealResolvedEvent`) and passes it on to the app:

- `appeal.outcome` is `AppealOutcome.upheld` (the decision stands) or `AppealOutcome.changed` (a new decision replaces it).
- Show `appeal.statementText` as plain text to the person who complained. The text contains the moderator's reasons and the notice about out-of-court dispute settlement (Art. 21 DSA).
- With `changed`, the ID of the new decision is in `appeal.newDecisionId`. The decision itself also arrives as `decision.created`. Only on that event does the app carry out the action, e.g. restoring or removing content. After a complaint against `removeContent` or `restrictContent`, a `restore` lifts only the restriction of the content (`restoreScope` is `RestoreScope.content`), see [Decisions](#decisions-and-statement-of-reasons).
- You can match the event via `appeal.id` (the `appealId` from the response) or `appeal.externalAppealId`.

## Informing reporters

Under Art. 16(5) DSA, reporters learn how their report was decided. After every decision on a case with reports from users, Limenia sends the event `reports.resolved` (`ReportsResolvedEvent`) in addition to `decision.created`:

- `reports.reports` lists the reports with `reportId` (from `ReportReceipt.reportId`) and, if set, `externalReportId`. The app uses these to find the reporting users. Limenia only knows their IDs as a hash.
- An event contains at most 100 reports. With more reports, several events arrive with the same `decisionId`. Each event has its own ID. Limenia sends at most 100 such events per decision, so it answers at most 10,000 reporters.
- If a complaint changes the decision later, no new `reports.resolved` arrives. The new decision comes as `decision.created` with `appealId` and `replacesDecisionId`. Inform the reporters of the case yourself if they should learn about it.
- `action`, `policies` and `decidedAt` describe the decision in short form. `appealDeadline` is the end of the complaint period.
- System reports (`ReportSource.system`) are not included.
- Reporters can file a complaint until `appealDeadline` with `AppealRequest.reporter(decisionId: reports.decisionId, ...)`, also against a dismissal (`dismiss`).

## Reviews (pre-moderation)

This section follows API version 0.13.2. The format of `review.decided` matches what Limenia sends.

With a review, Limenia checks content **before** the app publishes it, such as a profile photo, a listing or a profile text. For content that is already published, a report remains the right way. The tenant defines which review types exist, per app in the dashboard. `type` holds the code of the type, e.g. `profile_photo` (pattern `^[a-z0-9_]{2,40}$`).

```dart
final result = await limenia.submitForReview(
  ReviewRequest(
    type: 'profile_photo', // code of the review type from the dashboard
    author: ReportedUser(currentUserId), // the backend sets it from the login
    externalReviewId: 'upload-${upload.id}', // optional, comes back in review.decided
    content: ReportedContent(
      externalContentId: 'photo-${upload.id}', // a separate ID for every submitted version
      contentType: 'image',
      mediaUrls: [upload.signedUrl], // https, fetchable without login, valid for at least one hour
    ),
  ),
  idempotencyKey: 'review-${upload.id}', // optional, otherwise a new ULID
);
switch (result) {
  case ReviewSent(:final receipt):
    showInReview(upload, receipt.dueAt); // show only to the author, do not publish yet
  case ReviewQueued():
    showInReview(upload, null); // goes out with sendPendingReviews()
  case ReviewFailed(:final code):
    showSnackBar(switch (code) {
      // Type missing or disabled, or reviews not in the tenant's plan.
      'review_type_unknown' || 'feature_not_in_plan' || 'subscription_required' =>
        'Profile photos cannot be reviewed right now.',
      _ => 'The image could not be submitted.',
    });
  case ReviewExpired():
    break; // only comes from sendPendingReviews()
}
```

- `ReviewRequest` takes the content in the format of a report (`ReportedContent`). `content` is required, `author` is sent as `subject`. Always set the author, otherwise moderators see no user file and the decision belongs to no user.
- Sending, retries and the queue work as for reports: the same `RetryPolicy`, the same Idempotency-Key on every retry, and `Retry-After` is respected. Call `limenia.sendPendingReviews()` together with `sendPendingReports()`.
- For a persistent queue, pass `Limenia(pendingReviews: ...)` with your own `PendingReviewStore` implementation (same methods as `PendingReportStore`, JSON from `PendingReview.toJson()`). Pending requests contain the content that is not yet published and the author's ID: do not log them, delete them after sending.
- `ReviewFailed.code` gives the reason, e.g. `review_type_unknown` (type unknown or disabled), `idempotency_key_reused` (409) or `validation_failed` (400, with `fieldErrors`). If the check in the package fails, `code` is `null` and `fieldErrors` is filled.
- From API version 0.13.0 on, review requests depend on the tenant's plan: `subscription_required` (402) while the subscription has expired, `feature_not_in_plan` (403) if the plan does not include reviews. Both are final: the package neither retries nor queues them, and a queued request that meets them is dropped as `ReviewFailed`. Decide in your app what happens to the content then, e.g. keep it unpublished and tell the user. Reports and complaints are never blocked by the plan.
- `validateReview(request, idempotencyKey:)` checks up front the code of the type, `externalReviewId` (1 to 128 characters, `ReviewLimits`), and the author and content with the limits of a report (`ReportLimits`). Only Limenia checks whether the type exists and is active.
- Publish the content only after the result, not already after `ReviewSent`.
- A request sent again from the queue more than 24 hours after the first attempt counts as a new one. If the first attempt had arrived and only the answer was lost, Limenia reviews the content twice, and `review.decided` also comes for a `reviewId` the app never got. Set `externalReviewId` and match on it.
- Limenia's rate limit (10 requests per second per API key, burst 50) applies to the app's backend, i.e. to all users together. If the app has every upload reviewed, the backend absorbs peaks. On a long `Retry-After`, the package queues a request immediately.

### Result of a review

The backend passes the event `review.decided` (`ReviewDecidedEvent`) on to the app:

```dart
case ReviewDecidedEvent(:final review):
  switch (review.outcome) {
    case ReviewOutcome.approved:
      publish(review.externalContentId);
    case ReviewOutcome.restricted:
      publishRestricted(review.externalContentId); // e.g. 18+ only, or blurred with a notice
    case ReviewOutcome.rejected:
      markRejected(review.externalContentId, review.decisionId); // do not publish
  }
```

- `approved`: publish. An approval is not a decision within the meaning of the DSA, and no `decision.created` follows.
- `restricted`: publish with a restriction, e.g. only for adults or blurred with a notice. The app defines how, per review type. The decision with `ModerationAction.restrictContent` follows as `decision.created` with a statement of reasons. Show it to the author.
- `rejected`: do not publish. The decision with `ModerationAction.rejectSubmission` ("refusal to publish the content") follows as `decision.created`. Show the author `statementOfReasons.text` as plain text. The author can complain against it for six months with `AppealRequest.subject(decisionId: ..., ...)` (see [Complaints](#complaints)).
- `review.decisionId` is set for `restricted` and `rejected` and equals `decision.id` in the matching `decision.created`. The order of the events is not guaranteed, so `decision.created` can arrive first.
- `decision.reviewId` (`ModerationDecision.reviewId`) is the `reviewId` of the request. This way you can already tell from the first event which request the decision belongs to.
- If a complaint changes the decision, no second `review.decided` arrives. Instead, `appeal.resolved` arrives, together with a new decision as `decision.created` with `reviewId`, `appealId` and `replacesDecisionId`. Possible actions are `ModerationAction.restore` (the content may be published as submitted, `restoreScope` is `RestoreScope.content`) and, only after a rejection and if the type offers it, `ModerationAction.restrictContent` (publish with a restriction). The author's status never changes in the process, not even with `restore` (see [Decisions](#decisions-and-statement-of-reasons)).
- Match the event via `review.id` (the `reviewId` from `ReviewReceipt`) or `review.externalReviewId`. `review.externalContentId` identifies the upload only if every submitted version has its own `externalContentId` (e.g. `photo_881@v2`); a revised version may also keep the old one.
- `limenia.reviewStatus(reviewId)` returns `ReviewStatusInfo` with `status` (`pending`, `inReview`, `decided`) and, after the decision, `outcome`, `decidedAt` and, if applicable, `decisionId`. This is the fallback in case `review.decided` was lost, e.g. when a request is still open long after `dueAt`. The method throws transport errors. It always shows the first result: if a complaint changed the decision, `outcome` and `decisionId` stay as they were, and the newest `decision.created` with this `reviewId` counts (e.g. `restore` after a rejection: publish as submitted).

## Signals

Signals (API version 0.18.0) are observations of your app about users: a score that jumps, a burst of logins, a client that behaves unusually. A signal is **not a report**. Nobody reviews it by itself and it opens no case. The tenant defines rules per app in the dashboard, and a rule can turn signals into a case for the moderators, raise the priority of a case or set a flag on the user file. Limenia evaluates the rules in the background after the answer, and the answer tells nothing about them. Use a report for content that users flag, a review request for content before it is published, and signals for everything the app notices itself and wants the moderators to see only when a rule says so.

The tenant creates the signal types per app in the dashboard, e.g. `score_jump` with the meaning of `value` ("points per minute"). `type` holds the code of an active type (pattern `^[a-z0-9_]{2,40}$`).

```dart
final result = await limenia.sendSignals(
  SignalsRequest([
    SignalInput(
      type: 'score_jump', // code of a signal type from the dashboard
      externalUserId: currentUserId, // the backend sets it from the login
      value: 4200, // optional, a finite number
      occurredAt: DateTime.now(), // optional, default: receipt; see below
      context: const {'level': '7'}, // optional, IDs and technical details only, at most 4 KB
    ),
  ]),
  idempotencyKey: 'signals-$batchId', // optional, otherwise a new ULID
);
switch (result) {
  case SignalsSent(:final accepted):
    break; // `accepted` signals are stored; nothing to show to the user
  case SignalsQueued():
    break; // goes out with sendPendingSignals()
  case SignalsFailed(:final code, :final fieldErrors):
    // Not stored, not queued. code is signal_type_unknown, validation_failed, feature_not_in_plan, ...
    // fieldErrors name the signal by position, e.g. '/signals/2/type'. Log IDs and codes, not the signals.
    break;
  case SignalsExpired():
    break; // only comes from sendPendingSignals()
}
```

- A request holds 1 to 100 signals (`SignalLimits.maxSignals`) and Limenia checks it as a whole: one invalid signal rejects the request and **nothing is stored**. A request counts once for the rate limit, whatever the number of signals, so collect the signals of a short time and send them together instead of one by one.
- `validateSignals(request, idempotencyKey:)` checks the limits in advance with the paths of the spec: type pattern (`/signals/{i}/type`), user ID 1 to 128 characters (`/signals/{i}/externalUserId`), a finite `value`, the serialized `context` at most 4 KB (`/signals/{i}/context` with `too_large`, measured as the backend does) and 1 to 100 signals (`/signals` with `required` or `too_many`). `sendSignals(...)` calls it itself and returns `SignalsFailed` with a `SignalsValidationException` without queuing anything. Only Limenia knows whether a type exists and is active.
- Sending, retries and the queue work as for reports: the same `RetryPolicy`, the same Idempotency-Key on every retry, `Retry-After` is respected, and a 401, a 5xx, a network error and 403 `tenant_not_active` queue the signals while every other 4xx rejects them. `limenia.sendPendingSignals()` sends the queue. Call it together with `sendPendingReports()`. For a persistent queue, pass `Limenia(pendingSignals: ...)` with your own `PendingSignalsStore` (same methods as `PendingReportStore`, JSON from `PendingSignals.toJson()`); without it the queue is in memory only.
- `SignalsFailed.code` gives the reason: `signal_type_unknown` (400, a type does not exist or is inactive, `fieldErrors` names the signal at `/signals/{i}/type`), `validation_failed` (400), `subscription_required` (402, the subscription has expired), `feature_not_in_plan` (403, the plan does not include signals), `idempotency_key_reused` (409). All are final: the package neither retries nor queues them, and a queued request that meets one later is dropped as `SignalsFailed`. Signals are not an obligation under the DSA and never block reports, complaints or review requests, so decide in your app what to do without them. Nothing else in the app should depend on a signal having arrived.
- `occurredAt` is optional (default: when Limenia receives the request). Limenia accepts it at most 5 minutes ahead and 24 hours back and rejects the whole request otherwise (`/signals/{i}/occurredAt` with `invalid`). The package does not check this, because only the clock of Limenia counts and the clock of a device can be off. Signals that wait in the queue longer than 24 hours therefore fail as `SignalsFailed` unless you leave `occurredAt` out. Signals are observations of the moment, so a shorter `RetryPolicy.maxPendingAge` than the default 7 days is usually right.
- A request sent again from the queue more than 24 hours after the first attempt counts as a new one. If the first attempt had arrived and only the answer was lost, the signals are stored twice and count twice for the rules and the usage of the tenant. Limenia counts every stored signal in the usage of the plan, a repetition with the same key does not.

### Data minimisation and trust

- Send as little as a rule needs. `context` is for IDs and technical details (a level, a session ID, an app version), **never** content (texts, URLs of media) and never personal data of third parties. `externalUserId` is stored in plain text with the signal, so that a rule can create a user file. Limenia deletes signals after the retention period of the tenant (default 30 days). What your app sends is the decision of the tenant under data protection law, so agree on the signal types with them.
- Signals are data about the behaviour of users: do not log them, and keep the queue (`PendingSignalsStore`) as short-lived and as protected as the one for reports.
- Rules only create cases, raise priorities or set flags. A human decides on any measure.
- **Never trust values the device reports.** A modified app can send any `value`, any `context` and any `occurredAt`. The backend of your app must set the user from the login (`SignalsRequest.withExternalUserId(uid)`), should recompute `value` and `context` from its own data, and should limit how many signals one user can send. Best of all, detect the behaviour on the server and send the signal from there with `POST /v1/signals`. Do the same for the Limenia API key: it never belongs into an app.

## Device checks

The device connector (API version 0.20.0) ties a ban to the device without fingerprinting: Play Integrity with Device Recall on Android and Apple DeviceCheck on iOS keep a few bits per device that survive a reinstall and a factory reset. Limenia sets them when it sees the device of a banned or suspended user and reads them at every device check. On Android it also summarizes the integrity verdicts. Your app decides what follows: a marked device is a hint, never proof, because devices are sold on.

The token comes from the optional Flutter plugin [`limenia_device`](https://pub.dev/packages/limenia_device) (or your own native code). The flow, the setup in the Play Console, the Apple key and the test mode are described in its README. In short: your backend issues a request hash, the app gets a token with it, and your backend forwards the token to `POST /v1/devices/check`.

```dart
import 'package:flutter/foundation.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia_device/limenia_device.dart';

// Your backend: deviceRequestHash(uid, newDeviceNonce()), remembered for this user, single use.
final hash = await myBackend.startDeviceCheck();
final device = await LimeniaDevice.requestToken(requestHash: hash, cloudProjectNumber: 123456789012);
try {
  final result = await limenia.checkDevice(
    DeviceCheckRequest(
      externalUserId: currentUserId, // the backend sets it from the login
      platform: device.platform == 'ios' ? DevicePlatform.ios : DevicePlatform.android,
      token: device.token, // single-use, never store or log it
      requestHash: hash,
      environment: device.platform == 'ios' && kDebugMode ? DeviceEnvironment.development : null,
      event: DeviceCheckEvent.login, // registration, login, report or other
    ),
  );
  if (result.deviceFlag.isFlagged) {
    // A banned or suspended account used this device: e.g. ask for more verification.
  } else if (!result.evaluated) {
    // Google or Apple could not be asked (fail-open): decide without the check.
  }
} on DeviceCheckValidationException catch (e) {
  // Not sent: e.errors names the fields, e.g. /token with invalid.
} on LimeniaException catch (e) {
  if (e.isInvalidDeviceToken) {
    // Rejected by Google or Apple, or hash, package or age (15 minutes) do not fit: request a new token.
  } else if (e.isDeviceConnectorNotConfigured) {
    // The connector of this platform is off or not set up for the app (dashboard).
  }
}
```

- Check at registration and at every login, **also at the login of a banned account, before the app rejects it**: Limenia can only mark a device that sends a fresh token. Optionally also when a user reports.
- `limenia.checkDevice(request)` validates the request with `validateDeviceCheck` and then calls `LimeniaTransport.checkDevice`. It never retries and never queues: the token is single-use and valid for 15 minutes, so on any error request a new token. It throws a `DeviceCheckValidationException` before sending, and otherwise the errors of the transport unchanged.
- `validateDeviceCheck(request)` mirrors the limits of the spec (`DeviceCheckLimits`): user ID 1 to 128 characters (`/externalUserId`), token 1 to 8000 (`/token`), request hash 1 to 500 (`/requestHash`), a test token `test:<device>` with `<device>` of `[a-z0-9-]{1,40}` and an optional `:risk` (`/token`), and `environment` for iOS only (`/environment`), all with the code `invalid`. Whether the connector is active and whether Google or Apple accept the token only Limenia knows.
- `deviceRequestHash(externalUserId, nonce)` computes the recommended request hash, `base64url(SHA-256("limenia:" + externalUserId + ":" + nonce))` without `=` padding (43 characters, Play Integrity allows 500), with a SHA-256 in pure Dart. `newDeviceNonce()` gives a random nonce (32 bytes from `Random.secure`, base64url). Both belong in the backend: it computes the hash for the user it authenticated, so a token requested for another user or another check does not pass. On iOS DeviceCheck has no request hash; Limenia ignores it there.
- `DeviceCheckResult`: `checkId`, `platform`, `status` (`evaluated` or `unevaluated`; `evaluated` is a shortcut), `deviceFlag` (`none`, `suspended`, `banned` or `unknown`; `isFlagged` for the first two), `flaggedSince` (`YYYY-MM`, only a hint), `deviceAction` (`none`, `markedBanned`, `markedSuspended` or `reset`: what Limenia wrote to the device), `integrity` (Android only: `device` level, `appRecognized`, `licensed`, `risks` and `testingResponse`) and `subject` (the `SubjectStatus` of the user).
- Values a later API version adds do not break reading: the raw value is kept (`platformName`, `statusName`, `deviceFlagName`, `deviceActionName`, `DeviceIntegrity.deviceName` and `riskNames`), the typed getter is then `null`, `deviceFlag` falls back to `DeviceFlag.unknown`, and `risks` lists only the risks this version knows.
- Error codes: `invalid_device_token` (400, `LimeniaException.isInvalidDeviceToken`), `device_connector_not_configured` (409, `isDeviceConnectorNotConfigured`, also for a test token without the test mode), `validation_failed` (400), `subscription_required` (402) and `feature_not_in_plan` (403, the plan does not include the device connector). A check counts against the rate limit like a report.
- Limenia creates the system signals `device_flagged` (a device marked for another user) and `device_risk` (Android: no integrity, an unrecognized app or risks), so the rules of the tenant can open a case or raise a priority. You do not send them yourself.

The backend sets the user from its login and checks the request hash it issued. The steps in Dart, with a `LimeniaTransport` that calls the ingest API directly as in `test/integration_test.dart` (since 0.12.0 the package needs Flutter, so a Dart server computes the request hash with the formula above itself, e.g. with `package:crypto`; the TypeScript sketch in [What your backend must do](#what-your-backend-must-do) does the same):

```dart
// Step 1: before the app requests the token.
final hash = deviceRequestHash(uid, newDeviceNonce());
await hashes.remember(uid, hash, ttl: const Duration(minutes: 10)); // your storage, single use
// Step 4: the app sends platform, token and hash.
final request = DeviceCheckRequest.fromJson(body).withExternalUserId(uid);
if (request.platform == DevicePlatform.android && !await hashes.take(uid, request.requestHash)) {
  return Response(400);
}
final result = await limenia.checkDevice(request); // throws LimeniaException with Limenia's status and code
return Response.ok(jsonEncode(result.toJson()));
```

`DeviceCheckRequest.toString()` never shows the token. Do not log the request body either.

## Ban evasion across apps

A tenant with several apps can let Limenia (API version 0.28.0) link the user files of its apps through the same e-mail address or phone number. When a user who is banned or suspended in one app becomes active in another, a rule opens a case there, and a moderator decides. The feature is coming soon and available on request.

Your **backend** sends the identifiers, not the app, and this package deliberately has no support for them:

- Limenia receives only HMACs of the normalised e-mail address and phone number in the optional field `identifiers`, computed with the identifier key of the tenant (`lmid_…`). Like the API key, that key belongs only in your backend. Anyone could extract it from an app and test e-mail addresses against it, so the app never computes identifiers, and the models of this package (`ReportedUser`, `SignalInput`, `DeviceCheckRequest`) have no `identifiers` field.
- Your backend adds them when it forwards a request: `subject.identifiers` for reports and review requests, `signals[i].identifiers` for signals, `identifiers` for device checks. It takes the e-mail address and phone number from its own user record, never from the device, and drops any `identifiers` the device sent. Recommended: `PUT /v1/subjects/{externalUserId}` with `identifiers` at registration and on every change of the address or number.
- Identifiers never make a request fail and never change an answer, so nothing changes in the app or in `LimeniaTransport`.
- The normalisation, the HMAC, test vectors, the check values and snippets for Node.js, Go, Python and Dart are in the [integration guide](https://limenia.eu/docs/integration.md), section 3.13. Since 0.12.0 this package needs Flutter, so a Dart backend computes the HMAC itself with `package:crypto`, as shown there.

## Tracking the status

```dart
final watcher = limenia.watchSubject(currentUserId);
await watcher.refresh(); // after login

StreamBuilder<SubjectStatus>(
  stream: watcher.stream,
  builder: (context, snapshot) {
    final status = snapshot.data;
    if (status != null && watcher.isRestricted) return const SuspendedNotice();
    return const HomeScreen();
  },
);
```

- `refresh()` fetches the status via `getSubjectStatus` and throws the transport's errors. Call it after login.
- `tryRefresh()` never throws: errors go to `onRefreshError`, and the result is then `null`. This suits the switch to the foreground, in Flutter with `AppLifecycleListener(onResume: watcher.tryRefresh)`.
- `stream` emits the current status (if known) and then every change. `changes` emits only changes. `current` and `isRestricted` read the state immediately.
- A temporary suspension ends automatically at `suspendedUntil`. Limenia lifts it up to one hour later, or earlier with the next decision about the user, but the watcher already switches to `active` when it expires. The app must enforce the end itself.
- `handleEvent(event)` and `handleDecision(decision)` apply events that your backend passes on to the app (FCM data message or Firestore document). They return `true` if the event was applied. Events can arrive in any order and more than once: a suspension, ban, `restore` of the account or `subject.status_changed` older than the last applied one is ignored, a warning only counts for an active user and only after the last such event. The order is based on `decidedAt` or `createdAt`, respectively.
- As in Limenia, a suspension that has ended by the time of a warning counts as lifted, so the warning makes the user `warned`. From API version 0.13.2, Limenia then lifts the suspension with the decision: `subject.status_changed` comes right with `decision.created`, with the status after the decision (`warned` after a warning, `active` after e.g. `removeContent`) and a `createdAt` equal to `decidedAt`. Pass both on. The watcher ends with the same status whichever arrives first, and also gets `warned` from the decision alone.
- If an event about the user cannot be applied (older than the last one, or an action or restore scope this package version does not know), the watcher asks Limenia again when `refreshOnEvent` is set.
- Decisions on a review request (`decision.reviewId` is set) and a restore of the content (`decision.restoreScope` is `RestoreScope.content`) never change the status. `handleDecision` ignores them and returns `false`, and `SubjectStatus.afterDecision` leaves the status unchanged.
- With `refreshOnEvent: true` (default), the watcher fetches the status from Limenia after an event, because that status is authoritative. `onRefreshError` reports errors in this step.
- On logout, call `watcher.dispose()`. After that, `refresh()` throws a `StateError` and `tryRefresh()` returns `null`.
- `current` and `isRestricted` use the device's clock and are meant for the UI. Your backend must enforce restrictions itself.

## Decisions and statement of reasons

The backend receives the webhook and verifies the signature in the `Limenia-Signature` header ([integration guide](https://limenia.eu/docs/integration.md), section 4.2, with a test vector). The verification never belongs in the app. When the backend passes on the verified event, the app reads it like this:

```dart
final event = LimeniaEvent.fromJson(jsonDecode(payload) as JsonMap);
switch (event) {
  case DecisionCreatedEvent(:final decision):
    watcher.handleDecision(decision);
    final action = decision.action; // null for an unknown future action
    if (action != null && action.informsAffectedUser) {
      showStatementOfReasons(decision.statementOfReasons);
    }
  case SubjectStatusChangedEvent():
    watcher.handleEvent(event);
  case AppealResolvedEvent(:final appeal):
    showAppealAnswer(appeal.statementText); // plain text; with changed, decision.created follows
  case ReportsResolvedEvent(:final reports):
    notifyReporters(reports); // see "Informing reporters"
  case ReviewDecidedEvent(:final review):
    applyReview(review); // see "Reviews"
  case TestPingEvent() || UnknownLimeniaEvent():
    break; // acknowledge and ignore
}
```

A `restore` lifts an earlier restriction, of the content or of the account (API version 0.13.2):

```dart
if (decision.action == ModerationAction.restore) {
  switch (decision.restoreScope) {
    case RestoreScope.content:
      restoreContent(decision.externalContentId); // or publish it as submitted; the account stays as it is
    case RestoreScope.account:
      unlockAccount(decision.externalUserId); // the user is active again
    case null:
      log('restore ${decision.id} with scope ${decision.restoreScopeName}'); // see below
  }
}
```

- `ModerationDecision.action` is `null` for actions that this package version does not know. The raw value is in `actionName`. Do not silently ignore such decisions. Log the ID instead.
- `appealId` and `replacesDecisionId` are `null` as long as the decision does not come from a complaint. If a complaint changes the decision, the new decision names the complaint (`appealId`) and the replaced decision (`replacesDecisionId`). If the fields are missing, they stay `null`.
- `reviewId` is `null` as long as the decision does not belong to a review request. It is set when a request is restricted or rejected (`review.decided` follows) and for a new decision after a complaint against that, then together with `appealId` and `replacesDecisionId`. If the field is missing, it stays `null`.
- `restoreScope` says what a `restore` lifts. `RestoreScope.content`: the restriction of the content, after a complaint against `removeContent` or `restrictContent` and for every `restore` on a review request. The user's status and account stay as they are, a suspension or a ban too. `RestoreScope.account`: the restriction of the account, e.g. after a complaint against `warnUser`, `suspendUser` or `banUser` or from the user file. The user is active again. The field is `null` for other actions and with Limenia before API version 0.13.2, whose `restore` lifted the account, or the content with `reviewId`. A scope this package version does not know is `null` as well: its raw value is in `restoreScopeName`, and `changesUserStatus` is `false`.
- A decision with `reviewId` and a `restore` of the content never change the user's status or account. With `reviewId`, `restore` means that the submitted content (`decision.externalContentId`) may be published as submitted, not that a suspension is lifted. So check `decision.changesUserStatus`, not `decision.action?.changesUserStatus`. The latter only looks at the action and is always true for `restore`.
- `action.informsAffectedUser` is true for everything except `dismiss`. For `restore`, the statement is the notice that a restriction was lifted. For `rejectSubmission`, it gives the reasons why submitted content is not published.
- Show `statementOfReasons.text` as plain text (`Text` widget), never as HTML or Markdown, because the text contains the moderator's free text. For your own layout or other languages, use `statementOfReasons.structured`.
- `structured.noticeSource` (API version 0.16.0) says what led to the decision, as `NoticeSource`: `notice` (reports of users), `trustedFlagger` (at least one report of the case comes from a trusted flagger) or `ownInitiative` (reports with `source: system` only, an action in the user file, a review request). Decisions from before 0.16.0 have no such field: then it is derived from `basedOnNotice` (`true` is `notice`, `false` is `ownInitiative`). So is a value this package version does not know yet, whose raw value stays in `noticeSourceName` (`null` when the field is missing). `basedOnNotice` stays as it was.
- `structured.automatedDetection` is `true` since API version 0.16.0 if the case has at least one report with `source: system`, detected automatically by the app or by Limenia. The text then says that the occasion was detected automatically and a human decided. `automatedDecision` stays `false`.
- `structured.automation` (API version 0.19.0) says whether automated means were used for the decision, as `Automation`: `none`, `partial` (a moderator took and confirmed a suggestion of the AI pre-screening, a human still decided) or `full` (an automatic decision without a moderator). **When `automation` is `partial` or `full` (`automation.usesAutomatedMeans`), show the affected user that automated means were used** (Art. 17(3)(c) DSA); for `partial` the text of the statement has a sentence about it. Do not rely on `automatedDecision` for this: it is `true` only for `full` and stays `false` for `partial`. Decisions from before 0.19.0 have no such field and are `none`. So is a value this package version does not know yet, whose raw value stays in `automationName` (`null` when the field is missing).
- Event IDs (`event.id`, for the backend also in the `Limenia-Event-Id` header) are the same in every delivery attempt. Deduplicate by them.

## Widgets (`package:limenia/ui.dart`)

```dart
import 'package:limenia/ui.dart';
```

| Widget | What it is for |
|---|---|
| `showLimeniaReportSheet` / `LimeniaReportForm` | Report content or a user: category, optional text, optional good-faith confirmation (Art. 16 DSA) |
| `showLimeniaAppealSheet` / `LimeniaAppealForm` | Complain against a decision, for the affected user and for reporters (Art. 20 DSA) |
| `LimeniaStatementOfReasonsView` | Show the statement of reasons of a decision (Art. 17 DSA) |
| `LimeniaRestrictionNotice` / `LimeniaRestrictionScreen` | Tell the user that their account is warned, suspended or banned |
| `LimeniaSubjectStatusBuilder` | Rebuild with the status of a `SubjectStatusWatcher` |

The widgets use the models of `package:limenia/limenia.dart`: `ReportResult`, `AppealResult`, `StatementOfReasons`, `SubjectStatus`, `ReasonCategory` and the limits in `ReportLimits` and `AppealLimits`.

### Principles

- **The widgets never send anything.** They collect the input and call your callbacks, which usually wrap `Limenia.report(...)` and `Limenia.appeal(...)`. Those go through your `LimeniaTransport` to your own backend, which holds the API key of Limenia. The API key never belongs in an app.
- **They show every result of the headless API:** sending, sent, queued while offline, failed with "Try again", expired, and the answers of Limenia that need their own text (a reporter whose reports are suspended, a closed complaint window, …).
- **They check input with the validators of the headless API** (`validateReport`, `validateAppeal`), so they are never stricter than Limenia: lengths count Unicode code points, and a text over the limit shows an error instead of being cut off.
- **They follow your theme.** Colors come from your `ColorScheme`, fonts from your `TextTheme`, in light and dark. There are no colors of their own.
- **They are accessible:** headings and labels for screen readers, results in live regions (read out when they appear), 48 dp tap targets, a natural focus order, and layouts that hold at a text scale of 2.0.
- **Texts in German and English**, chosen from the locale of the app, each of them replaceable.
- **Statements of reasons are plain text**, never Markdown or HTML: they contain the free text of the moderator.

### How the pieces connect

```
Widget ──onSubmit──▶ your callback ──▶ Limenia.report / Limenia.appeal ──▶ LimeniaTransport
                                                                               │
                                       Limenia ◀── API key ── your backend ◀───┘
```

Set up `Limenia` with your transport as described in [Implementing `LimeniaTransport`](#implementing-limeniatransport). The callbacks below use an instance `limenia` of it. Your backend sets the reporter, the complaining user and the author from its own login, never from the device.

### Report sheet

```dart
final result = await showLimeniaReportSheet(
  context,
  goodFaith: GoodFaithConfirmation.optional, // shows the checkbox
  onSubmit: (draft) => limenia.report(
    ReportRequest.content(
      reasonCategory: draft.reasonCategory,
      reasonText: draft.reasonText,
      goodFaith: draft.goodFaithConfirmed, // only for source: user, the default
      content: ReportedContent(externalContentId: comment.id, contentType: 'comment'),
      author: ReportedUser(comment.authorId),
      externalReportId: 'report-${comment.id}-$userId', // to inform the reporter later
    ),
  ),
);
// result: the last ReportResult, or null if the user closed the sheet before one arrived.
```

- `ReportDraft` holds `reasonCategory` (a code that passes `ReasonCategory.isValid`), `reasonText` (as entered, `null` if empty, at most `ReportLimits.reasonTextLength` code points) and `goodFaithConfirmed`.
- **Categories:** by default the codes of `ReasonCategory.defaults` with labels matching the default policies of Limenia (Spam, Belästigung und Hassrede, Gewalt, Sexuelle Inhalte, Schutz von Minderjährigen, Betrug, Urheberrecht, Datenschutz, Selbstgefährdung, Sonstiges, and their English names). Pass your own list with the codes of the policies of your tenant:

  ```dart
  showLimeniaReportSheet(
    context,
    categories: const [
      ReportCategoryOption(code: 'spam', label: 'Werbung'),
      ReportCategoryOption(code: 'cheating', label: 'Schummeln', description: 'Bots, Hacks und Exploits'),
    ],
    onSubmit: ...,
  );
  ```

  Every code must pass `ReasonCategory.isValid` and appear once; in debug mode the form fails otherwise.
- **Good faith (Art. 16(2)(d) DSA):** `goodFaith: GoodFaithConfirmation.required` shows a checkbox the user must check, `optional` one they may leave unchecked, `hidden` (the default) none. Pass the answer on as `ReportRequest.goodFaith` (`goodFaith: draft.goodFaithConfirmed`, Limenia API version 0.22.0, as above): Limenia stores it and shows it to moderators. `false` (also when the form does not ask) counts as not confirmed, the same as leaving the field out. The field is only for reports of users, `source: user`, which is the default of `ReportRequest.content` and `ReportRequest.user` and what the sheet is for. With `source: system`, `validateReport` and Limenia reject it, also as `false`.
- **Emergency hint:** when the user picks self-harm or violence, the form shows a short hint to call the emergency services (112 in the EU). Change it with `emergencyHint: ReportEmergencyHint(categories: {...}, text: '...')`, e.g. with a helpline of your country, or turn it off with `emergencyHint: null`.
- **Results:** `ReportSent` thanks the user ("We will review it") and shows the warning of `ReportSent.reporterWarning` (Art. 23 DSA) if there is one. `ReportQueued` says the report will be sent when the user is online again. `ReportFailed` and `ReportExpired` offer "Try again", which calls `onSubmit` with the same draft; `ReportFailed.isReporterSuspended` shows until when the reports of the user are not processed, without a retry. If `onSubmit` throws, the form shows a failure with "Try again" and reports the error to `FlutterError.reportError`.
- **Embedded:** `LimeniaReportForm` is the same form without the sheet. It is as tall as its content, so put it in a scroll view. `onClose` adds a close button, `onResult` gets every result.

### Complaint form

For the affected user, from `decision.created`:

```dart
await showLimeniaAppealSheet(
  context,
  topic: AppealTopic.fromDecision(decision),
  onSubmit: (text) => limenia.appeal(
    AppealRequest.subject(decisionId: decision.id, externalUserId: userId, text: text),
  ),
);
```

For a reporter, from `reports.resolved`:

```dart
await showLimeniaAppealSheet(
  context,
  topic: AppealTopic.fromReportsResolution(resolution, title: 'Your report of October 1'),
  onSubmit: (text) => limenia.appeal(
    AppealRequest.reporter(decisionId: resolution.decisionId, externalUserId: userId, text: text),
  ),
);
```

- The form shows what the complaint is about (`AppealTopic`: an optional title, the measure, the titles of the policies and the date of the decision), that a complaint is possible for six months, free of charge and reviewed by a person, and until when: `ReportsResolution.appealDeadline` for reporters, otherwise six calendar months after `decidedAt` as Limenia computes it (`appealDeadlineFor`). `AppealTopic(title: '...')` works without a decision.
- The text is required and at most `AppealLimits.textLength` (5000) code points. `onSubmit` gets it exactly as entered.
- **Results:** `AppealSent` ("A person will review your complaint"), `AppealQueued` (sent when online), `AppealFailed` and `AppealExpired` with "Try again". The answers that cannot change by trying again have their own text and no retry: `appeal_window_closed`, `appeal_already_open`, `appeal_not_allowed` and `reporter_suspended` (with its end).
- **Embedded:** `LimeniaAppealForm`, like the report form.

### Statement of reasons

```dart
LimeniaStatementOfReasonsView(
  statement: decision.statementOfReasons,
  onAppeal: () => showLimeniaAppealSheet(context, topic: AppealTopic.fromDecision(decision), onSubmit: ...),
)
```

- By default the view shows the ready-made `text` of Limenia, in the language of the tenant, as selectable plain text.
- `layout: SorLayout.structured` builds sections from `StatementOfReasons.structured` with labels in the language of the app: measure, end of a temporary restriction, scope, facts, what led to the decision (a report of users, of a trusted flagger, or an own review), the use of automated means, the grounds (policy title, and the law reference for illegal content) and the redress text. Facts, policy titles and redress stay in the language of the tenant. An action this version of the package does not know falls back to the text.
- **Automated means (Art. 17(3)(c) DSA):** the structured layout always says whether automated means were used and highlights it for `Automation.partial` and `Automation.full`. The ready-made text contains the same sentence.
- The view is as tall as its content: put it in a scroll view, e.g. the body of a page.

### Restriction notices

```dart
LimeniaRestrictionNotice(
  status: watcher.current ?? SubjectStatus.active(userId),
  onShowReasons: () => showReasons(lastDecision),
  onAppeal: () => showLimeniaAppealSheet(context, ...),
)
```

- `LimeniaRestrictionNotice` is an inline notice: a soft banner for `warned`, a prominent one for `suspended` (with the end in the local time of the device) and `banned`, nothing for `active`.
- `LimeniaRestrictionScreen` is a full page for `suspended` and `banned`, e.g. in place of the home screen, with an optional `footer` (log out, contact). It shows nothing for `active` and `warned`.
- Both use `SubjectStatus.effectiveAt` with `now` (default `DateTime.now`, injectable for tests): a suspension that has ended shows nothing, and a notice on screen disappears by itself when the suspension ends.
- `LimeniaSubjectStatusBuilder` rebuilds with the status of a `SubjectStatusWatcher`:

  ```dart
  LimeniaSubjectStatusBuilder(
    watcher: watcher, // limenia.watchSubject(userId), refreshed after login
    builder: (context, status) => status != null && status.isRestrictedAt(DateTime.now())
        ? Scaffold(body: LimeniaRestrictionScreen(status: status, onAppeal: ...))
        : const HomeScreen(),
  )
  ```

- The notices are advisory, like the status in the app. Your backend enforces restrictions. A banned user may not be able to log in at all: tell them also by e-mail or on the login screen ([integration guide of Limenia](https://limenia.eu/docs/integration.md), section 4.7).

### Texts and languages

The widgets pick their texts from `LimeniaUiStrings`:

1. the `strings` argument of a widget or `show…` function,
2. the nearest `LimeniaUiStringsScope`,
3. `LimeniaUiStrings.forLocale(Localizations.localeOf(context))`: German (`de`, informal "du") for German, English for every other language.

Change single texts with `copyWith`, per locale, in `MaterialApp.builder` so that sheets and pages see them:

```dart
MaterialApp(
  builder: (context, child) => LimeniaUiStringsScope(
    strings: (locale) => switch (locale.languageCode) {
      'de' => LimeniaUiStrings.de.copyWith(
          reportTitle: 'Beitrag melden',
          emergencyHint: 'Du brauchst Hilfe? Die Telefonseelsorge ist rund um die Uhr erreichbar: 0800 111 0 111.',
        ),
      _ => LimeniaUiStrings.en,
    },
    child: child!,
  ),
);
```

For another language, build a complete `LimeniaUiStrings` (every text is a constructor argument) and return it from the scope. Texts with values are functions, e.g. `suspendedMessage: (until) => ...`; dates arrive already formatted by `formatDate` and `formatDateTime` (German `07.10.2026 14:30`, English `Oct 7, 2026, 14:30`, in the local time zone), which you can replace as well.

### Example app

`example/` is a Flutter app with one screen per widget, a fake backend whose answer you choose (sent, queued, failed, …), and switches for German and English and for light and dark:

```sh
cd example
flutter run -d chrome
flutter build web
```

Query parameters open a screen directly, e.g. `?screen=report&open=1&theme=dark&lang=en`; see the comment at the top of `example/lib/main.dart`.

The headless API has an example without Flutter widgets as well: `example/bin/headless.dart`, run it in `example/` with `dart run bin/headless.dart`.

## Tests

In `packages/limenia` of the repo:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

The CI of the repo (`.github/workflows/ci.yml`) runs these checks on every push. Widget tests are in `test/ui`. `example/bin/headless.dart` runs without a backend: `dart run bin/headless.dart` in `example/`.

Two tests pin the package to the real behaviour of the backend, with fixtures generated from the backend of Limenia:

- `test/go_events_test.dart` reads the webhook events exactly as the backend builds them (`test/fixtures/events`).
- `test/go_media_urls_test.dart` checks `isAllowedMediaUrl` and the field codes of `validateReport` for media URLs against the URL check of the backend and the character limit of the ingest API, for more than 160 URLs, including malformed and overlong ones (`test/fixtures/media_urls.json`).

The integration test sends real reports to a deployment and only runs with the tag `integration`:

```sh
LIMENIA_BASE_URL=https://limenia.example.com LIMENIA_API_KEY=lm_test_... flutter test -t integration
```

With `LIMENIA_REVIEW_TYPE` (the code of an active review type of the test app), it also submits a review request and reads its status. With `LIMENIA_SIGNAL_TYPE` (the code of an active signal type of the test app), it also sends signals and checks that a repetition returns the same receipt. With `LIMENIA_DEVICE_TEST_MODE=1` (the device connector of the test app is on, with test mode), it also checks test devices (`test:<device>`).

There is no separate test environment. Even an `lm_test_` key writes to the real system. Use a dedicated test app for this.

## API specification

`spec/openapi.yaml` is a copy of the public OpenAPI description of Limenia (<https://limenia.eu/openapi/v1.yaml>: the operations under `/v1` and the webhook events). `test/spec_test.dart` checks the package against it: the enums (actions, restore scopes, notice sources, statuses, sources, event types, complaints, reviews), the limits and patterns of reports (`trustedFlaggerId` and `goodFaith` included), complaints, review requests, signals and device checks, that `POST /v1/signals`, `POST /v1/devices/check` and their error codes are in the spec, the device enums and that the recommended request hash is the one `deviceRequestHash` computes, that every operation under `/v1` is either covered by `LimeniaTransport` or a known exception, that the models deliberately leave the `identifiers` for ban evasion across apps to the backend, the warning and the suspension (`ReporterWarning`, `Problem.suspendedUntil`, 403 `reporter_suspended`), that every field the models read or write is declared in the spec and that they write every required field, and that the events the backend builds match the schema `WebhookEvent`.

When Limenia's API changes:

1. Update the copy with `tool/sync_openapi.sh` (it downloads <https://limenia.eu/openapi/v1.yaml>; pass a URL or a local file to use another source). The maintainers regenerate the fixtures in `test/fixtures` from the backend.
2. `flutter test` shows where the package deviates. Adjust the models, the checks and `ReportLimits`.
3. Run the integration test against a deployment, bump the version in `pubspec.yaml` and `CHANGELOG.md`, tag (`limenia-v0.x.y`) and publish to pub.dev.

New actions, restore scopes and event types do not break older package versions: `ModerationDecision.action` or `ModerationDecision.restoreScope` is then `null`, and `LimeniaEvent.fromJson` returns `UnknownLimeniaEvent`. A new notice source falls back to the one derived from `basedOnNotice` (`SorDetails.noticeSource`; the raw value is in `noticeSourceName`). A new automation value falls back to `Automation.none` (`SorDetails.automation`; the raw value is in `automationName`). A new value in a device check keeps its raw value, see [Device checks](#device-checks). A new sanction status, complaint or review status, complaint or review outcome, appellant type or legal basis, on the other hand, leads to a `FormatException` when reading.

It is different when you switch to a new package version: a new enum value or event type breaks the app's code if a `switch` lists all cases, as `ModerationAction.rejectSubmission` and `ReviewDecidedEvent` did in 0.4.0. What changes is listed in `CHANGELOG.md`.

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Copyright 2026 Karim Belkacem. The license grants no rights to use the name "Limenia".
