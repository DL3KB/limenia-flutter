import 'dart:async';
import 'dart:collection';

import 'package:limenia/limenia.dart';

/// A transport that answers with scripted results, one per call.
final class FakeTransport implements LimeniaTransport {
  /// Answers for createReport: a [ReportReceipt] or something to throw.
  final reportAnswers = Queue<Object>();

  /// Answers for getSubjectStatus: a [SubjectStatus], something to throw or
  /// a [Completer] whose future is returned.
  final statusAnswers = Queue<Object>();

  /// Answers for createAppeal: an [AppealReceipt] or something to throw.
  final appealAnswers = Queue<Object>();

  /// Answers for getAppealStatus: an [AppealStatusInfo] or something to throw.
  final appealStatusAnswers = Queue<Object>();

  /// Answers for createReview: a [ReviewReceipt] or something to throw.
  final reviewAnswers = Queue<Object>();

  /// Answers for getReviewStatus: a [ReviewStatusInfo] or something to throw.
  final reviewStatusAnswers = Queue<Object>();

  /// Answers for createSignals: a [SignalsReceipt] or something to throw.
  final signalsAnswers = Queue<Object>();

  final reportCalls = <(ReportRequest, String)>[];
  final statusCalls = <String>[];
  final appealCalls = <(AppealRequest, String)>[];
  final appealStatusCalls = <String>[];
  final reviewCalls = <(ReviewRequest, String)>[];
  final reviewStatusCalls = <String>[];
  final signalsCalls = <(SignalsRequest, String)>[];

  /// Answers for checkDevice: a [DeviceCheckResult] or something to throw.
  final deviceAnswers = Queue<Object>();
  final deviceCalls = <DeviceCheckRequest>[];

  @override
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey}) async {
    reportCalls.add((request, idempotencyKey));
    return switch (reportAnswers.removeFirst()) {
      final ReportReceipt r => r,
      final Object error => throw error,
    };
  }

  @override
  Future<SubjectStatus> getSubjectStatus(String externalUserId) async {
    statusCalls.add(externalUserId);
    return switch (statusAnswers.removeFirst()) {
      final SubjectStatus s => s,
      final Completer<SubjectStatus> c => c.future,
      final Object error => throw error,
    };
  }

  @override
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey}) async {
    appealCalls.add((request, idempotencyKey));
    return switch (appealAnswers.removeFirst()) {
      final AppealReceipt r => r,
      final Object error => throw error,
    };
  }

  @override
  Future<AppealStatusInfo> getAppealStatus(String appealId) async {
    appealStatusCalls.add(appealId);
    return switch (appealStatusAnswers.removeFirst()) {
      final AppealStatusInfo s => s,
      final Object error => throw error,
    };
  }

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) async {
    reviewCalls.add((request, idempotencyKey));
    return switch (reviewAnswers.removeFirst()) {
      final ReviewReceipt r => r,
      final Object error => throw error,
    };
  }

  @override
  Future<ReviewStatusInfo> getReviewStatus(String reviewId) async {
    reviewStatusCalls.add(reviewId);
    return switch (reviewStatusAnswers.removeFirst()) {
      final ReviewStatusInfo s => s,
      final Object error => throw error,
    };
  }

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) async {
    signalsCalls.add((request, idempotencyKey));
    return switch (signalsAnswers.removeFirst()) {
      final SignalsReceipt r => r,
      final Object error => throw error,
    };
  }

  @override
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) async {
    deviceCalls.add(request);
    return switch (deviceAnswers.removeFirst()) {
      final DeviceCheckResult r => r,
      final Object error => throw error,
    };
  }
}

/// A network error as a transport would throw it.
final class NetworkException implements Exception {
  const NetworkException();
}

/// A clock that tests move forward by hand.
final class FakeClock {
  FakeClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// Timers that fire when the test says so.
final class FakeTimers {
  final timers = <FakeTimer>[];

  Timer create(Duration duration, void Function() callback) {
    final timer = FakeTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  List<FakeTimer> get active => [
        for (final t in timers)
          if (t.isActive) t
      ];
}

final class FakeTimer implements Timer {
  FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

ModerationDecision decision({
  required String action,
  required DateTime decidedAt,
  String? userId,
  String? contentId,
  DateTime? suspendUntil,
  String? reviewId,
  String? restoreScope,
}) =>
    ModerationDecision(
      id: 'd_${decidedAt.microsecondsSinceEpoch}',
      actionName: action,
      suspendUntil: suspendUntil,
      externalUserId: userId,
      externalContentId: contentId,
      reviewId: reviewId,
      restoreScopeName: restoreScope,
      policies: const [],
      statementOfReasons: StatementOfReasons(
        locale: 'en',
        text: 'Statement of reasons',
        structured: SorDetails(
          actionName: action,
          endsAt: suspendUntil,
          territorialScope: 'app',
          facts: 'Facts',
          basedOnNotice: true,
          automatedDetection: false,
          automatedDecision: false,
          grounds: const [],
          redress: 'Redress',
        ),
      ),
      decidedAt: decidedAt,
    );
