import 'dart:convert';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

const trustedFlaggerId = '01K6T2D0000000000000000000';

void main() {
  group('ReportRequest', () {
    test('toJson gives the body of POST /v1/reports', () {
      final request = ReportRequest.content(
        reasonCategory: ReasonCategory.harassmentHate,
        reasonText: 'Insults me in every comment',
        reporterId: 'u_829',
        author: const ReportedUser('u_112', displayName: 'maxi_99'),
        content: ReportedContent(
          externalContentId: 'comment_5521',
          contentType: 'comment',
          text: '…',
          mediaUrls: const ['https://storage.example.com/signed/abc.jpg'],
          externalUrl: 'https://app.example.com/p/77#comment_5521',
          createdAt: DateTime.utc(2026, 10, 1, 9, 12),
          context: const {'postId': 'p_77'},
        ),
      );

      expect(request.toJson(), {
        'source': 'user',
        'reasonCategory': 'harassment_hate',
        'reasonText': 'Insults me in every comment',
        'reporter': {'externalUserId': 'u_829'},
        'subject': {'externalUserId': 'u_112', 'displayName': 'maxi_99'},
        'content': {
          'externalContentId': 'comment_5521',
          'contentType': 'comment',
          'text': '…',
          'media': [
            {'url': 'https://storage.example.com/signed/abc.jpg'},
          ],
          'externalUrl': 'https://app.example.com/p/77#comment_5521',
          'createdAt': '2026-10-01T09:12:00.000Z',
          'context': {'postId': 'p_77'},
        },
      });
    });

    test('leaves out empty optional fields', () {
      const request = ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u_1'));
      expect(request.toJson(), {
        'source': 'user',
        'reasonCategory': 'spam',
        'subject': {'externalUserId': 'u_1'},
      });
    });

    test('sends local times as UTC', () {
      final local = DateTime(2026, 10, 1, 11, 12);
      final json = ReportedContent(externalContentId: 'c', contentType: 'comment', createdAt: local).toJson();
      expect(DateTime.parse(json['createdAt']! as String).isAtSameMomentAs(local), isTrue);
      expect(json['createdAt'], endsWith('Z'));
    });

    test('survives a JSON round trip', () {
      final request = ReportRequest.content(
        source: ReportSource.system,
        reasonCategory: 'spam',
        author: const ReportedUser('u_1'),
        content: ReportedContent(
          externalContentId: 'c_1',
          contentType: 'comment',
          mediaUrls: const ['https://a.example.com/1.png', 'https://a.example.com/2.png'],
          createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7),
          context: const {
            'n': 1,
            'list': [1, 'a'],
          },
        ),
      );
      final decoded = jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>;
      expect(ReportRequest.fromJson(decoded).toJson(), request.toJson());
    });

    test('withReporter replaces the reporter only', () {
      const request = ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u_1'), reporterId: 'evil');
      final json = request.withReporter('u_2').toJson();
      expect(json['reporter'], {'externalUserId': 'u_2'});
      expect(json['subject'], request.toJson()['subject']);
      expect(request.withReporter(null).toJson().containsKey('reporter'), isFalse);
    });

    test('externalReportId goes out and stays with another reporter', () {
      const request = ReportRequest.user(
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        reporterId: 'evil',
        externalReportId: 'rep_77',
      );
      expect(request.toJson()['externalReportId'], 'rep_77');
      expect(request.withReporter('u_2').externalReportId, 'rep_77');
      expect(ReportRequest.fromJson(request.toJson()).externalReportId, 'rep_77');
    });

    test('trustedFlaggerId goes out, survives a round trip and is left out without it', () {
      const request = ReportRequest.user(
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        reporterId: 'u_2',
        trustedFlaggerId: trustedFlaggerId,
      );
      expect(request.toJson()['trustedFlaggerId'], trustedFlaggerId);
      expect(ReportRequest.fromJson(request.toJson()).trustedFlaggerId, trustedFlaggerId);
      expect(ReportRequest.fromJson(jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>).toJson(),
          request.toJson());

      const content = ReportRequest.content(
        reasonCategory: 'spam',
        author: ReportedUser('u_1'),
        content: ReportedContent(externalContentId: 'c', contentType: 'comment'),
        trustedFlaggerId: trustedFlaggerId,
      );
      expect(content.trustedFlaggerId, trustedFlaggerId);
      expect(content.toJson()['trustedFlaggerId'], trustedFlaggerId);

      const without = ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u_1'));
      expect(without.trustedFlaggerId, isNull);
      expect(without.toJson().containsKey('trustedFlaggerId'), isFalse);
    });

    test('withReporter keeps the trusted flagger, withTrustedFlagger replaces or removes it', () {
      const request = ReportRequest.user(
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        reporterId: 'evil',
        externalReportId: 'rep_77',
        trustedFlaggerId: trustedFlaggerId,
      );
      expect(request.withReporter('u_2').trustedFlaggerId, trustedFlaggerId);

      // A backend sets both from its own records: a device cannot claim to be a trusted flagger.
      final ordinary = request.withReporter('u_2').withTrustedFlagger(null);
      expect(ordinary.trustedFlaggerId, isNull);
      expect(ordinary.toJson().containsKey('trustedFlaggerId'), isFalse);
      expect(ordinary.reporterId, 'u_2');
      expect(ordinary.externalReportId, 'rep_77');
      expect(ordinary.toJson()['subject'], request.toJson()['subject']);

      const other = '01K6T2D0000000000000000001';
      expect(request.withTrustedFlagger(other).trustedFlaggerId, other);
      expect(request.withTrustedFlagger(other).reporterId, 'evil');
    });

    test('a queued report keeps the trusted flagger', () {
      const request = ReportRequest.user(
        reasonCategory: 'spam',
        subject: ReportedUser('u_1'),
        trustedFlaggerId: trustedFlaggerId,
      );
      final pending = PendingReport(idempotencyKey: 'k', request: request, createdAt: DateTime.utc(2026, 10, 5));
      final again = PendingReport.fromJson(jsonDecode(jsonEncode(pending.toJson())) as Map<String, Object?>);
      expect(again.request.trustedFlaggerId, trustedFlaggerId);
    });

    group('goodFaith (API 0.22.0)', () {
      test('goes out as given, true and false, and is left out when null', () {
        for (final value in [true, false]) {
          final request = ReportRequest.user(
            reasonCategory: 'spam',
            subject: const ReportedUser('u_1'),
            reporterId: 'u_2',
            goodFaith: value,
          );
          expect(request.goodFaith, value);
          expect(request.toJson()['goodFaith'], value);
          expect(request.toJson().containsKey('goodFaith'), isTrue);
        }
        const without = ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u_1'));
        expect(without.goodFaith, isNull);
        expect(without.toJson().containsKey('goodFaith'), isFalse);
      });

      test('every constructor takes it', () {
        const content = ReportRequest.content(
          reasonCategory: 'spam',
          author: ReportedUser('u_1'),
          content: ReportedContent(externalContentId: 'c', contentType: 'comment'),
          goodFaith: true,
        );
        expect(content.toJson()['goodFaith'], isTrue);
        const plain = ReportRequest(source: ReportSource.user, reasonCategory: 'spam', goodFaith: false);
        expect(plain.toJson()['goodFaith'], isFalse);
      });

      test('the body has the field next to reasonText', () {
        const request = ReportRequest.user(
          reasonCategory: 'spam',
          reasonText: 'Ads in every comment',
          goodFaith: true,
          subject: ReportedUser('u_1'),
          reporterId: 'u_2',
        );
        expect(request.toJson(), {
          'source': 'user',
          'reasonCategory': 'spam',
          'reasonText': 'Ads in every comment',
          'goodFaith': true,
          'reporter': {'externalUserId': 'u_2'},
          'subject': {'externalUserId': 'u_1'},
        });
      });

      test('fromJson reads it and survives a round trip', () {
        for (final value in [true, false]) {
          final request =
              ReportRequest.user(reasonCategory: 'spam', subject: const ReportedUser('u_1'), goodFaith: value);
          final decoded = jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>;
          final again = ReportRequest.fromJson(decoded);
          expect(again.goodFaith, value);
          expect(again.toJson(), request.toJson());
        }
        expect(ReportRequest.fromJson({'source': 'user', 'reasonCategory': 'spam'}).goodFaith, isNull);
        expect(
            ReportRequest.fromJson({'source': 'user', 'reasonCategory': 'spam', 'goodFaith': null}).goodFaith, isNull);
        expect(
          () => ReportRequest.fromJson({'source': 'user', 'reasonCategory': 'spam', 'goodFaith': 'true'}),
          throwsFormatException,
        );
        expect(
          () => ReportRequest.fromJson({'source': 'user', 'reasonCategory': 'spam', 'goodFaith': 1}),
          throwsFormatException,
        );
      });

      test('withReporter and withTrustedFlagger keep it', () {
        for (final value in [true, false, null]) {
          final request = ReportRequest.user(
            reasonCategory: 'spam',
            subject: const ReportedUser('u_1'),
            reporterId: 'evil',
            goodFaith: value,
          );
          expect(request.withReporter('u_2').goodFaith, value);
          expect(request.withReporter(null).goodFaith, value);
          expect(request.withTrustedFlagger(trustedFlaggerId).goodFaith, value);
          expect(request.withReporter('u_2').withTrustedFlagger(null).goodFaith, value);
          expect(request.withReporter('u_2').toJson().containsKey('goodFaith'), value != null);
        }
      });

      test('a queued report keeps it', () {
        const request = ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u_1'), goodFaith: true);
        final pending = PendingReport(idempotencyKey: 'k', request: request, createdAt: DateTime.utc(2026, 10, 7));
        final again = PendingReport.fromJson(jsonDecode(jsonEncode(pending.toJson())) as Map<String, Object?>);
        expect(again.request.goodFaith, isTrue);
      });
    });

    test('fromJson rejects a wrong type with a FormatException', () {
      expect(() => ReportRequest.fromJson({'source': 'user', 'reasonCategory': 1}), throwsFormatException);
      expect(() => ReportRequest.fromJson({'source': 'bot', 'reasonCategory': 'spam'}), throwsFormatException);
      expect(
        () => ReportRequest.fromJson({'source': 'user', 'reasonCategory': 'spam', 'trustedFlaggerId': 5}),
        throwsFormatException,
      );
    });
  });

  test('ReportReceipt reads CreatedReport', () {
    final receipt = ReportReceipt.fromJson(
      jsonDecode('{"reportId":"r1","caseId":"c1","caseCreated":false}') as Map<String, Object?>,
    );
    expect(receipt, const ReportReceipt(reportId: 'r1', caseId: 'c1', caseCreated: false));
    expect(ReportReceipt.fromJson(receipt.toJson()), receipt);
    expect(receipt.reporterWarning, isNull);
    expect(receipt.toJson().containsKey('reporterWarning'), isFalse);
  });

  group('reporterWarning (API 0.16.0)', () {
    test('ReportReceipt reads the warning of a reporter', () {
      final receipt = ReportReceipt.fromJson(
        jsonDecode('{"reportId":"r1","caseId":"c1","caseCreated":true,'
            '"reporterWarning":{"issuedAt":"2026-10-04T08:30:00Z"}}') as Map<String, Object?>,
      );
      expect(receipt.reporterWarning, ReporterWarning(issuedAt: DateTime.utc(2026, 10, 4, 8, 30)));
      expect(receipt.reporterWarning!.issuedAt.isUtc, isTrue);
      expect(receipt.reportId, 'r1');
      expect(receipt.toJson()['reporterWarning'], {'issuedAt': '2026-10-04T08:30:00.000Z'});
      expect(ReportReceipt.fromJson(receipt.toJson()), receipt);
    });

    test('the warning counts for equality', () {
      final warning = ReporterWarning(issuedAt: DateTime.utc(2026, 10, 4));
      final warned = ReportReceipt(reportId: 'r', caseId: 'c', caseCreated: true, reporterWarning: warning);
      expect(warned, ReportReceipt(reportId: 'r', caseId: 'c', caseCreated: true, reporterWarning: warning));
      expect(warned.hashCode,
          ReportReceipt(reportId: 'r', caseId: 'c', caseCreated: true, reporterWarning: warning).hashCode);
      expect(warned, isNot(const ReportReceipt(reportId: 'r', caseId: 'c', caseCreated: true)));
      expect(warned.toString(), contains('reporterWarning: ReporterWarning(issuedAt: 2026-10-04'));
    });

    test('a broken warning is a FormatException', () {
      expect(
        () => ReportReceipt.fromJson(
            {'reportId': 'r', 'caseId': 'c', 'caseCreated': true, 'reporterWarning': <String, Object?>{}}),
        throwsFormatException,
      );
      expect(
        () => ReportReceipt.fromJson({
          'reportId': 'r',
          'caseId': 'c',
          'caseCreated': true,
          'reporterWarning': {'issuedAt': 'yesterday'},
        }),
        throwsFormatException,
      );
      expect(
        () =>
            ReportReceipt.fromJson({'reportId': 'r', 'caseId': 'c', 'caseCreated': true, 'reporterWarning': 'warned'}),
        throwsFormatException,
      );
    });
  });

  test('ReasonCategory defaults are valid codes', () {
    expect(ReasonCategory.defaults, hasLength(10));
    expect(ReasonCategory.defaults.every(ReasonCategory.isValid), isTrue);
    expect(ReasonCategory.childSafetyCategories, contains(ReasonCategory.childSafety));
    expect(ReasonCategory.isValid('a'), isFalse);
    expect(ReasonCategory.isValid('Spam'), isFalse);
  });
}
