// The headless API of package:limenia/limenia.dart, without widgets. Run it
// in this folder with `dart run bin/headless.dart`.
//
// Runs without a backend: the transport below stands in for the backend of
// your app. In a real app it calls your backend, which holds the Limenia API
// key and forwards to the ingest API (see README.md).
// ignore_for_file: avoid_print
import 'package:limenia/limenia.dart';

Future<void> main() async {
  final limenia = Limenia(transport: _DemoBackend());

  final result = await limenia.report(
    const ReportRequest.content(
      reasonCategory: ReasonCategory.harassmentHate,
      reasonText: 'Insults me in every comment',
      goodFaith: true, // the user confirmed the report in good faith (Art. 16(2)(d) DSA)
      author: ReportedUser('u_112', displayName: 'maxi_99'),
      content: ReportedContent(externalContentId: 'comment_5521', contentType: 'comment', text: '…'),
    ),
  );
  switch (result) {
    case ReportSent(:final receipt, :final reporterWarning):
      print('Report ${receipt.reportId} is in case ${receipt.caseId}.');
      // A moderator warned this reporter for unfounded reports (Art. 23 DSA): show the warning.
      if (reporterWarning != null) print('Warning issued at ${reporterWarning.issuedAt}.');
    case ReportQueued():
      print('Offline: the report goes out with sendPendingReports().');
    case ReportFailed(isReporterSuspended: true, :final suspendedUntil):
      print('Reports are suspended for this user until $suspendedUntil.');
    case ReportFailed(:final fieldErrors):
      print('Rejected: $fieldErrors');
    case ReportExpired():
      break;
  }

  final watcher = limenia.watchSubject('u_829');
  watcher.changes.listen((status) => print('Status of u_829: ${status.status.name}'));
  await watcher.refresh();
  watcher.handleDecision(
    ModerationDecision.fromJson({
      'id': 'dec_1',
      'action': 'warn_user',
      'subject': {'externalUserId': 'u_829'},
      'policies': [
        {'code': 'spam', 'title': 'Spam'},
      ],
      'statementOfReasons': {
        'locale': 'en',
        'text': 'Decision about your account\n\nMeasure: warning.',
        'structured': {
          'action': 'warn_user',
          'territorialScope': 'app',
          'facts': 'Repeated advertising in comments.',
          'basedOnNotice': true,
          'noticeSource': 'notice',
          'automatedDetection': false,
          'automatedDecision': false,
          'automation': 'none',
          'grounds': [
            {'basis': 'terms', 'policyCode': 'spam', 'title': 'Spam'},
          ],
          'redress': 'You can object to this decision.',
        },
      },
      'decidedAt': DateTime.now().toUtc().toIso8601String(),
    }),
  );
  await Future<void>.delayed(Duration.zero);
  watcher.dispose();

  // The warning above can be appealed by the affected user.
  final appeal = await limenia.appeal(
    const AppealRequest.subject(
      decisionId: '01K6G5H1TR8W4QZ3M0XCB7NDEC',
      externalUserId: 'u_829',
      text: 'I only posted my own shop once.',
    ),
  );
  switch (appeal) {
    case AppealSent(:final receipt):
      print('Complaint ${receipt.appealId} is ${receipt.status.wireName}.');
    case AppealQueued():
      print('Offline: the complaint goes out with sendPendingAppeals().');
    case AppealFailed(:final code):
      print('Rejected: $code');
    case AppealExpired():
      break;
  }

  // A new profile photo is shown only after Limenia reviewed it.
  final submitted = await limenia.submitForReview(
    const ReviewRequest(
      type: 'profile_photo', // code of a review type of the app
      author: ReportedUser('u_829'),
      externalReviewId: 'upload_881',
      content: ReportedContent(
        externalContentId: 'photo_881',
        contentType: 'image',
        mediaUrls: ['https://storage.example.com/signed/photo_881.jpg'],
      ),
    ),
  );
  switch (submitted) {
    case ReviewSent(:final receipt):
      print('Photo is in review (${receipt.reviewId}), target time ${receipt.dueAt}.');
    case ReviewQueued():
      print('Offline: the photo goes out with sendPendingReviews().');
    case ReviewFailed(:final code, :final fieldErrors):
      print('Rejected: ${code ?? fieldErrors}');
    case ReviewExpired():
      break;
  }

  // Observations of the app about a user go out as signals. Rules of the tenant
  // decide whether they become a case, a higher priority or a flag.
  final signals = await limenia.sendSignals(
    SignalsRequest([
      SignalInput(
        type: 'score_jump', // code of a signal type of the app
        externalUserId: 'u_829', // the backend sets it from the login
        value: 4200,
        occurredAt: DateTime.now(),
        context: const {'level': '7'}, // IDs and technical details only
      ),
    ]),
  );
  switch (signals) {
    case SignalsSent(:final accepted):
      print('$accepted signal(s) stored.');
    case SignalsQueued():
      print('Offline: the signals go out with sendPendingSignals().');
    case SignalsFailed(:final code, :final fieldErrors):
      print('Rejected: ${code ?? fieldErrors}');
    case SignalsExpired():
      break;
  }

  // At registration and login the app checks the device (API 0.20.0). The
  // backend issues a request hash for the user, the app gets a token with it
  // (Flutter plugin limenia_device; in an emulator a test token of the test
  // mode) and the backend forwards the token to Limenia.
  final requestHash = deviceRequestHash('u_829', newDeviceNonce()); // in the backend
  try {
    final device = await limenia.checkDevice(
      DeviceCheckRequest(
        externalUserId: 'u_829', // the backend sets it from the login
        platform: DevicePlatform.test, // android or ios with a real token
        token: 'test:emulator-1', // from LimeniaDevice.requestToken(requestHash: ...)
        requestHash: requestHash,
        event: DeviceCheckEvent.login,
      ),
    );
    if (device.deviceFlag.isFlagged) {
      // A hint, never proof: e.g. ask for more verification instead of blocking.
      print('Device marked as ${device.deviceFlag.wireName} since ${device.flaggedSince ?? 'unknown'}.');
    } else if (!device.evaluated) {
      print('Google or Apple could not be asked: decide without the check.');
    } else {
      print('Device ${device.deviceFlag.wireName}, check ${device.checkId}.');
    }
  } on LimeniaException catch (e) {
    if (!e.isInvalidDeviceToken) rethrow;
    print('Token rejected: request a new one.');
  }

  // Later the backend passes the event review.decided on to the app.
  final event = LimeniaEvent.fromJson({
    'id': 'evt_2',
    'type': 'review.decided',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'app': {'id': '01K6APP', 'slug': 'photoapp'},
    'review': {
      'id': '01K6REVIEW',
      'externalReviewId': 'upload_881',
      'type': 'profile_photo',
      'outcome': 'rejected',
      'decidedAt': DateTime.now().toUtc().toIso8601String(),
      'decisionId': '01K6DECISION',
      'content': {'externalContentId': 'photo_881'},
    },
  });
  if (event case ReviewDecidedEvent(:final review)) {
    switch (review.outcome) {
      case ReviewOutcome.approved:
        print('Publish ${review.externalContentId}.');
      case ReviewOutcome.restricted:
        print('Publish ${review.externalContentId} with a restriction, '
            'the statement of reasons follows in decision ${review.decisionId}.');
      case ReviewOutcome.rejected:
        print('Do not publish ${review.externalContentId}, '
            'show the statement of reasons of decision ${review.decisionId}.');
    }
  }
}

final class _DemoBackend implements LimeniaTransport {
  var _status = 'active';

  @override
  Future<ReportReceipt> createReport(ReportRequest request, {required String idempotencyKey}) async =>
      const ReportReceipt(reportId: '01K6REPORT', caseId: '01K6CASE', caseCreated: true);

  @override
  Future<SubjectStatus> getSubjectStatus(String externalUserId) async {
    final status = SubjectStatus.fromJson({'externalUserId': externalUserId, 'status': _status});
    _status = 'warned'; // the refresh after the event sees the warning
    return status;
  }

  @override
  Future<AppealReceipt> createAppeal(AppealRequest request, {required String idempotencyKey}) async =>
      const AppealReceipt(appealId: '01K6APPEAL', status: AppealStatus.open);

  @override
  Future<AppealStatusInfo> getAppealStatus(String appealId) async => AppealStatusInfo(
        id: appealId,
        decisionId: '01K6G5H1TR8W4QZ3M0XCB7NDEC',
        appellantType: AppellantType.subject,
        status: AppealStatus.open,
        createdAt: DateTime.now().toUtc(),
      );

  @override
  Future<ReviewReceipt> createReview(ReviewRequest request, {required String idempotencyKey}) async => ReviewReceipt(
        reviewId: '01K6REVIEW',
        status: ReviewStatus.pending,
        dueAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

  @override
  Future<ReviewStatusInfo> getReviewStatus(String reviewId) async => ReviewStatusInfo(
        id: reviewId,
        type: 'profile_photo',
        status: ReviewStatus.pending,
        submittedAt: DateTime.now().toUtc(),
      );

  @override
  Future<SignalsReceipt> createSignals(SignalsRequest request, {required String idempotencyKey}) async =>
      SignalsReceipt(accepted: request.signals.length);

  @override
  Future<DeviceCheckResult> checkDevice(DeviceCheckRequest request) async => DeviceCheckResult.fromJson({
        'checkId': '01K6CHECK',
        'platform': request.platform.wireName,
        'status': 'evaluated',
        'deviceFlag': 'banned', // another banned account used this device
        'flaggedSince': '2026-09',
        'deviceAction': 'none',
        'subject': {'externalUserId': request.externalUserId, 'status': 'active'},
        'test': request.platform == DevicePlatform.test,
      });
}
