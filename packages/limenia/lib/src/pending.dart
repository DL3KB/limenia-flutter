import 'appeal.dart';
import 'json.dart';
import 'report.dart';
import 'review.dart';
import 'signal.dart';

/// A report that has not reached Limenia yet.
final class PendingReport {
  const PendingReport({required this.idempotencyKey, required this.request, required this.createdAt});

  final String idempotencyKey;
  final ReportRequest request;

  /// When the user reported it.
  final DateTime createdAt;

  factory PendingReport.fromJson(JsonMap json) => PendingReport(
        idempotencyKey: readRequired<String>(json, 'idempotencyKey'),
        request: ReportRequest.fromJson(readObject(json, 'request')),
        createdAt: readDate(json, 'createdAt'),
      );

  JsonMap toJson() => {
        'idempotencyKey': idempotencyKey,
        'request': request.toJson(),
        'createdAt': formatDate(createdAt),
      };
}

/// Storage for reports that still have to be sent.
///
/// Implement it with persistent storage (e.g. shared_preferences or a local
/// database, one entry per key as JSON from [PendingReport.toJson]) so that
/// reports survive a restart of the app. Reports contain content and IDs of
/// users: delete them as soon as they are sent and do not log them.
abstract interface class PendingReportStore {
  /// All stored reports, oldest first.
  Future<List<PendingReport>> load();

  /// Stores [report], replacing one with the same key.
  Future<void> put(PendingReport report);

  Future<void> remove(String idempotencyKey);
}

/// Keeps pending reports in memory only, so they are lost when the app ends.
final class InMemoryPendingReportStore implements PendingReportStore {
  final _reports = <String, PendingReport>{};

  @override
  Future<List<PendingReport>> load() async =>
      _reports.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> put(PendingReport report) async => _reports[report.idempotencyKey] = report;

  @override
  Future<void> remove(String idempotencyKey) async => _reports.remove(idempotencyKey);
}

/// A complaint that has not reached Limenia yet.
final class PendingAppeal {
  const PendingAppeal({required this.idempotencyKey, required this.request, required this.createdAt});

  final String idempotencyKey;
  final AppealRequest request;

  /// When the user complained.
  final DateTime createdAt;

  factory PendingAppeal.fromJson(JsonMap json) => PendingAppeal(
        idempotencyKey: readRequired<String>(json, 'idempotencyKey'),
        request: AppealRequest.fromJson(readObject(json, 'request')),
        createdAt: readDate(json, 'createdAt'),
      );

  JsonMap toJson() => {
        'idempotencyKey': idempotencyKey,
        'request': request.toJson(),
        'createdAt': formatDate(createdAt),
      };
}

/// Storage for complaints that still have to be sent, like
/// [PendingReportStore]. Complaints contain the text of the user and their
/// ID: delete them as soon as they are sent and do not log them.
abstract interface class PendingAppealStore {
  /// All stored complaints, oldest first.
  Future<List<PendingAppeal>> load();

  /// Stores [appeal], replacing one with the same key.
  Future<void> put(PendingAppeal appeal);

  Future<void> remove(String idempotencyKey);
}

/// Keeps pending complaints in memory only, so they are lost when the app ends.
final class InMemoryPendingAppealStore implements PendingAppealStore {
  final _appeals = <String, PendingAppeal>{};

  @override
  Future<List<PendingAppeal>> load() async =>
      _appeals.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> put(PendingAppeal appeal) async => _appeals[appeal.idempotencyKey] = appeal;

  @override
  Future<void> remove(String idempotencyKey) async => _appeals.remove(idempotencyKey);
}

/// A review request that has not reached Limenia yet.
final class PendingReview {
  const PendingReview({required this.idempotencyKey, required this.request, required this.createdAt});

  final String idempotencyKey;
  final ReviewRequest request;

  /// When the user submitted the content.
  final DateTime createdAt;

  factory PendingReview.fromJson(JsonMap json) => PendingReview(
        idempotencyKey: readRequired<String>(json, 'idempotencyKey'),
        request: ReviewRequest.fromJson(readObject(json, 'request')),
        createdAt: readDate(json, 'createdAt'),
      );

  JsonMap toJson() => {
        'idempotencyKey': idempotencyKey,
        'request': request.toJson(),
        'createdAt': formatDate(createdAt),
      };
}

/// Storage for review requests that still have to be sent, like
/// [PendingReportStore]. They contain the content before publication and the
/// ID of its author: delete them as soon as they are sent and do not log them.
abstract interface class PendingReviewStore {
  /// All stored review requests, oldest first.
  Future<List<PendingReview>> load();

  /// Stores [review], replacing one with the same key.
  Future<void> put(PendingReview review);

  Future<void> remove(String idempotencyKey);
}

/// Keeps pending review requests in memory only, so they are lost when the
/// app ends.
final class InMemoryPendingReviewStore implements PendingReviewStore {
  final _reviews = <String, PendingReview>{};

  @override
  Future<List<PendingReview>> load() async =>
      _reviews.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> put(PendingReview review) async => _reviews[review.idempotencyKey] = review;

  @override
  Future<void> remove(String idempotencyKey) async => _reviews.remove(idempotencyKey);
}

/// Signals that have not reached Limenia yet.
final class PendingSignals {
  const PendingSignals({required this.idempotencyKey, required this.request, required this.createdAt});

  final String idempotencyKey;
  final SignalsRequest request;

  /// When the app collected the signals. Limenia rejects signals whose
  /// `occurredAt` is more than 24 hours old, see [SignalInput.occurredAt].
  final DateTime createdAt;

  factory PendingSignals.fromJson(JsonMap json) => PendingSignals(
        idempotencyKey: readRequired<String>(json, 'idempotencyKey'),
        request: SignalsRequest.fromJson(readObject(json, 'request')),
        createdAt: readDate(json, 'createdAt'),
      );

  JsonMap toJson() => {
        'idempotencyKey': idempotencyKey,
        'request': request.toJson(),
        'createdAt': formatDate(createdAt),
      };
}

/// Storage for signals that still have to be sent, like [PendingReportStore].
/// They contain IDs of users and what they did: delete them as soon as they
/// are sent and do not log them.
abstract interface class PendingSignalsStore {
  /// All stored signal requests, oldest first.
  Future<List<PendingSignals>> load();

  /// Stores [signals], replacing a request with the same key.
  Future<void> put(PendingSignals signals);

  Future<void> remove(String idempotencyKey);
}

/// Keeps pending signals in memory only, so they are lost when the app ends.
final class InMemoryPendingSignalsStore implements PendingSignalsStore {
  final _signals = <String, PendingSignals>{};

  @override
  Future<List<PendingSignals>> load() async =>
      _signals.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> put(PendingSignals signals) async => _signals[signals.idempotencyKey] = signals;

  @override
  Future<void> remove(String idempotencyKey) async => _signals.remove(idempotencyKey);
}
