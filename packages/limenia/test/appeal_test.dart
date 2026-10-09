import 'dart:convert';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

const decisionId = '01K6G5H1TR8W4QZ3M0XCB7NDEC';

JsonMap decode(String json) => jsonDecode(json) as JsonMap;

void main() {
  group('AppealRequest', () {
    test('toJson gives the body of POST /v1/appeals', () {
      const request = AppealRequest.reporter(
        decisionId: decisionId,
        externalUserId: 'u_829',
        text: 'The comment still insults me.',
        externalAppealId: 'appeal_17',
      );
      expect(request.toJson(), {
        'decisionId': decisionId,
        'appellant': {'type': 'reporter', 'externalUserId': 'u_829'},
        'text': 'The comment still insults me.',
        'externalAppealId': 'appeal_17',
      });
    });

    test('subject leaves out an empty externalAppealId and survives a round trip', () {
      const request = AppealRequest.subject(decisionId: decisionId, externalUserId: 'u_112', text: 'Satire.');
      expect(request.toJson(), {
        'decisionId': decisionId,
        'appellant': {'type': 'subject', 'externalUserId': 'u_112'},
        'text': 'Satire.',
      });
      final again = AppealRequest.fromJson(decode(jsonEncode(request.toJson())));
      expect(again.appellantType, AppellantType.subject);
      expect(again.toJson(), request.toJson());
    });

    test('withAppellantUser replaces the user only', () {
      const request = AppealRequest.reporter(decisionId: decisionId, externalUserId: 'evil', text: 'x');
      final json = request.withAppellantUser('u_2').toJson();
      expect(json['appellant'], {'type': 'reporter', 'externalUserId': 'u_2'});
      expect(json['text'], 'x');
    });

    test('fromJson rejects an unknown appellant type', () {
      expect(
        () => AppealRequest.fromJson({
          'decisionId': decisionId,
          'appellant': {'type': 'lawyer', 'externalUserId': 'u'},
          'text': 'x',
        }),
        throwsFormatException,
      );
    });
  });

  test('AppealReceipt reads CreatedAppeal', () {
    final receipt = AppealReceipt.fromJson(decode('{"appealId":"a1","status":"open"}'));
    expect(receipt, const AppealReceipt(appealId: 'a1', status: AppealStatus.open));
    expect(AppealReceipt.fromJson(receipt.toJson()), receipt);
    expect(() => AppealReceipt.fromJson(decode('{"appealId":"a1","status":"closed"}')), throwsFormatException);
  });

  group('AppealStatusInfo', () {
    test('an open complaint', () {
      final info = AppealStatusInfo.fromJson(decode('''
        {"id":"a1","decisionId":"$decisionId","appellantType":"subject","status":"in_review",
         "createdAt":"2026-10-02T10:00:00Z"}'''));
      expect(info.status, AppealStatus.inReview);
      expect(info.outcome, isNull);
      expect(info.statementText, isNull);
      expect(info.toJson()['status'], 'in_review');
    });

    test('a resolved complaint survives a round trip', () {
      final json = decode('''
        {"id":"a1","externalAppealId":"appeal_17","decisionId":"$decisionId","appellantType":"reporter",
         "status":"resolved","createdAt":"2026-10-02T10:00:00Z","outcome":"changed",
         "statementText":"Response to your complaint","resolvedAt":"2026-10-03T08:30:00Z",
         "newDecisionId":"01K6G5H1TR8W4QZ3M0XCB7NNEW"}''');
      final info = AppealStatusInfo.fromJson(json);
      expect(info.appellantType, AppellantType.reporter);
      expect(info.outcome, AppealOutcome.changed);
      expect(info.resolvedAt, DateTime.utc(2026, 10, 3, 8, 30));
      expect(info.newDecisionId, '01K6G5H1TR8W4QZ3M0XCB7NNEW');
      expect(AppealStatusInfo.fromJson(info.toJson()).toJson(), info.toJson());
    });
  });

  test('Limenia.appealStatus asks the transport', () async {
    final transport = FakeTransport();
    final info = AppealStatusInfo(
      id: 'a1',
      decisionId: decisionId,
      appellantType: AppellantType.subject,
      status: AppealStatus.open,
      createdAt: DateTime.utc(2026, 10, 2),
    );
    transport.appealStatusAnswers.add(info);
    expect(await Limenia(transport: transport).appealStatus('a1'), same(info));
    expect(transport.appealStatusCalls, ['a1']);
  });
}
