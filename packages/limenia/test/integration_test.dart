// Sends the JSON of this package to a real Limenia deployment, to prove it
// matches what the server accepts and returns. Writes real reports: use the
// key of a test app.
//
//   LIMENIA_BASE_URL=https://... LIMENIA_API_KEY=lm_test_... dart test -t integration
//
// With LIMENIA_REVIEW_TYPE (the code of an active review type of the test
// app) it also submits a review request and reads its status. With
// LIMENIA_SIGNAL_TYPE (the code of an active signal type of the test app) it
// also sends signals. With LIMENIA_DEVICE_TEST_MODE=1 (the device connector of
// the test app is on, with test mode) it also checks test devices.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

void main() {
  final baseUrl = Platform.environment['LIMENIA_BASE_URL'];
  final apiKey = Platform.environment['LIMENIA_API_KEY'];
  final skip = baseUrl == null || apiKey == null ? 'needs LIMENIA_BASE_URL and LIMENIA_API_KEY' : false;

  late _DirectTransport transport;
  setUpAll(() {
    if (skip == false) transport = _DirectTransport(Uri.parse(baseUrl!), apiKey!);
  });
  tearDownAll(() {
    if (skip == false) transport.close();
  });

  final run = DateTime.now().toUtc().millisecondsSinceEpoch;
  final userId = 'dart-it-$run';

  test('a report goes through and a repetition returns the same receipt', () async {
    final limenia = Limenia(transport: transport);
    final request = ReportRequest.content(
      reasonCategory: ReasonCategory.spam,
      reasonText: 'Integration test of the Dart package',
      reporterId: 'dart-it-reporter',
      externalReportId: 'dart-it-report-$run',
      author: ReportedUser(userId, displayName: 'Dart IT'),
      content: ReportedContent(
        externalContentId: 'dart-it-content-$run',
        contentType: 'comment',
        text: 'Automated test 😀 <b>&</b>',
        createdAt: DateTime.now(),
        context: const {'source': 'clients/dart integration test'},
      ),
    );
    final key = newIdempotencyKey();
    final first = await limenia.report(request, idempotencyKey: key);
    expect(first, isA<ReportSent>());
    expect((first as ReportSent).receipt.caseCreated, isTrue);

    // Same key and body: Limenia answers with the original receipt.
    final again = await transport.createReport(request, idempotencyKey: key);
    expect(again, first.receipt);

    // Same key, other body: rejected and not retried.
    final other = await limenia.report(request.withReporter('someone-else'), idempotencyKey: key);
    expect(other, isA<ReportFailed>());
    expect(((other as ReportFailed).error as LimeniaException).code, 'idempotency_key_reused');
  }, skip: skip);

  test('Limenia rejects what the client check rejects', () async {
    // Bypasses the client check on purpose.
    final invalid = ReportRequest.content(
      reasonCategory: ReasonCategory.spam,
      author: ReportedUser(userId),
      content: ReportedContent(
        externalContentId: 'x',
        contentType: 'comment',
        mediaUrls: [
          'https://10.0.0.1/a.jpg',
          // From API version 0.13.2 Limenia counts the characters of media
          // URLs: 2049 characters are too long, 2048 with 4072 bytes are not.
          'https://cdn.example.com/${'a' * 2025}',
          'https://cdn.example.com/${'ä' * 2024}',
        ],
      ),
    );
    final local = validateReport(invalid);
    expect(
        local, const [FieldError('/content/media/0/url', 'invalid'), FieldError('/content/media/1/url', 'too_long')]);
    try {
      await transport.createReport(invalid, idempotencyKey: newIdempotencyKey());
      fail('Limenia accepted an invalid report');
    } on LimeniaException catch (e) {
      expect(e.status, 400);
      expect(e.code, 'validation_failed');
      expect(e.fieldErrors, local);
    }
  }, skip: skip);

  // Needs Limenia with API version 0.22.0 (goodFaith).
  test('a confirmation in good faith goes through, and Limenia rejects it with source system', () async {
    final limenia = Limenia(transport: transport);
    final confirmed = ReportRequest.user(
      reasonCategory: ReasonCategory.spam,
      reasonText: 'Integration test of the Dart package (good faith)',
      reporterId: 'dart-it-reporter',
      goodFaith: true,
      subject: ReportedUser('$userId-good-faith'),
    );
    expect(await limenia.report(confirmed), isA<ReportSent>());

    // Bypasses the client check on purpose.
    final system = ReportRequest.user(
      source: ReportSource.system,
      reasonCategory: ReasonCategory.spam,
      goodFaith: false,
      subject: ReportedUser('$userId-good-faith'),
    );
    final local = validateReport(system);
    expect(local, const [FieldError('/goodFaith', 'invalid')]);
    try {
      await transport.createReport(system, idempotencyKey: newIdempotencyKey());
      fail('Limenia accepted goodFaith with source system');
    } on LimeniaException catch (e) {
      expect(e.status, 400);
      expect(e.code, 'validation_failed');
      expect(e.fieldErrors, local);
    }
  }, skip: skip);

  test('a complaint against an unknown decision is rejected with 404', () async {
    final limenia = Limenia(transport: transport);
    final result = await limenia.appeal(
      AppealRequest.subject(
        decisionId: newIdempotencyKey(), // a ULID no decision has
        externalUserId: userId,
        text: 'Integration test of the Dart package',
        externalAppealId: 'dart-it-appeal-$run',
      ),
    );
    expect(result, isA<AppealFailed>());
    expect(((result as AppealFailed).error as LimeniaException).status, 404);
    expect(await limenia.reporter.pendingAppeals(), isEmpty);

    await expectLater(
      limenia.appealStatus(newIdempotencyKey()),
      throwsA(isA<LimeniaException>().having((e) => e.status, 'status', 404)),
    );
  }, skip: skip);

  // Needs Limenia with API version 0.12.0 (review requests).
  test('a review request with an unknown type is rejected', () async {
    final limenia = Limenia(transport: transport);
    final result = await limenia.submitForReview(
      ReviewRequest(
        type: 'dart_it_unknown_type',
        author: ReportedUser(userId),
        externalReviewId: 'dart-it-review-$run',
        content: ReportedContent(
          externalContentId: 'dart-it-review-content-$run',
          contentType: 'profile_text',
          text: 'Integration test of the Dart package',
        ),
      ),
    );
    expect(result, isA<ReviewFailed>());
    expect((result as ReviewFailed).code, 'review_type_unknown');
    expect(result.fieldErrors.map((e) => (e.field, e.code)), [('/type', 'unknown')]);
    expect(await limenia.reporter.pendingReviews(), isEmpty);

    await expectLater(
      limenia.reviewStatus(newIdempotencyKey()),
      throwsA(isA<LimeniaException>().having((e) => e.status, 'status', 404)),
    );
  }, skip: skip);

  final reviewType = Platform.environment['LIMENIA_REVIEW_TYPE'];
  test('a review request goes through, a repetition returns the same receipt', () async {
    final limenia = Limenia(transport: transport);
    final request = ReviewRequest(
      type: reviewType!,
      author: ReportedUser(userId, displayName: 'Dart IT'),
      externalReviewId: 'dart-it-review-ok-$run',
      content: ReportedContent(
        externalContentId: 'dart-it-review-ok-content-$run',
        contentType: 'profile_text',
        text: 'Integration test of the Dart package',
      ),
    );
    final key = newIdempotencyKey();
    final sent = await limenia.submitForReview(request, idempotencyKey: key);
    expect(sent, isA<ReviewSent>());
    final receipt = (sent as ReviewSent).receipt;
    expect(receipt.status, ReviewStatus.pending);
    expect(receipt.dueAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1))), isTrue);

    expect(await transport.createReview(request, idempotencyKey: key), receipt);

    final status = await limenia.reviewStatus(receipt.reviewId);
    expect(status.id, receipt.reviewId);
    expect(status.type, reviewType);
    expect(status.externalReviewId, 'dart-it-review-ok-$run');
    expect(status.status, ReviewStatus.pending);
    expect([status.outcome, status.decisionId], [null, null]);
  }, skip: skip != false ? skip : (reviewType == null ? 'needs LIMENIA_REVIEW_TYPE' : false));

  // Needs Limenia with API version 0.18.0 (signals).
  test('signals of an unknown type are rejected as a whole', () async {
    final limenia = Limenia(transport: transport);
    final result = await limenia.sendSignals(
      SignalsRequest([SignalInput(type: 'dart_it_unknown_type', externalUserId: userId, value: 1)]),
    );
    expect(result, isA<SignalsFailed>());
    expect((result as SignalsFailed).code, 'signal_type_unknown');
    expect(result.fieldErrors.map((e) => e.field), ['/signals/0/type']);
    expect(await limenia.reporter.pendingSignals(), isEmpty);
  }, skip: skip);

  final signalType = Platform.environment['LIMENIA_SIGNAL_TYPE'];
  test('signals go through, a repetition returns the same receipt', () async {
    final limenia = Limenia(transport: transport);
    final request = SignalsRequest([
      SignalInput(
        type: signalType!,
        externalUserId: userId,
        value: 4200,
        occurredAt: DateTime.now(),
        context: const {'source': 'dart integration test'},
      ),
      SignalInput(type: signalType, externalUserId: userId),
    ]);
    final key = newIdempotencyKey();
    final sent = await limenia.sendSignals(request, idempotencyKey: key);
    expect(sent, isA<SignalsSent>());
    expect((sent as SignalsSent).accepted, 2);

    expect(await transport.createSignals(request, idempotencyKey: key), sent.receipt);

    // Same key, other body: rejected and not retried.
    final other = await limenia.sendSignals(SignalsRequest([request.signals.first]), idempotencyKey: key);
    expect(other, isA<SignalsFailed>().having((r) => r.code, 'code', 'idempotency_key_reused'));
  }, skip: skip != false ? skip : (signalType == null ? 'needs LIMENIA_SIGNAL_TYPE' : false));

  final deviceTestMode = Platform.environment['LIMENIA_DEVICE_TEST_MODE'] == '1';
  test('device checks with test tokens', () async {
    final limenia = Limenia(transport: transport);
    final result = await limenia.checkDevice(DeviceCheckRequest(
      externalUserId: userId,
      platform: DevicePlatform.test,
      token: 'test:dart-it-$run',
      event: DeviceCheckEvent.registration,
    ));
    expect(result.test, isTrue);
    expect(result.platform, DevicePlatform.test);
    expect(result.status, DeviceCheckStatus.evaluated);
    expect(result.deviceFlag, DeviceFlag.none); // a new test device
    expect(result.deviceAction, DeviceAction.none); // the user is not restricted
    expect(result.subject.externalUserId, userId);
    expect(result.checkId, isNotEmpty);

    final risky = await limenia.checkDevice(DeviceCheckRequest(
      externalUserId: userId,
      platform: DevicePlatform.test,
      token: 'test:dart-it-$run:risk',
      event: DeviceCheckEvent.login,
    ));
    expect(risky.status, DeviceCheckStatus.evaluated);
    expect(risky.test, isTrue);

    // A test token is not an Android token: the connector rejects it or is not configured.
    await expectLater(
      limenia.checkDevice(DeviceCheckRequest(externalUserId: userId, platform: DevicePlatform.android, token: 'x')),
      throwsA(isA<LimeniaException>().having(
        (e) => e.isInvalidDeviceToken || e.isDeviceConnectorNotConfigured,
        'invalid_device_token or device_connector_not_configured',
        isTrue,
      )),
    );
  }, skip: skip != false ? skip : (deviceTestMode ? false : 'needs LIMENIA_DEVICE_TEST_MODE=1'));

  test('status of the reported user', () async {
    final status = await Limenia(transport: transport).subjectStatus(userId);
    expect(status, SubjectStatus.active(userId));
  }, skip: skip);
}

/// Talks to the ingest API directly with the API key. Only for this test: in
/// an app the key belongs into the backend, never into the app.
final class _DirectTransport implements LimeniaTransport {
  _DirectTransport(this._baseUrl, this._apiKey);

  final Uri _baseUrl;
  final String _apiKey;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 30);

  void close() => _http.close();

  @override
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey}) async {
    final body = await _send('POST', '/v1/reports', body: request.toJson(), idempotencyKey: idempotencyKey);
    return ReportReceipt.fromJson(body);
  }

  @override
  Future<SubjectStatus> getSubjectStatus(String externalUserId) async {
    final body = await _send('GET', '/v1/subjects/${Uri.encodeComponent(externalUserId)}/status');
    return SubjectStatus.fromJson(body);
  }

  @override
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey}) async {
    final body = await _send('POST', '/v1/appeals', body: request.toJson(), idempotencyKey: idempotencyKey);
    return AppealReceipt.fromJson(body);
  }

  @override
  Future<AppealStatusInfo> getAppealStatus(String appealId) async {
    final body = await _send('GET', '/v1/appeals/${Uri.encodeComponent(appealId)}');
    return AppealStatusInfo.fromJson(body);
  }

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) async {
    final body = await _send('POST', '/v1/reviews', body: request.toJson(), idempotencyKey: idempotencyKey);
    return ReviewReceipt.fromJson(body);
  }

  @override
  Future<ReviewStatusInfo> getReviewStatus(String reviewId) async {
    final body = await _send('GET', '/v1/reviews/${Uri.encodeComponent(reviewId)}');
    return ReviewStatusInfo.fromJson(body);
  }

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) async {
    final body = await _send('POST', '/v1/signals', body: request.toJson(), idempotencyKey: idempotencyKey);
    return SignalsReceipt.fromJson(body);
  }

  @override
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) async {
    final body = await _send('POST', '/v1/devices/check', body: request.toJson());
    return DeviceCheckResult.fromJson(body);
  }

  Future<JsonMap> _send(String method, String path, {JsonMap? body, String? idempotencyKey}) async {
    final req = await _http.openUrl(method, _baseUrl.resolve(path));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
    if (idempotencyKey != null) req.headers.set('Idempotency-Key', idempotencyKey);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 60));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode > 299) {
      throw LimeniaException.fromResponse(
        status: res.statusCode,
        body: text,
        retryAfter: res.headers.value(HttpHeaders.retryAfterHeader),
      );
    }
    return jsonDecode(text) as JsonMap;
  }
}
