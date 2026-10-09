import 'dart:async';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

const request = ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u_1'), reporterId: 'u_2');
const receipt = ReportReceipt(reportId: 'r', caseId: 'c', caseCreated: true);
const appealRequest =
    AppealRequest.reporter(decisionId: '01K6G5H1TR8W4QZ3M0XCB7NDEC', externalUserId: 'u_2', text: 'Please check.');
const appealReceipt = AppealReceipt(appealId: 'a', status: AppealStatus.open);
const reviewRequest = ReviewRequest(
  type: 'profile_photo',
  author: ReportedUser('u_1'),
  content: ReportedContent(
    externalContentId: 'photo_881',
    contentType: 'image',
    mediaUrls: ['https://cdn.example.com/photo_881.jpg'],
  ),
  externalReviewId: 'upload_881',
);
final reviewReceipt = ReviewReceipt(reviewId: 'rv', status: ReviewStatus.pending, dueAt: DateTime.utc(2026, 10, 3, 13));
const signalsRequest = SignalsRequest([
  SignalInput(type: 'score_jump', externalUserId: 'u_1', value: 4200, context: {'level': '7'}),
  SignalInput(type: 'login_burst', externalUserId: 'u_1'),
]);
const signalsReceipt = SignalsReceipt(accepted: 2);

void main() {
  late FakeTransport transport;
  late InMemoryPendingReportStore store;
  late InMemoryPendingAppealStore appealStore;
  late InMemoryPendingReviewStore reviewStore;
  late InMemoryPendingSignalsStore signalsStore;
  late FakeClock clock;
  late List<Duration> sleeps;
  late LimeniaReporter reporter;

  LimeniaReporter build({RetryPolicy policy = const RetryPolicy()}) => LimeniaReporter(
        transport: transport,
        store: store,
        appealStore: appealStore,
        reviewStore: reviewStore,
        signalsStore: signalsStore,
        retryPolicy: policy,
        now: clock.call,
        sleep: (d) async => sleeps.add(d),
      );

  setUp(() {
    transport = FakeTransport();
    store = InMemoryPendingReportStore();
    appealStore = InMemoryPendingAppealStore();
    reviewStore = InMemoryPendingReviewStore();
    signalsStore = InMemoryPendingSignalsStore();
    clock = FakeClock(DateTime.utc(2026, 10, 2, 12));
    sleeps = [];
    reporter = build();
  });

  group('report', () {
    test('sends and removes the report from the store', () async {
      transport.reportAnswers.add(receipt);
      final result = await reporter.report(request, idempotencyKey: 'report-1');
      expect(result, isA<ReportSent>().having((r) => r.receipt, 'receipt', receipt));
      expect(result.idempotencyKey, 'report-1');
      expect(transport.reportCalls.single.$2, 'report-1');
      expect(await store.load(), isEmpty);
    });

    test('creates a ULID as key', () async {
      transport.reportAnswers.add(receipt);
      final result = await reporter.report(request);
      expect(result.idempotencyKey, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
    });

    test('tries again with the same key and backoff', () async {
      transport.reportAnswers.addAll([const NetworkException(), const LimeniaException(502), receipt]);
      final result = await reporter.report(request, idempotencyKey: 'k');
      expect(result, isA<ReportSent>());
      expect(transport.reportCalls.map((c) => c.$2), ['k', 'k', 'k']);
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('waits at least Retry-After', () async {
      transport.reportAnswers.addAll([const LimeniaException(429, retryAfter: Duration(seconds: 5)), receipt]);
      await reporter.report(request);
      expect(sleeps, [const Duration(seconds: 5)]);
    });

    test('queues the report when Limenia asks to wait too long', () async {
      transport.reportAnswers.add(const LimeniaException(429, retryAfter: Duration(minutes: 1)));
      final result = await reporter.report(request, idempotencyKey: 'k');
      expect(result, isA<ReportQueued>());
      expect(sleeps, isEmpty);
      expect((await store.load()).single.idempotencyKey, 'k');
    });

    test('queues the report after the last attempt', () async {
      transport.reportAnswers.addAll([const NetworkException(), const NetworkException(), const NetworkException()]);
      final result = await reporter.report(request, idempotencyKey: 'k');
      expect(result, isA<ReportQueued>().having((r) => r.error, 'error', isA<NetworkException>()));
      expect(transport.reportCalls, hasLength(3));
      final pending = (await store.load()).single;
      expect(pending.idempotencyKey, 'k');
      expect(pending.createdAt, clock.now);
      expect(pending.request.toJson(), request.toJson());
    });

    test('a rejected report is not kept', () async {
      transport.reportAnswers.add(const LimeniaException(409, code: 'idempotency_key_reused'));
      final result = await reporter.report(request, idempotencyKey: 'k');
      expect(result, isA<ReportFailed>().having((r) => r.error, 'error', isA<LimeniaException>()));
      expect((result as ReportFailed).fieldErrors, isEmpty);
      expect(transport.reportCalls, hasLength(1));
      expect(await store.load(), isEmpty);
    });

    test('a tenant that is not active yet is tried later', () async {
      reporter = build(policy: const RetryPolicy(maxAttempts: 1));
      transport.reportAnswers.add(const LimeniaException(403, code: 'tenant_not_active'));
      expect(await reporter.report(request), isA<ReportQueued>());
    });

    test('exposes the warning of a reporter', () async {
      final warned = ReportReceipt(
        reportId: 'r',
        caseId: 'c',
        caseCreated: false,
        reporterWarning: ReporterWarning(issuedAt: DateTime.utc(2026, 10, 4, 8, 30)),
      );
      transport.reportAnswers.addAll([warned, receipt]);
      final result = await reporter.report(request) as ReportSent;
      expect(result.reporterWarning, ReporterWarning(issuedAt: DateTime.utc(2026, 10, 4, 8, 30)));
      expect(result.receipt, warned);
      expect((await reporter.report(request) as ReportSent).reporterWarning, isNull);
    });

    test('a suspended reporter is refused, not retried and not kept', () async {
      transport.reportAnswers.add(LimeniaException.fromResponse(status: 403, body: {
        'status': 403,
        'code': 'reporter_suspended',
        'suspendedUntil': '2026-11-01T10:00:00Z',
      }));
      final result = await reporter.report(request, idempotencyKey: 'k');
      expect(result, isA<ReportFailed>());
      final failed = result as ReportFailed;
      expect(failed.code, 'reporter_suspended');
      expect(failed.isReporterSuspended, isTrue);
      expect(failed.suspendedUntil, DateTime.utc(2026, 11, 1, 10));
      expect(failed.fieldErrors, isEmpty);
      expect(transport.reportCalls, hasLength(1));
      expect(sleeps, isEmpty);
      expect(await store.load(), isEmpty);
    });

    test('a suspension without suspendedUntil is still final', () async {
      transport.reportAnswers.add(const LimeniaException(403, code: 'reporter_suspended'));
      final failed = await reporter.report(request) as ReportFailed;
      expect(failed.isReporterSuspended, isTrue);
      expect(failed.suspendedUntil, isNull);
      expect(await store.load(), isEmpty);
    });

    test('a suspension is final whatever status the backend of the app gives it', () async {
      // Neither a retryable status nor a 401 keeps the request.
      for (final status in [401, 429, 503]) {
        transport.reportAnswers.add(LimeniaException(status, code: 'reporter_suspended'));
        final result = await reporter.report(request);
        expect(result, isA<ReportFailed>(), reason: '$status');
        expect((result as ReportFailed).isReporterSuspended, isTrue, reason: '$status');
      }
      expect(transport.reportCalls, hasLength(3));
      expect(sleeps, isEmpty);
      expect(await store.load(), isEmpty);
    });

    test('other results have no suspension', () async {
      transport.reportAnswers.addAll([
        const LimeniaException(409, code: 'idempotency_key_reused'),
        const FormatException('broken'),
      ]);
      for (var i = 0; i < 2; i++) {
        final failed = await reporter.report(request) as ReportFailed;
        expect(failed.isReporterSuspended, isFalse);
        expect(failed.suspendedUntil, isNull);
      }
      const invalid = ReportRequest.user(reasonCategory: 'Spam!', subject: ReportedUser('u'));
      final local = await reporter.report(invalid) as ReportFailed;
      expect(local.isReporterSuspended, isFalse);
      expect(local.suspendedUntil, isNull);
    });

    test('a trusted flagger report goes to the transport unchanged', () async {
      const flagged = ReportRequest.user(
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        reporterId: 'u_2',
        trustedFlaggerId: '01K6T2D0000000000000000000',
      );
      transport.reportAnswers.add(receipt);
      expect(await reporter.report(flagged), isA<ReportSent>());
      expect(transport.reportCalls.single.$1.trustedFlaggerId, '01K6T2D0000000000000000000');
    });

    test('an invalid trusted flagger is neither sent nor kept', () async {
      const invalid = ReportRequest(
        source: ReportSource.system,
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        trustedFlaggerId: '01K6T2D0000000000000000000',
      );
      final result = await reporter.report(invalid) as ReportFailed;
      expect(result.fieldErrors, [const FieldError('/trustedFlaggerId', 'invalid')]);
      expect(transport.reportCalls, isEmpty);
      expect(await store.load(), isEmpty);
    });

    test('goodFaith (API 0.22.0) goes to the transport, and with source system it is neither sent nor kept', () async {
      const confirmed = ReportRequest.user(
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        reporterId: 'u_2',
        goodFaith: true,
      );
      transport.reportAnswers.add(receipt);
      expect(await reporter.report(confirmed), isA<ReportSent>());
      expect(transport.reportCalls.single.$1.goodFaith, isTrue);
      expect(transport.reportCalls.single.$1.toJson()['goodFaith'], isTrue);

      const system = ReportRequest(
        source: ReportSource.system,
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        goodFaith: false,
      );
      final result = await reporter.report(system) as ReportFailed;
      expect(result.fieldErrors, [const FieldError('/goodFaith', 'invalid')]);
      expect(transport.reportCalls, hasLength(1));
      expect(await store.load(), isEmpty);
    });

    test('an invalid report is neither sent nor kept', () async {
      const invalid = ReportRequest.user(reasonCategory: 'Spam!', subject: ReportedUser('u'));
      final result = await reporter.report(invalid);
      expect(
        result,
        isA<ReportFailed>().having(
          (r) => (r.error as ReportValidationException).errors,
          'errors',
          [const FieldError('/reasonCategory', 'invalid')],
        ),
      );
      expect((result as ReportFailed).fieldErrors.single.field, '/reasonCategory');
      expect(transport.reportCalls, isEmpty);
      expect(await store.load(), isEmpty);
    });

    test('field errors of Limenia are available without a cast', () async {
      transport.reportAnswers.add(LimeniaException.fromResponse(status: 400, body: {
        'code': 'validation_failed',
        'errors': [
          {'field': '/content/media/0/url', 'code': 'invalid'},
        ],
      }));
      final result = await reporter.report(request) as ReportFailed;
      expect(result.fieldErrors, [const FieldError('/content/media/0/url', 'invalid')]);
    });

    test('bugs in the transport are not retried and do not stay queued', () async {
      transport.reportAnswers.add(StateError('bug'));
      await expectLater(reporter.report(request), throwsStateError);
      expect(transport.reportCalls, hasLength(1));
      expect(await store.load(), isEmpty);
    });

    test('an answer that cannot be read is final', () async {
      transport.reportAnswers.add(const FormatException('Limenia: field "caseId" is missing'));
      final result = await reporter.report(request);
      expect(result, isA<ReportFailed>().having((r) => r.error, 'error', isA<FormatException>()));
      expect((result as ReportFailed).code, isNull);
      expect(transport.reportCalls, hasLength(1));
      expect(await store.load(), isEmpty);
    });

    test('a 401 keeps the report without trying again now', () async {
      transport.reportAnswers.add(const LimeniaException(401, code: 'unauthenticated'));
      final result = await reporter.report(request, idempotencyKey: 'k');
      expect(result, isA<ReportQueued>().having((r) => (r.error as LimeniaException).status, 'status', 401));
      expect(transport.reportCalls, hasLength(1));
      expect(sleeps, isEmpty);
      expect((await store.load()).single.idempotencyKey, 'k');
    });

    test('server and CDN errors are tried again, 501 and 505 are not', () async {
      reporter = build(policy: const RetryPolicy(maxAttempts: 1));
      for (final status in [500, 502, 503, 504, 507, 520, 524, 599]) {
        transport.reportAnswers.add(LimeniaException(status));
        expect(await reporter.report(request), isA<ReportQueued>(), reason: '$status');
      }
      for (final status in [501, 505]) {
        transport.reportAnswers.add(LimeniaException(status));
        expect(await reporter.report(request), isA<ReportFailed>(), reason: '$status');
      }
    });

    test('ReportFailed exposes the code', () async {
      transport.reportAnswers.add(const LimeniaException(409, code: 'idempotency_key_reused'));
      final result = await reporter.report(request) as ReportFailed;
      expect(result.code, 'idempotency_key_reused');
    });

    test('the same key cannot be sent twice at the same time', () async {
      final gate = Completer<void>();
      final slow = LimeniaReporter(transport: _GatedTransport(gate.future), store: store);
      final first = slow.report(request, idempotencyKey: 'k');
      await expectLater(slow.report(request, idempotencyKey: 'k'), throwsStateError);
      gate.complete();
      expect(await first, isA<ReportSent>());
    });
  });

  group('sendPending', () {
    Future<void> queue(String key) async {
      transport.reportAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      expect(await reporter.report(request, idempotencyKey: key), isA<ReportQueued>());
    }

    test('sends queued reports oldest first with their keys', () async {
      await queue('a');
      clock.now = clock.now.add(const Duration(minutes: 1));
      await queue('b');
      transport.reportAnswers.addAll([receipt, receipt]);
      final results = await reporter.sendPending();
      expect(results.map((r) => (r.runtimeType, r.idempotencyKey)), [(ReportSent, 'a'), (ReportSent, 'b')]);
      expect(transport.reportCalls.skip(2).map((c) => c.$2), ['a', 'b']);
      expect(await reporter.pending(), isEmpty);
    });

    test('stops at the first report that is queued again', () async {
      await queue('a');
      await queue('b');
      transport.reportAnswers.add(const NetworkException());
      final results = await reporter.sendPending();
      expect(results.single, isA<ReportQueued>());
      expect(sleeps, isEmpty);
      expect((await reporter.pending()).map((p) => p.idempotencyKey), ['a', 'b']);
    });

    test('drops a rejected report and goes on', () async {
      await queue('a');
      await queue('b');
      transport.reportAnswers.addAll([const LimeniaException(400, code: 'validation_failed'), receipt]);
      final results = await reporter.sendPending();
      expect(results.map((r) => r.runtimeType), [ReportFailed, ReportSent]);
      expect(await reporter.pending(), isEmpty);
    });

    test('drops the reports of a suspended reporter and goes on', () async {
      await queue('a');
      await queue('b');
      await queue('c');
      transport.reportAnswers.addAll([
        LimeniaException.fromResponse(
            status: 403, body: {'code': 'reporter_suspended', 'suspendedUntil': '2026-11-01T10:00:00Z'}),
        const LimeniaException(403, code: 'reporter_suspended'),
        receipt,
      ]);
      final results = await reporter.sendPending();
      expect(results.map((r) => r.runtimeType), [ReportFailed, ReportFailed, ReportSent]);
      expect((results.first as ReportFailed).suspendedUntil, DateTime.utc(2026, 11, 1, 10));
      expect((results[1] as ReportFailed).isReporterSuspended, isTrue);
      expect(await reporter.pending(), isEmpty);
    });

    test('a report that went out from the queue carries the warning', () async {
      await queue('a');
      final warned = ReportReceipt(
        reportId: 'r',
        caseId: 'c',
        caseCreated: true,
        reporterWarning: ReporterWarning(issuedAt: DateTime.utc(2026, 10, 4)),
      );
      transport.reportAnswers.add(warned);
      final result = (await reporter.sendPending()).single as ReportSent;
      expect(result.reporterWarning?.issuedAt, DateTime.utc(2026, 10, 4));
    });

    test('drops reports older than maxPendingAge', () async {
      await queue('old');
      clock.now = clock.now.add(const Duration(days: 7, seconds: 1));
      final results = await reporter.sendPending();
      expect(results.single, isA<ReportExpired>().having((r) => r.idempotencyKey, 'key', 'old'));
      expect(transport.reportCalls, hasLength(1));
      expect(await reporter.pending(), isEmpty);
    });

    test('a 401 keeps every queued report and stops', () async {
      await queue('a');
      await queue('b');
      transport.reportAnswers.add(const LimeniaException(401));
      final results = await reporter.sendPending();
      expect(results.single, isA<ReportQueued>());
      expect(transport.reportCalls, hasLength(3));
      expect((await reporter.pending()).map((p) => p.idempotencyKey), ['a', 'b']);
    });

    test('a bug for one report does not block the others', () async {
      await queue('a');
      await queue('b');
      transport.reportAnswers.add(StateError('bug'));
      await expectLater(reporter.sendPending(), throwsStateError);
      expect((await reporter.pending()).map((p) => p.idempotencyKey), ['b']);
      transport.reportAnswers.add(receipt);
      expect((await reporter.sendPending()).single, isA<ReportSent>());
      expect(await reporter.pending(), isEmpty);
    });

    test('keeps reports in a persistent store across instances', () async {
      await queue('a');
      final restarted = LimeniaReporter(transport: transport, store: store, now: clock.call);
      transport.reportAnswers.add(receipt);
      expect((await restarted.sendPending()).single, isA<ReportSent>());
    });
  });

  group('appeal', () {
    test('sends with the key and removes the complaint from the store', () async {
      transport.appealAnswers.add(appealReceipt);
      final result = await reporter.appeal(appealRequest, idempotencyKey: 'appeal-1');
      expect(result, isA<AppealSent>().having((r) => r.receipt, 'receipt', appealReceipt));
      expect(transport.appealCalls.single.$2, 'appeal-1');
      expect(transport.appealCalls.single.$1.toJson(), appealRequest.toJson());
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('tries again with the same key and creates a ULID', () async {
      transport.appealAnswers.addAll([const NetworkException(), appealReceipt]);
      final result = await reporter.appeal(appealRequest);
      expect(result, isA<AppealSent>());
      expect(result.idempotencyKey, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
      expect(transport.appealCalls.map((c) => c.$2).toSet(), {result.idempotencyKey});
      expect(sleeps, [const Duration(seconds: 1)]);
    });

    test('a rejected complaint is not kept and exposes the code', () async {
      for (final (status, code) in [
        (403, 'appeal_not_allowed'),
        (409, 'appeal_window_closed'),
        (409, 'appeal_already_open'),
        (409, 'idempotency_key_reused'),
        (404, 'not_found'),
      ]) {
        transport.appealAnswers.add(LimeniaException(status, code: code));
        final result = await reporter.appeal(appealRequest);
        expect(result, isA<AppealFailed>().having((r) => r.code, 'code', code));
      }
      expect(transport.appealCalls, hasLength(5));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('a suspended reporter is refused a complaint, which is not kept', () async {
      transport.appealAnswers.add(LimeniaException.fromResponse(status: 403, body: {
        'status': 403,
        'code': 'reporter_suspended',
        'suspendedUntil': '2026-11-01T10:00:00Z',
      }));
      final result = await reporter.appeal(appealRequest, idempotencyKey: 'a');
      expect(result, isA<AppealFailed>());
      final failed = result as AppealFailed;
      expect(failed.code, 'reporter_suspended');
      expect(failed.isReporterSuspended, isTrue);
      expect(failed.suspendedUntil, DateTime.utc(2026, 11, 1, 10));
      expect(transport.appealCalls, hasLength(1));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('a suspension of a complaint is final whatever status it comes with', () async {
      for (final status in [401, 429, 503]) {
        transport.appealAnswers.add(LimeniaException(status, code: 'reporter_suspended'));
        final result = await reporter.appeal(appealRequest);
        expect(result, isA<AppealFailed>().having((r) => r.isReporterSuspended, 'isReporterSuspended', isTrue));
        expect((result as AppealFailed).suspendedUntil, isNull);
      }
      expect(transport.appealCalls, hasLength(3));
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('drops queued complaints of a suspended reporter and goes on', () async {
      reporter = build(policy: const RetryPolicy(maxAttempts: 1));
      for (final key in ['a', 'b']) {
        transport.appealAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
        expect(await reporter.appeal(appealRequest, idempotencyKey: key), isA<AppealQueued>());
      }
      transport.appealAnswers.addAll([const LimeniaException(403, code: 'reporter_suspended'), appealReceipt]);
      final results = await reporter.sendPendingAppeals();
      expect(results.map((r) => r.runtimeType), [AppealFailed, AppealSent]);
      expect((results.first as AppealFailed).isReporterSuspended, isTrue);
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('other results of a complaint have no suspension', () async {
      transport.appealAnswers.add(const LimeniaException(403, code: 'appeal_not_allowed'));
      final failed = await reporter.appeal(appealRequest) as AppealFailed;
      expect(failed.isReporterSuspended, isFalse);
      expect(failed.suspendedUntil, isNull);
      const invalid = AppealRequest.subject(decisionId: 'd', externalUserId: 'u', text: '');
      final local = await reporter.appeal(invalid) as AppealFailed;
      expect(local.isReporterSuspended, isFalse);
      expect(local.suspendedUntil, isNull);
    });

    test('a tenant that is not active yet keeps the complaint', () async {
      reporter = build(policy: const RetryPolicy(maxAttempts: 1));
      transport.appealAnswers.add(const LimeniaException(403, code: 'tenant_not_active'));
      expect(await reporter.appeal(appealRequest), isA<AppealQueued>());
      expect(await reporter.pendingAppeals(), hasLength(1));
    });

    test('a bug in the transport does not stay queued', () async {
      transport.appealAnswers.add(ArgumentError('bug'));
      await expectLater(reporter.appeal(appealRequest), throwsArgumentError);
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('an invalid complaint is neither sent nor kept', () async {
      const invalid = AppealRequest.subject(decisionId: 'd', externalUserId: 'u', text: '');
      final result = await reporter.appeal(invalid) as AppealFailed;
      expect(result.error, isA<AppealValidationException>());
      expect(result.code, isNull);
      expect(result.fieldErrors, [const FieldError('/decisionId', 'invalid'), const FieldError('/text', 'required')]);
      expect(transport.appealCalls, isEmpty);
      expect(await reporter.pendingAppeals(), isEmpty);
    });

    test('queues and sends later, oldest first', () async {
      transport.appealAnswers.addAll([const NetworkException(), const NetworkException(), const NetworkException()]);
      expect(await reporter.appeal(appealRequest, idempotencyKey: 'a'), isA<AppealQueued>());
      transport.appealAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      clock.now = clock.now.add(const Duration(minutes: 1));
      expect(await reporter.appeal(appealRequest, idempotencyKey: 'b'), isA<AppealQueued>());
      expect((await reporter.pendingAppeals()).map((p) => p.idempotencyKey), ['a', 'b']);

      transport.appealAnswers.addAll([appealReceipt, appealReceipt]);
      final results = await reporter.sendPendingAppeals();
      expect(results.map((r) => (r.runtimeType, r.idempotencyKey)), [(AppealSent, 'a'), (AppealSent, 'b')]);
      expect(await reporter.pendingAppeals(), isEmpty);
      // Reports are untouched.
      expect(transport.reportCalls, isEmpty);
    });

    test('sendPendingAppeals stops at the first complaint queued again and drops old ones', () async {
      transport.appealAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.appeal(appealRequest, idempotencyKey: 'old');
      clock.now = clock.now.add(const Duration(days: 7, seconds: 1));
      transport.appealAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.appeal(appealRequest, idempotencyKey: 'new');

      transport.appealAnswers.add(const NetworkException());
      final results = await reporter.sendPendingAppeals();
      expect(results.map((r) => r.runtimeType), [AppealExpired, AppealQueued]);
      expect((await reporter.pendingAppeals()).map((p) => p.idempotencyKey), ['new']);
    });
  });

  group('submitForReview', () {
    test('sends with the key and removes the request from the store', () async {
      transport.reviewAnswers.add(reviewReceipt);
      final result = await reporter.submitForReview(reviewRequest, idempotencyKey: 'review-1');
      expect(result, isA<ReviewSent>().having((r) => r.receipt, 'receipt', reviewReceipt));
      expect(transport.reviewCalls.single.$2, 'review-1');
      expect(transport.reviewCalls.single.$1.toJson(), reviewRequest.toJson());
      expect(await reporter.pendingReviews(), isEmpty);
    });

    test('tries again with the same key, respects Retry-After and creates a ULID', () async {
      transport.reviewAnswers.addAll([
        const NetworkException(),
        const LimeniaException(429, code: 'rate_limited', retryAfter: Duration(seconds: 3)),
        reviewReceipt,
      ]);
      final result = await reporter.submitForReview(reviewRequest);
      expect(result, isA<ReviewSent>());
      expect(result.idempotencyKey, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
      expect(transport.reviewCalls.map((c) => c.$2).toSet(), {result.idempotencyKey});
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 3)]);
    });

    test('an unknown review type comes with the field /type', () async {
      // The problem body Limenia sends for review_type_unknown.
      transport.reviewAnswers.add(LimeniaException.fromResponse(status: 400, body: {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'detail': 'The request contains invalid fields.',
        'code': 'review_type_unknown',
        'errors': [
          {'field': '/type', 'code': 'unknown', 'message': 'no active review type of the app has this code'},
        ],
      }));
      final result = await reporter.submitForReview(reviewRequest) as ReviewFailed;
      expect(result.code, 'review_type_unknown');
      expect(result.fieldErrors.single.field, '/type');
      expect(result.fieldErrors.single.code, 'unknown');
    });

    test('a tenant that is not active yet and a 401 keep the request', () async {
      reporter = build(policy: const RetryPolicy(maxAttempts: 1));
      transport.reviewAnswers.addAll([
        const LimeniaException(403, code: 'tenant_not_active'),
        const LimeniaException(401, code: 'unauthenticated'),
      ]);
      expect(await reporter.submitForReview(reviewRequest), isA<ReviewQueued>());
      expect(await reporter.submitForReview(reviewRequest), isA<ReviewQueued>());
      expect(await reporter.pendingReviews(), hasLength(2));
    });

    test('a bug in the transport does not stay queued', () async {
      transport.reviewAnswers.add(TypeError());
      await expectLater(reporter.submitForReview(reviewRequest), throwsA(isA<TypeError>()));
      expect(await reporter.pendingReviews(), isEmpty);
    });

    test('a rejected request is not kept and exposes the code', () async {
      for (final (status, code) in [
        (400, 'review_type_unknown'),
        (400, 'bad_request'),
        (409, 'idempotency_key_reused'),
      ]) {
        transport.reviewAnswers.add(LimeniaException(status, code: code));
        final result = await reporter.submitForReview(reviewRequest);
        expect(result, isA<ReviewFailed>().having((r) => r.code, 'code', code));
        expect((result as ReviewFailed).fieldErrors, isEmpty);
      }
      expect(transport.reviewCalls, hasLength(3));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingReviews(), isEmpty);
    });

    test('the plan of the tenant blocks review requests for good', () async {
      for (final (status, code) in [(402, 'subscription_required'), (403, 'feature_not_in_plan')]) {
        transport.reviewAnswers.add(LimeniaException.fromResponse(
          status: status,
          body: {'type': 'about:blank', 'title': 'Payment Required', 'status': status, 'code': code},
        ));
        final result = await reporter.submitForReview(reviewRequest);
        expect(result, isA<ReviewFailed>().having((r) => r.code, 'code', code));
      }
      expect(transport.reviewCalls, hasLength(2));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingReviews(), isEmpty);
    });

    test('a queued request that the plan blocks later is dropped', () async {
      transport.reviewAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      expect(await reporter.submitForReview(reviewRequest), isA<ReviewQueued>());
      transport.reviewAnswers.add(const LimeniaException(402, code: 'subscription_required'));
      final results = await reporter.sendPendingReviews();
      expect(results.single, isA<ReviewFailed>().having((r) => r.code, 'code', 'subscription_required'));
      expect(await reporter.pendingReviews(), isEmpty);
    });

    test('field errors of Limenia are available without a cast', () async {
      transport.reviewAnswers.add(LimeniaException.fromResponse(status: 400, body: {
        'code': 'validation_failed',
        'errors': [
          {'field': '/content/media/0/url', 'code': 'invalid'},
        ],
      }));
      final result = await reporter.submitForReview(reviewRequest) as ReviewFailed;
      expect(result.code, 'validation_failed');
      expect(result.fieldErrors, [const FieldError('/content/media/0/url', 'invalid')]);
    });

    test('an invalid request is neither sent nor kept', () async {
      const invalid = ReviewRequest(
        type: 'ProfilePhoto',
        content: ReportedContent(externalContentId: 'p', contentType: 'image'),
        externalReviewId: '',
      );
      final result = await reporter.submitForReview(invalid) as ReviewFailed;
      expect(result.error, isA<ReviewValidationException>());
      expect(result.code, isNull);
      expect(
          result.fieldErrors, [const FieldError('/type', 'invalid'), const FieldError('/externalReviewId', 'invalid')]);
      expect(transport.reviewCalls, isEmpty);
      expect(await reporter.pendingReviews(), isEmpty);
    });

    test('queues and sends later, oldest first, apart from reports and complaints', () async {
      transport.reviewAnswers.addAll([const NetworkException(), const NetworkException(), const NetworkException()]);
      expect(await reporter.submitForReview(reviewRequest, idempotencyKey: 'a'), isA<ReviewQueued>());
      transport.reviewAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      clock.now = clock.now.add(const Duration(minutes: 1));
      expect(await reporter.submitForReview(reviewRequest, idempotencyKey: 'b'), isA<ReviewQueued>());
      expect((await reporter.pendingReviews()).map((p) => p.idempotencyKey), ['a', 'b']);
      expect(await reporter.pending(), isEmpty);
      expect(await reporter.pendingAppeals(), isEmpty);

      transport.reviewAnswers.addAll([reviewReceipt, reviewReceipt]);
      final results = await reporter.sendPendingReviews();
      expect(results.map((r) => (r.runtimeType, r.idempotencyKey)), [(ReviewSent, 'a'), (ReviewSent, 'b')]);
      expect(await reporter.pendingReviews(), isEmpty);
      expect(transport.reportCalls, isEmpty);
      expect(transport.appealCalls, isEmpty);
    });

    test('sendPendingReviews stops at the first request queued again and drops old ones', () async {
      transport.reviewAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.submitForReview(reviewRequest, idempotencyKey: 'old');
      clock.now = clock.now.add(const Duration(days: 7, seconds: 1));
      transport.reviewAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.submitForReview(reviewRequest, idempotencyKey: 'new');

      transport.reviewAnswers.add(const NetworkException());
      final results = await reporter.sendPendingReviews();
      expect(results.map((r) => r.runtimeType), [ReviewExpired, ReviewQueued]);
      expect((await reporter.pendingReviews()).map((p) => p.idempotencyKey), ['new']);
    });

    test('the same key cannot be sent twice at the same time', () async {
      final gate = Completer<ReviewReceipt>();
      final slow = LimeniaReporter(transport: _GatedReviewTransport(gate.future), reviewStore: reviewStore);
      final first = slow.submitForReview(reviewRequest, idempotencyKey: 'k');
      await expectLater(slow.submitForReview(reviewRequest, idempotencyKey: 'k'), throwsStateError);
      gate.complete(reviewReceipt);
      expect(await first, isA<ReviewSent>());
    });

    test('keeps requests in a persistent store across instances', () async {
      transport.reviewAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.submitForReview(reviewRequest, idempotencyKey: 'a');
      final restarted = Limenia(transport: transport, pendingReviews: reviewStore, now: clock.call);
      transport.reviewAnswers.add(reviewReceipt);
      expect((await restarted.sendPendingReviews()).single, isA<ReviewSent>());
      expect(await reviewStore.load(), isEmpty);
    });
  });

  group('sendSignals', () {
    test('sends with the key and removes the signals from the store', () async {
      transport.signalsAnswers.add(signalsReceipt);
      final result = await reporter.sendSignals(signalsRequest, idempotencyKey: 'signals-1');
      expect(result, isA<SignalsSent>().having((r) => r.accepted, 'accepted', 2));
      expect(result.idempotencyKey, 'signals-1');
      expect(transport.signalsCalls.single.$2, 'signals-1');
      expect(transport.signalsCalls.single.$1.toJson(), signalsRequest.toJson());
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('tries again with the same key, respects Retry-After and creates a ULID', () async {
      transport.signalsAnswers.addAll([
        const NetworkException(),
        const LimeniaException(429, code: 'rate_limited', retryAfter: Duration(seconds: 3)),
        signalsReceipt,
      ]);
      final result = await reporter.sendSignals(signalsRequest);
      expect(result, isA<SignalsSent>());
      expect(result.idempotencyKey, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
      expect(transport.signalsCalls.map((c) => c.$2).toSet(), {result.idempotencyKey});
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 3)]);
    });

    test('queues after the attempts are used up, on a long Retry-After and on a 5xx', () async {
      transport.signalsAnswers
          .addAll([const NetworkException(), const LimeniaException(500), const LimeniaException(502)]);
      expect(await reporter.sendSignals(signalsRequest, idempotencyKey: 'a'), isA<SignalsQueued>());
      expect(transport.signalsCalls, hasLength(3));
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      expect(await reporter.sendSignals(signalsRequest, idempotencyKey: 'b'), isA<SignalsQueued>());
      expect((await reporter.pendingSignals()).map((p) => p.idempotencyKey), ['a', 'b']);
    });

    test('a tenant that is not active yet and a 401 keep the signals', () async {
      reporter = build(policy: const RetryPolicy(maxAttempts: 1));
      transport.signalsAnswers.addAll([
        const LimeniaException(403, code: 'tenant_not_active'),
        const LimeniaException(401, code: 'unauthenticated'),
      ]);
      expect(await reporter.sendSignals(signalsRequest), isA<SignalsQueued>());
      expect(await reporter.sendSignals(signalsRequest), isA<SignalsQueued>());
      expect(await reporter.pendingSignals(), hasLength(2));
      expect(sleeps, isEmpty);
    });

    test('an unknown signal type is final and comes with the position', () async {
      // The problem body Limenia sends for signal_type_unknown.
      transport.signalsAnswers.add(LimeniaException.fromResponse(status: 400, body: {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'detail': 'The request contains invalid fields.',
        'code': 'signal_type_unknown',
        'errors': [
          {'field': '/signals/1/type', 'code': 'unknown', 'message': 'no active signal type of the app has this code'},
        ],
      }));
      final result = await reporter.sendSignals(signalsRequest) as SignalsFailed;
      expect(result.code, 'signal_type_unknown');
      expect(result.fieldErrors.single.field, '/signals/1/type');
      expect(transport.signalsCalls, hasLength(1));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('rejected requests are not kept and expose the code', () async {
      for (final (status, code) in [
        (400, 'validation_failed'),
        (409, 'idempotency_key_reused'),
        (403, 'forbidden'),
        (404, 'not_found'),
      ]) {
        transport.signalsAnswers.add(LimeniaException(status, code: code));
        final result = await reporter.sendSignals(signalsRequest);
        expect(result, isA<SignalsFailed>().having((r) => r.code, 'code', code));
        expect((result as SignalsFailed).fieldErrors, isEmpty);
      }
      expect(transport.signalsCalls, hasLength(4));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('the plan of the tenant blocks signals for good', () async {
      for (final (status, code) in [(402, 'subscription_required'), (403, 'feature_not_in_plan')]) {
        transport.signalsAnswers.add(LimeniaException.fromResponse(
          status: status,
          body: {'type': 'about:blank', 'title': 'Payment Required', 'status': status, 'code': code},
        ));
        final result = await reporter.sendSignals(signalsRequest);
        expect(result, isA<SignalsFailed>().having((r) => r.code, 'code', code));
      }
      expect(transport.signalsCalls, hasLength(2));
      expect(sleeps, isEmpty);
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('queued signals that the plan blocks later are dropped', () async {
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      expect(await reporter.sendSignals(signalsRequest), isA<SignalsQueued>());
      transport.signalsAnswers.add(const LimeniaException(403, code: 'feature_not_in_plan'));
      final results = await reporter.sendPendingSignals();
      expect(results.single, isA<SignalsFailed>().having((r) => r.code, 'code', 'feature_not_in_plan'));
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('an answer that cannot be read ends the request', () async {
      transport.signalsAnswers.add(const FormatException('Limenia: field "accepted" is missing or not a int'));
      final result = await reporter.sendSignals(signalsRequest);
      expect(result, isA<SignalsFailed>().having((r) => r.error, 'error', isA<FormatException>()));
      expect(transport.signalsCalls, hasLength(1));
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('a bug in the transport does not stay queued', () async {
      transport.signalsAnswers.add(TypeError());
      await expectLater(reporter.sendSignals(signalsRequest), throwsA(isA<TypeError>()));
      expect(await reporter.pendingSignals(), isEmpty);
    });

    test('invalid signals are neither sent nor kept', () async {
      const invalid = SignalsRequest([
        SignalInput(type: 'score_jump', externalUserId: 'u_1'),
        SignalInput(type: 'Score', externalUserId: ''),
      ]);
      final result = await reporter.sendSignals(invalid) as SignalsFailed;
      expect(result.error, isA<SignalsValidationException>());
      expect(result.code, isNull);
      expect(result.fieldErrors, [
        const FieldError('/signals/1/type', 'invalid'),
        const FieldError('/signals/1/externalUserId', 'invalid'),
      ]);
      expect(transport.signalsCalls, isEmpty);
      expect(await reporter.pendingSignals(), isEmpty);

      final empty = await reporter.sendSignals(const SignalsRequest([]), idempotencyKey: '') as SignalsFailed;
      expect(empty.fieldErrors,
          [const FieldError('Idempotency-Key', 'invalid'), const FieldError('/signals', 'required')]);
      expect(transport.signalsCalls, isEmpty);
    });

    test('queues and sends later, oldest first, apart from reports, complaints and reviews', () async {
      transport.signalsAnswers.addAll([const NetworkException(), const NetworkException(), const NetworkException()]);
      expect(await reporter.sendSignals(signalsRequest, idempotencyKey: 'a'), isA<SignalsQueued>());
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      clock.now = clock.now.add(const Duration(minutes: 1));
      expect(await reporter.sendSignals(signalsRequest, idempotencyKey: 'b'), isA<SignalsQueued>());
      expect((await reporter.pendingSignals()).map((p) => p.idempotencyKey), ['a', 'b']);
      expect(await reporter.pending(), isEmpty);
      expect(await reporter.pendingAppeals(), isEmpty);
      expect(await reporter.pendingReviews(), isEmpty);

      transport.signalsAnswers.addAll([signalsReceipt, signalsReceipt]);
      final results = await reporter.sendPendingSignals();
      expect(results.map((r) => (r.runtimeType, r.idempotencyKey)), [(SignalsSent, 'a'), (SignalsSent, 'b')]);
      expect(transport.signalsCalls.map((c) => c.$2).skip(4), ['a', 'b']);
      expect(await reporter.pendingSignals(), isEmpty);
      expect(transport.reportCalls, isEmpty);
      expect(transport.appealCalls, isEmpty);
      expect(transport.reviewCalls, isEmpty);
    });

    test('sendPendingSignals stops at the first request queued again and drops old ones', () async {
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.sendSignals(signalsRequest, idempotencyKey: 'old');
      clock.now = clock.now.add(const Duration(days: 7, seconds: 1));
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.sendSignals(signalsRequest, idempotencyKey: 'new');

      transport.signalsAnswers.add(const NetworkException());
      final results = await reporter.sendPendingSignals();
      expect(results.map((r) => r.runtimeType), [SignalsExpired, SignalsQueued]);
      expect((await reporter.pendingSignals()).map((p) => p.idempotencyKey), ['new']);
    });

    test('a shorter maxPendingAge drops stale signals', () async {
      reporter = build(policy: const RetryPolicy(maxPendingAge: Duration(hours: 1)));
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.sendSignals(signalsRequest, idempotencyKey: 'k');
      clock.now = clock.now.add(const Duration(hours: 1, seconds: 1));
      final results = await reporter.sendPendingSignals();
      expect(
          results.single, isA<SignalsExpired>().having((r) => r.createdAt, 'createdAt', DateTime.utc(2026, 10, 2, 12)));
      expect(transport.signalsCalls, hasLength(1));
    });

    test('the same key cannot be sent twice at the same time', () async {
      final gate = Completer<SignalsReceipt>();
      final slow = LimeniaReporter(transport: _GatedSignalsTransport(gate.future), signalsStore: signalsStore);
      final first = slow.sendSignals(signalsRequest, idempotencyKey: 'k');
      await expectLater(slow.sendSignals(signalsRequest, idempotencyKey: 'k'), throwsStateError);
      gate.complete(signalsReceipt);
      expect(await first, isA<SignalsSent>());
    });

    test('keeps requests in a persistent store across instances', () async {
      transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
      await reporter.sendSignals(signalsRequest, idempotencyKey: 'a');
      final restarted = Limenia(transport: transport, pendingSignals: signalsStore, now: clock.call);
      transport.signalsAnswers.add(signalsReceipt);
      expect((await restarted.sendPendingSignals()).single, isA<SignalsSent>());
      expect(await signalsStore.load(), isEmpty);
    });
  });

  test('PendingSignals survives a JSON round trip', () {
    final pending = PendingSignals(idempotencyKey: 'k', request: signalsRequest, createdAt: DateTime.utc(2026, 10, 5));
    final again = PendingSignals.fromJson(pending.toJson());
    expect(again.toJson(), pending.toJson());
    expect(again.request.signals.first.context, {'level': '7'});
    expect(again.createdAt, DateTime.utc(2026, 10, 5));
  });

  test('PendingReview survives a JSON round trip', () {
    final pending = PendingReview(idempotencyKey: 'k', request: reviewRequest, createdAt: DateTime.utc(2026, 10, 3));
    final again = PendingReview.fromJson(pending.toJson());
    expect(again.toJson(), pending.toJson());
    expect(again.request.author?.externalUserId, 'u_1');
  });

  test('PendingAppeal survives a JSON round trip', () {
    final pending = PendingAppeal(idempotencyKey: 'k', request: appealRequest, createdAt: DateTime.utc(2026, 10, 2));
    final again = PendingAppeal.fromJson(pending.toJson());
    expect(again.toJson(), pending.toJson());
  });

  test('PendingReport survives a JSON round trip', () {
    final pending = PendingReport(idempotencyKey: 'k', request: request, createdAt: DateTime.utc(2026, 10, 2));
    final again = PendingReport.fromJson(pending.toJson());
    expect(again.toJson(), pending.toJson());
  });

  test('RetryPolicy.delayAfter doubles up to maxDelay', () {
    const policy = RetryPolicy();
    expect([for (var i = 1; i <= 6; i++) policy.delayAfter(i).inSeconds], [1, 2, 4, 8, 8, 8]);
    expect(policy.delayAfter(1, retryAfter: const Duration(seconds: 3)), const Duration(seconds: 3));
    expect(policy.delayAfter(4, retryAfter: const Duration(seconds: 3)), const Duration(seconds: 8));
  });
}

final class _GatedTransport implements LimeniaTransport {
  _GatedTransport(this.gate);

  final Future<void> gate;

  @override
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey}) async {
    await gate;
    return receipt;
  }

  @override
  Future<SubjectStatus> getSubjectStatus(String externalUserId) => throw UnimplementedError();

  @override
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey}) =>
      throw UnimplementedError();

  @override
  Future<AppealStatusInfo> getAppealStatus(String appealId) => throw UnimplementedError();

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) =>
      throw UnimplementedError();

  @override
  Future<ReviewStatusInfo> getReviewStatus(String reviewId) => throw UnimplementedError();

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) =>
      throw UnimplementedError();

  @override
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) => throw UnimplementedError();
}

final class _GatedReviewTransport extends _GatedTransport {
  _GatedReviewTransport(this.answer) : super(Future<void>.value());

  final Future<ReviewReceipt> answer;

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) => answer;
}

final class _GatedSignalsTransport extends _GatedTransport {
  _GatedSignalsTransport(this.answer) : super(Future<void>.value());

  final Future<SignalsReceipt> answer;

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) => answer;
}
