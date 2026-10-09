import 'appeal.dart';
import 'device.dart';
import 'errors.dart';
import 'report.dart';
import 'review.dart';
import 'signal.dart';
import 'status.dart';

/// The way from the app to Limenia. The app implements it, usually as a call
/// to its own backend, which passes the request on to the Limenia ingest API.
///
/// The API key of Limenia belongs into the backend only, never into the app.
///
/// Error contract, which [LimeniaReporter] relies on for reports,
/// complaints, review requests and signals:
///
/// * For an error answer throw [LimeniaException], e.g. with
///   [LimeniaException.fromResponse]. Its status and code decide what
///   happens: an error that may pass later ([LimeniaException.isRetryable])
///   is tried again, a 401 keeps the request without trying it again now, any
///   other error rejects it, `reporter_suspended` (403, API version 0.16.0)
///   among them: a reporter whose notices are suspended is refused, nothing
///   is kept, and `suspendedUntil` of the problem is available through
///   [LimeniaException.suspendedUntil]. Map errors of your own backend to a
///   [LimeniaException] with a fitting status, too: an expired login of the
///   app to 401, so that the request waits until the user is logged in again
///   and you call `sendPending…`.
/// * For network errors and timeouts throw any other [Exception]. The
///   reporter tries these again and keeps the request until it went through.
/// * If the answer of your backend cannot be read, throw a [FormatException]
///   (the `fromJson` constructors do): the request is rejected, because
///   sending it again would get the same answer.
/// * An [Error] (a bug) is never tried again: the request is dropped from its
///   queue and the error is thrown on.
abstract interface class LimeniaTransport {
  /// Sends [request] to `POST /v1/reports` with the header
  /// `Idempotency-Key: idempotencyKey`. The backend must pass the key on
  /// unchanged, so that repetitions do not create new reports. Without
  /// headers (e.g. Firebase callable functions) send it in the payload.
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey});

  /// Status from `GET /v1/subjects/{externalUserId}/status`. The backend
  /// should only answer for the user that is logged in.
  Future<SubjectStatus> getSubjectStatus(String externalUserId);

  /// Sends [request] to `POST /v1/appeals` with the header
  /// `Idempotency-Key: idempotencyKey`, like [createReport]. The backend sets
  /// the complaining user from its own login.
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey});

  /// Status from `GET /v1/appeals/{appealId}`. The backend should only answer
  /// for complaints of the user that is logged in.
  Future<AppealStatusInfo> getAppealStatus(String appealId);

  /// Sends [request] to `POST /v1/reviews` with the header
  /// `Idempotency-Key: idempotencyKey`, like [createReport]. The backend sets
  /// the author from its own login.
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey});

  /// Status from `GET /v1/reviews/{reviewId}`. The backend should only answer
  /// for review requests of the user that is logged in.
  Future<ReviewStatusInfo> getReviewStatus(String reviewId);

  /// Sends [request] to `POST /v1/signals` (API version 0.18.0) with the header
  /// `Idempotency-Key: idempotencyKey`, like [createReport]. The backend sets
  /// the user of every signal from its own login, see
  /// [SignalsRequest.withExternalUserId], and answers with Limenia's 202 body.
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey});

  /// Sends [request] to `POST /v1/devices/check` (API version 0.20.0), without
  /// an `Idempotency-Key`: the token of the device is single-use. The backend
  /// sets the user from its own login ([DeviceCheckRequest.withExternalUserId]),
  /// checks that the request hash is one it issued to this user
  /// ([deviceRequestHash]) and answers with Limenia's 200 body. Errors as for
  /// the other methods; `Limenia.checkDevice` never retries them, because a
  /// token cannot be sent twice.
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request);
}
