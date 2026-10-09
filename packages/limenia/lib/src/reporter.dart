import 'dart:math';

import 'appeal.dart';
import 'errors.dart';
import 'idempotency.dart';
import 'pending.dart';
import 'report.dart';
import 'review.dart';
import 'signal.dart';
import 'transport.dart';
import 'validation.dart';

/// When and how often [LimeniaReporter] tries a report, a complaint, a review
/// request or signals again.
final class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 8),
    this.maxInlineWait = const Duration(seconds: 10),
    this.maxPendingAge = const Duration(days: 7),
  });

  /// Attempts per call of [LimeniaReporter.report], including the first. After
  /// that the report stays queued for [LimeniaReporter.sendPending].
  final int maxAttempts;

  /// Wait after the first failed attempt, doubled for every further one.
  final Duration initialDelay;
  final Duration maxDelay;

  /// If Limenia asks to wait longer than this (`Retry-After`), the report is
  /// queued at once instead of keeping the user waiting.
  final Duration maxInlineWait;

  /// The `sendPending…` methods drop older requests. Limenia keeps an
  /// idempotency key for at least 24 hours. A request sent again after that
  /// counts as a new one, which matters only in the rare case that the first
  /// attempt reached Limenia but its answer got lost:
  /// - a report arrives twice, and Limenia adds it to the same case while that
  ///   case is open;
  /// - a complaint gets `appeal_already_open` while the first one is open, or
  ///   becomes a second complaint once the first is resolved;
  /// - a review request is reviewed twice, and `review.decided` comes for a
  ///   review ID the app never got;
  /// - signals are stored twice and count twice for the rules and the usage.
  /// Set `externalAppealId` and `externalReviewId` so that the events can be
  /// matched in any case.
  ///
  /// Limenia also rejects signals whose `occurredAt` is more than 24 hours
  /// old, so queued signals older than that are dropped as `SignalsFailed`
  /// even within this age, unless `occurredAt` is left out. Signals are
  /// observations of the moment: for them a shorter age than the default is
  /// usually the better choice.
  final Duration maxPendingAge;

  /// Wait after failed attempt number [attempt] (1-based), at least
  /// [retryAfter].
  Duration delayAfter(int attempt, {Duration? retryAfter}) {
    final backoff = initialDelay * pow(2, attempt - 1).toInt();
    final capped = backoff > maxDelay ? maxDelay : backoff;
    return retryAfter != null && retryAfter > capped ? retryAfter : capped;
  }
}

/// Outcome of sending a report.
sealed class ReportResult {
  const ReportResult(this.idempotencyKey);

  final String idempotencyKey;
}

/// Limenia has the report.
final class ReportSent extends ReportResult {
  const ReportSent(super.idempotencyKey, this.receipt);

  final ReportReceipt receipt;

  /// The warning for the reporter if one stands, see
  /// [ReportReceipt.reporterWarning]: show it to them. A report that went out
  /// from the queue ([LimeniaReporter.sendPending]) carries it as well.
  ReporterWarning? get reporterWarning => receipt.reporterWarning;
}

/// Limenia cannot be reached right now. The report is kept and goes out with
/// the next [LimeniaReporter.sendPending].
final class ReportQueued extends ReportResult {
  const ReportQueued(super.idempotencyKey, this.error);

  /// The last error: a network error, a [LimeniaException] that may succeed
  /// later, or a 401 (log in again, then call [LimeniaReporter.sendPending]).
  final Exception error;
}

/// Limenia or the client rejected the report. It is not kept: sending it
/// again unchanged would fail again.
///
/// [code] tells why, e.g. `validation_failed` (400, see [fieldErrors]),
/// `idempotency_key_reused` (409, the key was used for another report) or,
/// from API version 0.16.0, `reporter_suspended` (403, see
/// [isReporterSuspended] and [suspendedUntil]). An answer of the transport
/// that cannot be read (a [FormatException]) also ends here.
final class ReportFailed extends ReportResult {
  const ReportFailed(super.idempotencyKey, this.error);

  /// A [ReportValidationException], a [LimeniaException] or a
  /// [FormatException].
  final Exception error;

  /// The code of a [LimeniaException], null otherwise.
  String? get code => switch (error) {
        final LimeniaException e => e.code,
        _ => null,
      };

  /// The invalid fields, from the check in the client or from Limenia.
  List<FieldError> get fieldErrors => switch (error) {
        final ReportValidationException e => e.errors,
        final LimeniaException e => e.fieldErrors,
        _ => const [],
      };

  /// Whether Limenia refused the report because the processing of the
  /// reporter's notices is suspended (Art. 23 DSA, `reporter_suspended`, API
  /// version 0.16.0). Limenia stored nothing and the report is not kept: tell
  /// the reporter that they cannot report until [suspendedUntil].
  bool get isReporterSuspended => switch (error) {
        final LimeniaException e => e.isReporterSuspended,
        _ => false,
      };

  /// The end of the suspension with [isReporterSuspended]. Null otherwise, and
  /// if the backend of the app did not pass the field on.
  DateTime? get suspendedUntil => switch (error) {
        final LimeniaException e when e.isReporterSuspended => e.suspendedUntil,
        _ => null,
      };
}

/// The report waited longer than [RetryPolicy.maxPendingAge] and was dropped.
final class ReportExpired extends ReportResult {
  const ReportExpired(super.idempotencyKey, this.createdAt);

  final DateTime createdAt;
}

/// Outcome of sending a complaint, like [ReportResult].
sealed class AppealResult {
  const AppealResult(this.idempotencyKey);

  final String idempotencyKey;
}

/// Limenia has the complaint.
final class AppealSent extends AppealResult {
  const AppealSent(super.idempotencyKey, this.receipt);

  final AppealReceipt receipt;
}

/// Limenia cannot be reached right now. The complaint is kept and goes out
/// with the next [LimeniaReporter.sendPendingAppeals].
final class AppealQueued extends AppealResult {
  const AppealQueued(super.idempotencyKey, this.error);

  /// The last error: a network error, a [LimeniaException] that may succeed
  /// later, or a 401 (log in again, then call
  /// [LimeniaReporter.sendPendingAppeals]).
  final Exception error;
}

/// Limenia or the client rejected the complaint. It is not kept.
///
/// [code] tells why: `appeal_not_allowed` (403, e.g. a subject complains
/// against a dismissal or the user did not report the case),
/// `appeal_window_closed` (409, more than six months after the decision),
/// `appeal_already_open` (409, this person already has an open complaint
/// against the decision), `idempotency_key_reused` (409, the key was used for
/// another complaint), `not_found` (404, unknown decision),
/// `validation_failed` (400, see [fieldErrors]) or, from API version 0.16.0,
/// `reporter_suspended` (403, a complaint of a reporter whose notices are
/// suspended, see [isReporterSuspended] and [suspendedUntil]). An answer of
/// the transport that cannot be read (a [FormatException]) also ends here.
final class AppealFailed extends AppealResult {
  const AppealFailed(super.idempotencyKey, this.error);

  /// An [AppealValidationException], a [LimeniaException] or a
  /// [FormatException].
  final Exception error;

  /// The code of a [LimeniaException], null otherwise.
  String? get code => switch (error) {
        final LimeniaException e => e.code,
        _ => null,
      };

  /// The invalid fields, from the check in the client or from Limenia.
  List<FieldError> get fieldErrors => switch (error) {
        final AppealValidationException e => e.errors,
        final LimeniaException e => e.fieldErrors,
        _ => const [],
      };

  /// Whether Limenia refused the complaint because the processing of the
  /// reporter's notices is suspended (Art. 23 DSA, `reporter_suspended`, API
  /// version 0.16.0). It concerns complaints of a reporter
  /// ([AppealRequest.reporter]) only; the affected user ([AppealRequest.subject])
  /// can always complain. Limenia stored nothing and the complaint is not
  /// kept: tell the reporter that they cannot complain until [suspendedUntil].
  bool get isReporterSuspended => switch (error) {
        final LimeniaException e => e.isReporterSuspended,
        _ => false,
      };

  /// The end of the suspension with [isReporterSuspended]. Null otherwise, and
  /// if the backend of the app did not pass the field on.
  DateTime? get suspendedUntil => switch (error) {
        final LimeniaException e when e.isReporterSuspended => e.suspendedUntil,
        _ => null,
      };
}

/// The complaint waited longer than [RetryPolicy.maxPendingAge] and was dropped.
final class AppealExpired extends AppealResult {
  const AppealExpired(super.idempotencyKey, this.createdAt);

  final DateTime createdAt;
}

/// Outcome of sending a review request, like [ReportResult].
sealed class ReviewResult {
  const ReviewResult(this.idempotencyKey);

  final String idempotencyKey;
}

/// Limenia has the review request. Publish the content only after
/// `review.decided` (or [ReviewStatusInfo.outcome]), and follow a later
/// `decision.created` with its `reviewId` if a complaint changes the result.
final class ReviewSent extends ReviewResult {
  const ReviewSent(super.idempotencyKey, this.receipt);

  final ReviewReceipt receipt;
}

/// Limenia cannot be reached right now. The review request is kept and goes
/// out with the next [LimeniaReporter.sendPendingReviews].
final class ReviewQueued extends ReviewResult {
  const ReviewQueued(super.idempotencyKey, this.error);

  /// The last error: a network error, a [LimeniaException] that may succeed
  /// later, or a 401 (log in again, then call
  /// [LimeniaReporter.sendPendingReviews]).
  final Exception error;
}

/// Limenia or the client rejected the review request. It is not kept.
///
/// [code] tells why, e.g. `review_type_unknown` (the type does not exist or
/// is inactive, field `/type` with code `unknown`), `idempotency_key_reused`
/// (409), `validation_failed` (400, see [fieldErrors]) and, from API version
/// 0.13.0, `subscription_required` (402) or `feature_not_in_plan` (403) when
/// the plan of the tenant does not allow review requests. An answer of the
/// transport that cannot be read (a [FormatException]) also ends here.
final class ReviewFailed extends ReviewResult {
  const ReviewFailed(super.idempotencyKey, this.error);

  /// A [ReviewValidationException], a [LimeniaException] or a
  /// [FormatException].
  final Exception error;

  /// The code of a [LimeniaException], null otherwise.
  String? get code => switch (error) {
        final LimeniaException e => e.code,
        _ => null,
      };

  /// The invalid fields, from the check in the client or from Limenia.
  List<FieldError> get fieldErrors => switch (error) {
        final ReviewValidationException e => e.errors,
        final LimeniaException e => e.fieldErrors,
        _ => const [],
      };
}

/// The review request waited longer than [RetryPolicy.maxPendingAge] and was
/// dropped.
final class ReviewExpired extends ReviewResult {
  const ReviewExpired(super.idempotencyKey, this.createdAt);

  final DateTime createdAt;
}

/// Outcome of sending signals, like [ReportResult].
sealed class SignalsResult {
  const SignalsResult(this.idempotencyKey);

  final String idempotencyKey;
}

/// Limenia has the signals. Rules are evaluated afterwards in the background
/// and the answer says nothing about them.
final class SignalsSent extends SignalsResult {
  const SignalsSent(super.idempotencyKey, this.receipt);

  final SignalsReceipt receipt;

  /// Number of signals Limenia stored.
  int get accepted => receipt.accepted;
}

/// Limenia cannot be reached right now. The signals are kept and go out with
/// the next [LimeniaReporter.sendPendingSignals].
final class SignalsQueued extends SignalsResult {
  const SignalsQueued(super.idempotencyKey, this.error);

  /// The last error: a network error, a [LimeniaException] that may succeed
  /// later, or a 401 (log in again, then call
  /// [LimeniaReporter.sendPendingSignals]).
  final Exception error;
}

/// Limenia or the client rejected the signals. They are not kept: sending them
/// again unchanged would fail again. Limenia checks the request as a whole, so
/// none of its signals was stored.
///
/// [code] tells why, e.g. `signal_type_unknown` (400, a type does not exist or
/// is inactive; [fieldErrors] names it, `/signals/{i}/type`),
/// `validation_failed` (400, see [fieldErrors]), `subscription_required`
/// (402, the subscription has expired), `feature_not_in_plan` (403, the plan
/// does not include signals) or `idempotency_key_reused` (409, the key was
/// used for other signals). A 403 `tenant_not_active` is not final: like a
/// 5xx it ends in [SignalsQueued]. An answer of the transport that cannot be
/// read (a [FormatException]) ends here as well.
final class SignalsFailed extends SignalsResult {
  const SignalsFailed(super.idempotencyKey, this.error);

  /// A [SignalsValidationException], a [LimeniaException] or a
  /// [FormatException].
  final Exception error;

  /// The code of a [LimeniaException], null otherwise.
  String? get code => switch (error) {
        final LimeniaException e => e.code,
        _ => null,
      };

  /// The invalid fields, from the check in the client or from Limenia. The
  /// paths name the signal by its position in the request, e.g.
  /// `/signals/2/type`.
  List<FieldError> get fieldErrors => switch (error) {
        final SignalsValidationException e => e.errors,
        final LimeniaException e => e.fieldErrors,
        _ => const [],
      };
}

/// The signals waited longer than [RetryPolicy.maxPendingAge] and were
/// dropped.
final class SignalsExpired extends SignalsResult {
  const SignalsExpired(super.idempotencyKey, this.createdAt);

  final DateTime createdAt;
}

/// Sends reports, complaints, review requests and signals reliably: checks
/// them against the limits of Limenia, keeps them in a [PendingReportStore],
/// [PendingAppealStore], [PendingReviewStore] or [PendingSignalsStore] until
/// they went through, tries again with the same idempotency key and respects
/// `Retry-After`.
final class LimeniaReporter {
  LimeniaReporter({
    required LimeniaTransport transport,
    PendingReportStore? store,
    PendingAppealStore? appealStore,
    PendingReviewStore? reviewStore,
    PendingSignalsStore? signalsStore,
    this.retryPolicy = const RetryPolicy(),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  })  : _transport = transport,
        _store = store ?? InMemoryPendingReportStore(),
        _appealStore = appealStore ?? InMemoryPendingAppealStore(),
        _reviewStore = reviewStore ?? InMemoryPendingReviewStore(),
        _signalsStore = signalsStore ?? InMemoryPendingSignalsStore(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final LimeniaTransport _transport;
  final PendingReportStore _store;
  final PendingAppealStore _appealStore;
  final PendingReviewStore _reviewStore;
  final PendingSignalsStore _signalsStore;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final RetryPolicy retryPolicy;

  /// Keys being sent right now, so that [report] and [sendPending] never send
  /// the same report twice at the same time.
  final _inFlight = <String>{};

  /// The same for [appeal] and [sendPendingAppeals].
  final _appealsInFlight = <String>{};

  /// The same for [submitForReview] and [sendPendingReviews].
  final _reviewsInFlight = <String>{};

  /// The same for [sendSignals] and [sendPendingSignals].
  final _signalsInFlight = <String>{};

  /// Sends [request]. Never throws for errors of the transport, see the
  /// subclasses of [ReportResult].
  ///
  /// Pass [idempotencyKey] if the report already has an ID in the app (e.g.
  /// `report-<id>`), otherwise a new key is created.
  Future<ReportResult> report(ReportRequest request, {String? idempotencyKey}) async {
    final key = idempotencyKey ?? newIdempotencyKey(_now());
    final errors = validateReport(request, idempotencyKey: key);
    if (errors.isNotEmpty) return ReportFailed(key, ReportValidationException(errors));
    if (!_inFlight.add(key)) {
      throw StateError('The report with this idempotency key is already being sent.');
    }
    try {
      final pending = PendingReport(idempotencyKey: key, request: request, createdAt: _now());
      await _store.put(pending);
      return await _send(pending, retryPolicy.maxAttempts);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Sends the queued reports, oldest first, one attempt each. Call it when
  /// the app starts, comes back to the foreground or is online again.
  ///
  /// Stops at the first report that is queued again, because the others
  /// would most likely fail in the same way.
  Future<List<ReportResult>> sendPending() async {
    final results = <ReportResult>[];
    for (final pending in await _store.load()) {
      if (!_inFlight.add(pending.idempotencyKey)) continue;
      try {
        if (_now().difference(pending.createdAt) > retryPolicy.maxPendingAge) {
          await _store.remove(pending.idempotencyKey);
          results.add(ReportExpired(pending.idempotencyKey, pending.createdAt));
          continue;
        }
        final result = await _send(pending, 1);
        results.add(result);
        if (result is ReportQueued) break;
      } finally {
        _inFlight.remove(pending.idempotencyKey);
      }
    }
    return results;
  }

  /// The reports that still have to be sent.
  Future<List<PendingReport>> pending() => _store.load();

  /// Sends the complaint [request] against a decision (Art. 20 DSA), with the
  /// same queue and retries as [report]. Never throws for errors of the
  /// transport, see the subclasses of [AppealResult].
  ///
  /// Pass [idempotencyKey] if the complaint already has an ID in the app
  /// (e.g. `appeal-<id>`), otherwise a new key is created.
  Future<AppealResult> appeal(AppealRequest request, {String? idempotencyKey}) async {
    final key = idempotencyKey ?? newIdempotencyKey(_now());
    final errors = validateAppeal(request, idempotencyKey: key);
    if (errors.isNotEmpty) return AppealFailed(key, AppealValidationException(errors));
    if (!_appealsInFlight.add(key)) {
      throw StateError('The complaint with this idempotency key is already being sent.');
    }
    try {
      final pending = PendingAppeal(idempotencyKey: key, request: request, createdAt: _now());
      await _appealStore.put(pending);
      return await _sendAppeal(pending, retryPolicy.maxAttempts);
    } finally {
      _appealsInFlight.remove(key);
    }
  }

  /// Sends the queued complaints like [sendPending].
  Future<List<AppealResult>> sendPendingAppeals() async {
    final results = <AppealResult>[];
    for (final pending in await _appealStore.load()) {
      if (!_appealsInFlight.add(pending.idempotencyKey)) continue;
      try {
        if (_now().difference(pending.createdAt) > retryPolicy.maxPendingAge) {
          await _appealStore.remove(pending.idempotencyKey);
          results.add(AppealExpired(pending.idempotencyKey, pending.createdAt));
          continue;
        }
        final result = await _sendAppeal(pending, 1);
        results.add(result);
        if (result is AppealQueued) break;
      } finally {
        _appealsInFlight.remove(pending.idempotencyKey);
      }
    }
    return results;
  }

  /// The complaints that still have to be sent.
  Future<List<PendingAppeal>> pendingAppeals() => _appealStore.load();

  /// Submits the content of [request] for review before publication
  /// (pre-moderation), with the same queue and retries as [report].
  /// Never throws for errors of the transport, see the subclasses of
  /// [ReviewResult].
  ///
  /// Pass [idempotencyKey] if the submission already has an ID in the app
  /// (e.g. `review-<upload id>`), otherwise a new key is created.
  Future<ReviewResult> submitForReview(ReviewRequest request, {String? idempotencyKey}) async {
    final key = idempotencyKey ?? newIdempotencyKey(_now());
    final errors = validateReview(request, idempotencyKey: key);
    if (errors.isNotEmpty) return ReviewFailed(key, ReviewValidationException(errors));
    if (!_reviewsInFlight.add(key)) {
      throw StateError('The review request with this idempotency key is already being sent.');
    }
    try {
      final pending = PendingReview(idempotencyKey: key, request: request, createdAt: _now());
      await _reviewStore.put(pending);
      return await _sendReview(pending, retryPolicy.maxAttempts);
    } finally {
      _reviewsInFlight.remove(key);
    }
  }

  /// Sends the queued review requests like [sendPending].
  Future<List<ReviewResult>> sendPendingReviews() async {
    final results = <ReviewResult>[];
    for (final pending in await _reviewStore.load()) {
      if (!_reviewsInFlight.add(pending.idempotencyKey)) continue;
      try {
        if (_now().difference(pending.createdAt) > retryPolicy.maxPendingAge) {
          await _reviewStore.remove(pending.idempotencyKey);
          results.add(ReviewExpired(pending.idempotencyKey, pending.createdAt));
          continue;
        }
        final result = await _sendReview(pending, 1);
        results.add(result);
        if (result is ReviewQueued) break;
      } finally {
        _reviewsInFlight.remove(pending.idempotencyKey);
      }
    }
    return results;
  }

  /// The review requests that still have to be sent.
  Future<List<PendingReview>> pendingReviews() => _reviewStore.load();

  /// Sends the signals of [request] (API version 0.18.0), with the same queue
  /// and retries as [report]. Never throws for errors of the transport, see the
  /// subclasses of [SignalsResult].
  ///
  /// Limenia accepts or rejects the request as a whole and counts it once for
  /// the rate limit, so send the signals of a short time together (1 to 100).
  /// Pass [idempotencyKey] if the batch already has an ID in the app (e.g.
  /// `signals-<batch id>`), otherwise a new key is created.
  Future<SignalsResult> sendSignals(SignalsRequest request, {String? idempotencyKey}) async {
    final key = idempotencyKey ?? newIdempotencyKey(_now());
    final errors = validateSignals(request, idempotencyKey: key);
    if (errors.isNotEmpty) return SignalsFailed(key, SignalsValidationException(errors));
    if (!_signalsInFlight.add(key)) {
      throw StateError('The signals with this idempotency key are already being sent.');
    }
    try {
      final pending = PendingSignals(idempotencyKey: key, request: request, createdAt: _now());
      await _signalsStore.put(pending);
      return await _sendSignals(pending, retryPolicy.maxAttempts);
    } finally {
      _signalsInFlight.remove(key);
    }
  }

  /// Sends the queued signals like [sendPending].
  Future<List<SignalsResult>> sendPendingSignals() async {
    final results = <SignalsResult>[];
    for (final pending in await _signalsStore.load()) {
      if (!_signalsInFlight.add(pending.idempotencyKey)) continue;
      try {
        if (_now().difference(pending.createdAt) > retryPolicy.maxPendingAge) {
          await _signalsStore.remove(pending.idempotencyKey);
          results.add(SignalsExpired(pending.idempotencyKey, pending.createdAt));
          continue;
        }
        final result = await _sendSignals(pending, 1);
        results.add(result);
        if (result is SignalsQueued) break;
      } finally {
        _signalsInFlight.remove(pending.idempotencyKey);
      }
    }
    return results;
  }

  /// The signals that still have to be sent.
  Future<List<PendingSignals>> pendingSignals() => _signalsStore.load();

  Future<ReportResult> _send(PendingReport pending, int maxAttempts) async {
    final key = pending.idempotencyKey;
    final attempt = await _attempt(
        () => _transport.createReport(pending.request, idempotencyKey: key), maxAttempts, () => _store.remove(key));
    switch (attempt) {
      case _Done(:final value):
        await _store.remove(key);
        return ReportSent(key, value);
      case _Rejected(:final error):
        await _store.remove(key);
        return ReportFailed(key, error);
      case _Deferred(:final error):
        return ReportQueued(key, error);
    }
  }

  Future<AppealResult> _sendAppeal(PendingAppeal pending, int maxAttempts) async {
    final key = pending.idempotencyKey;
    final attempt = await _attempt(() => _transport.createAppeal(pending.request, idempotencyKey: key), maxAttempts,
        () => _appealStore.remove(key));
    switch (attempt) {
      case _Done(:final value):
        await _appealStore.remove(key);
        return AppealSent(key, value);
      case _Rejected(:final error):
        await _appealStore.remove(key);
        return AppealFailed(key, error);
      case _Deferred(:final error):
        return AppealQueued(key, error);
    }
  }

  Future<ReviewResult> _sendReview(PendingReview pending, int maxAttempts) async {
    final key = pending.idempotencyKey;
    final attempt = await _attempt(() => _transport.createReview(pending.request, idempotencyKey: key), maxAttempts,
        () => _reviewStore.remove(key));
    switch (attempt) {
      case _Done(:final value):
        await _reviewStore.remove(key);
        return ReviewSent(key, value);
      case _Rejected(:final error):
        await _reviewStore.remove(key);
        return ReviewFailed(key, error);
      case _Deferred(:final error):
        return ReviewQueued(key, error);
    }
  }

  Future<SignalsResult> _sendSignals(PendingSignals pending, int maxAttempts) async {
    final key = pending.idempotencyKey;
    final attempt = await _attempt(() => _transport.createSignals(pending.request, idempotencyKey: key), maxAttempts,
        () => _signalsStore.remove(key));
    switch (attempt) {
      case _Done(:final value):
        await _signalsStore.remove(key);
        return SignalsSent(key, value);
      case _Rejected(:final error):
        await _signalsStore.remove(key);
        return SignalsFailed(key, error);
      case _Deferred(:final error):
        return SignalsQueued(key, error);
    }
  }

  /// Calls [send] up to [maxAttempts] times with backoff and `Retry-After`.
  ///
  /// An [Error] of the transport is a bug and never tried again: [forget]
  /// removes the request from its store, so that it does not block the queue,
  /// and the error is thrown on.
  Future<_Attempt<T>> _attempt<T>(Future<T> Function() send, int maxAttempts, Future<void> Function() forget) async {
    for (var attempt = 1;; attempt++) {
      try {
        return _Done(await send());
      } on Exception catch (e) {
        switch (_kind(e)) {
          case _Kind.rejected:
            return _Rejected(e);
          case _Kind.later:
            return _Deferred(e);
          case _Kind.retry:
            if (attempt >= maxAttempts) return _Deferred(e);
            final wait = retryPolicy.delayAfter(attempt, retryAfter: e is LimeniaException ? e.retryAfter : null);
            if (wait > retryPolicy.maxInlineWait) return _Deferred(e);
            await _sleep(wait);
        }
      } on Error {
        try {
          await forget();
        } on Exception {
          // The error of the transport matters more than one of the store.
        }
        rethrow;
      }
    }
  }

  /// How to go on after [e]:
  /// - `reporter_suspended` ([LimeniaException.isReporterSuspended]): rejected
  ///   and dropped, whatever the status. Limenia stored nothing, and the
  ///   reporter's notices stay suspended until
  ///   [LimeniaException.suspendedUntil], so keeping the request would only
  ///   repeat the refusal;
  /// - a [LimeniaException] that may succeed later ([LimeniaException.isRetryable]):
  ///   try again;
  /// - 401: keep the request without trying again now, the login of the app
  ///   (or the API key of its backend) has to be renewed first;
  /// - other [LimeniaException]s, a check of the client, or an answer that
  ///   cannot be read ([FormatException]): rejected, sending it again would
  ///   get the same answer;
  /// - any other [Exception] (network errors, timeouts): try again.
  static _Kind _kind(Exception e) => switch (e) {
        LimeniaException(isReporterSuspended: true) => _Kind.rejected,
        LimeniaException(status: 401) => _Kind.later,
        LimeniaException(isRetryable: true) => _Kind.retry,
        LimeniaException() => _Kind.rejected,
        ReportValidationException() ||
        AppealValidationException() ||
        ReviewValidationException() ||
        SignalsValidationException() =>
          _Kind.rejected,
        FormatException() => _Kind.rejected,
        _ => _Kind.retry,
      };
}

/// See [LimeniaReporter._kind].
enum _Kind { retry, later, rejected }

/// Outcome of [LimeniaReporter._attempt].
sealed class _Attempt<T> {
  const _Attempt();
}

/// Sent, with the answer.
final class _Done<T> extends _Attempt<T> {
  const _Done(this.value);

  final T value;
}

/// Rejected, sending it again unchanged would fail again.
final class _Rejected<T> extends _Attempt<T> {
  const _Rejected(this.error);

  final Exception error;
}

/// Not sent yet, may succeed later.
final class _Deferred<T> extends _Attempt<T> {
  const _Deferred(this.error);

  final Exception error;
}
