import 'dart:async';

import 'appeal.dart';
import 'device.dart';
import 'errors.dart';
import 'pending.dart';
import 'report.dart';
import 'reporter.dart';
import 'review.dart';
import 'signal.dart';
import 'status.dart';
import 'transport.dart';
import 'validation.dart';
import 'watcher.dart';

/// Entry point for apps: reports, complaints, review requests, signals, device
/// checks and the status of users over one [LimeniaTransport] to the backend
/// of the app.
///
/// ```dart
/// final limenia = Limenia(transport: MyBackendTransport(), pendingReports: MyStore());
/// await limenia.sendPendingReports(); // at app start
/// final result = await limenia.report(ReportRequest.content(...));
/// ```
final class Limenia {
  Limenia({
    required this.transport,
    PendingReportStore? pendingReports,
    PendingAppealStore? pendingAppeals,
    PendingReviewStore? pendingReviews,
    PendingSignalsStore? pendingSignals,
    RetryPolicy retryPolicy = const RetryPolicy(),
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        reporter = LimeniaReporter(
          transport: transport,
          store: pendingReports,
          appealStore: pendingAppeals,
          reviewStore: pendingReviews,
          signalsStore: pendingSignals,
          retryPolicy: retryPolicy,
          now: now,
        );

  final LimeniaTransport transport;
  final LimeniaReporter reporter;
  final DateTime Function() _now;

  /// Sends a report, see [LimeniaReporter.report].
  Future<ReportResult> report(ReportRequest request, {String? idempotencyKey}) =>
      reporter.report(request, idempotencyKey: idempotencyKey);

  /// Sends queued reports, see [LimeniaReporter.sendPending].
  Future<List<ReportResult>> sendPendingReports() => reporter.sendPending();

  /// Sends a complaint against a decision, see [LimeniaReporter.appeal].
  Future<AppealResult> appeal(AppealRequest request, {String? idempotencyKey}) =>
      reporter.appeal(request, idempotencyKey: idempotencyKey);

  /// Sends queued complaints, see [LimeniaReporter.sendPendingAppeals].
  Future<List<AppealResult>> sendPendingAppeals() => reporter.sendPendingAppeals();

  /// Status and result of a complaint, the fallback if `appeal.resolved` was
  /// missed. Throws the errors of the transport.
  Future<AppealStatusInfo> appealStatus(String appealId) => transport.getAppealStatus(appealId);

  /// Submits content for review before publication, see
  /// [LimeniaReporter.submitForReview].
  Future<ReviewResult> submitForReview(ReviewRequest request, {String? idempotencyKey}) =>
      reporter.submitForReview(request, idempotencyKey: idempotencyKey);

  /// Sends queued review requests, see [LimeniaReporter.sendPendingReviews].
  Future<List<ReviewResult>> sendPendingReviews() => reporter.sendPendingReviews();

  /// Status and result of a review request, the fallback if `review.decided`
  /// was missed. Throws the errors of the transport.
  Future<ReviewStatusInfo> reviewStatus(String reviewId) => transport.getReviewStatus(reviewId);

  /// Sends signals about users (API version 0.18.0), see
  /// [LimeniaReporter.sendSignals].
  Future<SignalsResult> sendSignals(SignalsRequest request, {String? idempotencyKey}) =>
      reporter.sendSignals(request, idempotencyKey: idempotencyKey);

  /// Sends queued signals, see [LimeniaReporter.sendPendingSignals].
  Future<List<SignalsResult>> sendPendingSignals() => reporter.sendPendingSignals();

  /// Sends a device check (API version 0.20.0) with a fresh token of the
  /// device, e.g. from the Flutter plugin `limenia_device`, see
  /// [LimeniaTransport.checkDevice].
  ///
  /// Throws a [DeviceCheckValidationException] if [request] breaks a limit
  /// ([validateDeviceCheck]), without calling the transport, and otherwise
  /// the errors of the transport unchanged: a [LimeniaException] (e.g.
  /// [LimeniaException.isInvalidDeviceToken] or
  /// [LimeniaException.isDeviceConnectorNotConfigured]) or a network error.
  /// Unlike reports, nothing is retried or queued: the token is single-use and
  /// Limenia accepts it for 15 minutes only. Request a new token instead.
  ///
  /// The result is a hint for the app, never proof: decide what to do with a
  /// marked device ([DeviceCheckResult.deviceFlag]) and with an
  /// [DeviceCheckStatus.unevaluated] check yourself.
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) {
    final errors = validateDeviceCheck(request);
    if (errors.isNotEmpty) return Future.error(DeviceCheckValidationException(errors));
    return transport.checkDevice(request);
  }

  /// The current status of a user, with an ended suspension as active.
  Future<SubjectStatus> subjectStatus(String externalUserId) async =>
      (await transport.getSubjectStatus(externalUserId)).effectiveAt(_now());

  /// A watcher for the status of a user, usually the one logged in. Call
  /// [SubjectStatusWatcher.refresh] after login and
  /// [SubjectStatusWatcher.dispose] after logout.
  SubjectStatusWatcher watchSubject(
    String externalUserId, {
    bool refreshOnEvent = true,
    void Function(Object error, StackTrace stackTrace)? onRefreshError,
  }) =>
      SubjectStatusWatcher(
        transport: transport,
        externalUserId: externalUserId,
        refreshOnEvent: refreshOnEvent,
        onRefreshError: onRefreshError,
        now: _now,
      );
}
