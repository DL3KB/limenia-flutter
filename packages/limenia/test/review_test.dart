import 'dart:convert';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

JsonMap decode(String json) => jsonDecode(json) as JsonMap;

void main() {
  group('ReviewRequest', () {
    test('toJson gives the body of POST /v1/reviews', () {
      final request = ReviewRequest(
        type: 'profile_photo',
        externalReviewId: 'upload_881',
        author: const ReportedUser('u_112', displayName: 'maxi_99'),
        content: ReportedContent(
          externalContentId: 'photo_881',
          contentType: 'image',
          mediaUrls: const ['https://storage.example.com/signed/photo_881.jpg'],
          createdAt: DateTime.utc(2026, 10, 3, 8, 59),
          context: const {'albumId': 'a_7'},
        ),
      );
      expect(request.toJson(), {
        'type': 'profile_photo',
        'externalReviewId': 'upload_881',
        'subject': {'externalUserId': 'u_112', 'displayName': 'maxi_99'},
        'content': {
          'externalContentId': 'photo_881',
          'contentType': 'image',
          'media': [
            {'url': 'https://storage.example.com/signed/photo_881.jpg'},
          ],
          'createdAt': '2026-10-03T08:59:00.000Z',
          'context': {'albumId': 'a_7'},
        },
      });
    });

    test('leaves out empty optional fields and survives a round trip', () {
      const request = ReviewRequest(
        type: 'listing',
        content: ReportedContent(externalContentId: 'l_1', contentType: 'listing', text: 'Fahrrad, 28 Zoll'),
      );
      expect(request.toJson(), {
        'type': 'listing',
        'content': {'externalContentId': 'l_1', 'contentType': 'listing', 'text': 'Fahrrad, 28 Zoll'},
      });
      final again = ReviewRequest.fromJson(decode(jsonEncode(request.toJson())));
      expect(again.author, isNull);
      expect(again.externalReviewId, isNull);
      expect(again.toJson(), request.toJson());
    });

    test('withAuthor replaces the author only', () {
      const request = ReviewRequest(
        type: 'profile_text',
        author: ReportedUser('evil'),
        externalReviewId: 'r_1',
        content: ReportedContent(externalContentId: 'bio_1', contentType: 'profile_text', text: 'Hallo'),
      );
      final json = request.withAuthor(const ReportedUser('u_2', displayName: 'Anna')).toJson();
      expect(json['subject'], {'externalUserId': 'u_2', 'displayName': 'Anna'});
      expect(json['type'], 'profile_text');
      expect(json['externalReviewId'], 'r_1');
      expect(json['content'], request.content.toJson());
      expect(request.withAuthor(null).toJson().containsKey('subject'), isFalse);
    });

    test('fromJson needs type and content', () {
      expect(() => ReviewRequest.fromJson({'type': 'listing'}), throwsFormatException);
      expect(
        () => ReviewRequest.fromJson({
          'content': {'externalContentId': 'l_1', 'contentType': 'listing'},
        }),
        throwsFormatException,
      );
    });
  });

  test('ReviewReceipt reads CreatedReview', () {
    final receipt =
        ReviewReceipt.fromJson(decode('{"reviewId":"rv1","status":"pending","dueAt":"2026-10-03T10:00:00Z"}'));
    expect(receipt, ReviewReceipt(reviewId: 'rv1', status: ReviewStatus.pending, dueAt: DateTime.utc(2026, 10, 3, 10)));
    expect(ReviewReceipt.fromJson(receipt.toJson()), receipt);
    expect(
      () => ReviewReceipt.fromJson(decode('{"reviewId":"rv1","status":"open","dueAt":"2026-10-03T10:00:00Z"}')),
      throwsFormatException,
    );
  });

  group('ReviewStatusInfo', () {
    test('an open request', () {
      final info = ReviewStatusInfo.fromJson(decode('''
        {"id":"rv1","type":"profile_photo","status":"in_review","submittedAt":"2026-10-03T09:00:00Z"}'''));
      expect(info.status, ReviewStatus.inReview);
      expect(info.outcome, isNull);
      expect(info.decisionId, isNull);
      expect(info.toJson()['status'], 'in_review');
    });

    test('a rejected request survives a round trip', () {
      final info = ReviewStatusInfo.fromJson(decode('''
        {"id":"rv1","externalReviewId":"upload_881","type":"profile_photo","status":"decided",
         "submittedAt":"2026-10-03T09:00:00Z","outcome":"rejected","decidedAt":"2026-10-03T09:12:00.5Z",
         "decisionId":"01K6T2D0000000000000000000"}'''));
      expect(info.outcome, ReviewOutcome.rejected);
      expect(info.decidedAt, DateTime.utc(2026, 10, 3, 9, 12, 0, 500));
      expect(info.decisionId, '01K6T2D0000000000000000000');
      expect(ReviewStatusInfo.fromJson(info.toJson()).toJson(), info.toJson());
    });

    test('an unknown outcome throws a FormatException', () {
      expect(
        () => ReviewStatusInfo.fromJson(decode('''
          {"id":"rv1","type":"t","status":"decided","submittedAt":"2026-10-03T09:00:00Z","outcome":"maybe"}''')),
        throwsFormatException,
      );
    });
  });

  test('ReviewResolution reads WebhookReview', () {
    final approved = ReviewResolution.fromJson(
        decode('{"id":"rv2","type":"listing","outcome":"approved","decidedAt":"2026-10-03T09:13:00Z"}'));
    expect(approved.outcome, ReviewOutcome.approved);
    expect(approved.decisionId, isNull);
    expect(approved.externalContentId, isNull);
    expect(approved.toJson(), {
      'id': 'rv2',
      'type': 'listing',
      'outcome': 'approved',
      'decidedAt': '2026-10-03T09:13:00.000Z',
    });
  });

  test('Limenia.reviewStatus asks the transport', () async {
    final transport = FakeTransport();
    final info = ReviewStatusInfo(
      id: 'rv1',
      type: 'profile_photo',
      status: ReviewStatus.pending,
      submittedAt: DateTime.utc(2026, 10, 3, 9),
    );
    transport.reviewStatusAnswers.add(info);
    expect(await Limenia(transport: transport).reviewStatus('rv1'), same(info));
    expect(transport.reviewStatusCalls, ['rv1']);
  });

  test('Limenia.submitForReview sends through the transport', () async {
    final transport = FakeTransport();
    final receipt = ReviewReceipt(reviewId: 'rv1', status: ReviewStatus.pending, dueAt: DateTime.utc(2026, 10, 3, 10));
    transport.reviewAnswers.add(receipt);
    final result = await Limenia(transport: transport).submitForReview(
      const ReviewRequest(
        type: 'profile_photo',
        author: ReportedUser('u_1'),
        content: ReportedContent(externalContentId: 'photo_1', contentType: 'image'),
      ),
      idempotencyKey: 'review-photo_1',
    );
    expect(result, isA<ReviewSent>().having((r) => r.receipt, 'receipt', receipt));
    expect(transport.reviewCalls.single.$2, 'review-photo_1');
  });
}
