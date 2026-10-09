import 'dart:convert';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

// Examples from the integration guide of Limenia (https://limenia.eu/docs/integration.md, section 4.5).
const decisionCreated = r'''
{
  "id": "evt_01K6G5H1TR8W4QZ3M0XCB7NDEA",
  "type": "decision.created",
  "createdAt": "2026-10-01T10:00:00.123456Z",
  "app": { "id": "01K6G5H1TR8W4QZ3M0XCB7NAPP", "slug": "photoapp" },
  "decision": {
    "id": "01K6G5H1TR8W4QZ3M0XCB7NDEC",
    "action": "suspend_user",
    "suspendUntil": "2026-10-08T08:00:00Z",
    "content": { "externalContentId": "comment_5521" },
    "subject": { "externalUserId": "u_112" },
    "policies": [{ "code": "harassment_hate", "title": "Harassment and hate speech" }],
    "statementOfReasons": {
      "locale": "en",
      "text": "Decision about your account\n\nMeasure: temporary suspension of the account until 2026-10-08 08:00 UTC.",
      "structured": {
        "action": "suspend_user",
        "endsAt": "2026-10-08T08:00:00Z",
        "territorialScope": "app",
        "facts": "Repeated insults in comments.",
        "basedOnNotice": true,
        "automatedDetection": false,
        "automatedDecision": false,
        "grounds": [{ "basis": "terms", "policyCode": "harassment_hate", "title": "Harassment and hate speech" }],
        "redress": "…"
      }
    },
    "decidedAt": "2026-10-01T10:00:00.123456Z"
  }
}
''';

const statusChanged = '''
{
  "id": "evt_01K6R2",
  "type": "subject.status_changed",
  "createdAt": "2026-10-08T08:15:02.481233Z",
  "app": { "id": "01K6G5H1TR8W4QZ3M0XCB7NAPP", "slug": "photoapp" },
  "subject": { "externalUserId": "u_112", "status": "active" }
}
''';

const appealResolved = r'''
{
  "id": "evt_01K6S1",
  "type": "appeal.resolved",
  "createdAt": "2026-10-05T09:00:00.5Z",
  "app": { "id": "01K6G5H1TR8W4QZ3M0XCB7NAPP", "slug": "photoapp" },
  "appeal": {
    "id": "01K6S1APPEAL0000000000000A",
    "externalAppealId": "appeal_17",
    "decisionId": "01K6G5H1TR8W4QZ3M0XCB7NDEC",
    "appellantType": "subject",
    "outcome": "changed",
    "statementText": "Response to your complaint\n\nWe have changed the decision.",
    "resolvedAt": "2026-10-05T09:00:00Z",
    "newDecisionId": "01K6S1DECISION000000000NEW"
  }
}
''';

const reportsResolved = '''
{
  "id": "evt_01K6S2",
  "type": "reports.resolved",
  "createdAt": "2026-10-01T10:00:01Z",
  "app": { "id": "01K6G5H1TR8W4QZ3M0XCB7NAPP", "slug": "photoapp" },
  "reports": {
    "decisionId": "01K6G5H1TR8W4QZ3M0XCB7NDEC",
    "action": "dismiss",
    "policies": [],
    "decidedAt": "2026-10-01T10:00:00Z",
    "appealDeadline": "2027-04-01T10:00:00Z",
    "items": [
      { "reportId": "01K6REPORT0000000000000001", "externalReportId": "rep_77" },
      { "reportId": "01K6REPORT0000000000000002" }
    ]
  }
}
''';

const reviewDecided = '''
{
  "id": "evt_01K6T3",
  "type": "review.decided",
  "createdAt": "2026-10-03T09:12:00.123456Z",
  "app": { "id": "01K6G5H1TR8W4QZ3M0XCB7NAPP", "slug": "photoapp" },
  "review": {
    "id": "01K6T2R0000000000000000000",
    "externalReviewId": "upload_881",
    "type": "profile_photo",
    "outcome": "rejected",
    "decidedAt": "2026-10-03T09:12:00.098765Z",
    "decisionId": "01K6T2D0000000000000000000",
    "content": { "externalContentId": "photo_881" }
  }
}
''';

LimeniaEvent parse(String json) => LimeniaEvent.fromJson(jsonDecode(json) as Map<String, Object?>);

void main() {
  test('decision.created', () {
    final event = parse(decisionCreated);
    expect(event, isA<DecisionCreatedEvent>());
    expect(event.type, 'decision.created');
    expect(event.id, 'evt_01K6G5H1TR8W4QZ3M0XCB7NDEA');
    expect(event.appSlug, 'photoapp');
    expect(event.createdAt, DateTime.utc(2026, 10, 1, 10, 0, 0, 123, 456));

    final d = (event as DecisionCreatedEvent).decision;
    expect(d.action, ModerationAction.suspendUser);
    expect(d.suspendUntil, DateTime.utc(2026, 10, 8, 8));
    expect(d.externalContentId, 'comment_5521');
    expect(d.externalUserId, 'u_112');
    expect(d.policies.single.code, 'harassment_hate');
    expect(d.statementOfReasons.locale, 'en');
    expect(d.statementOfReasons.text, startsWith('Decision about your account\n\n'));
    final s = d.statementOfReasons.structured;
    expect(s.action, ModerationAction.suspendUser);
    expect(s.endsAt, DateTime.utc(2026, 10, 8, 8));
    expect(s.basedOnNotice, isTrue);
    expect(s.grounds.single.basis, LegalBasis.terms);
    expect(s.grounds.single.lawReference, isNull);
  });

  group('noticeSource (API 0.16.0)', () {
    SorDetails structured([void Function(Map<String, Object?> structured)? change]) {
      final json = jsonDecode(decisionCreated) as Map<String, Object?>;
      final decision = json['decision']! as Map<String, Object?>;
      final sor = (decision['statementOfReasons']! as Map<String, Object?>)['structured']! as Map<String, Object?>;
      change?.call(sor);
      return (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision.statementOfReasons.structured;
    }

    test('reads every value', () {
      for (final (wire, source) in [
        ('notice', NoticeSource.notice),
        ('trusted_flagger', NoticeSource.trustedFlagger),
        ('own_initiative', NoticeSource.ownInitiative),
      ]) {
        final s = structured((sor) => sor['noticeSource'] = wire);
        expect(s.noticeSource, source, reason: wire);
        expect(s.noticeSourceName, wire);
        expect(s.toJson()['noticeSource'], wire);
      }
    });

    test('comes from the field, not from basedOnNotice', () {
      final s = structured((sor) => sor['noticeSource'] = 'trusted_flagger');
      expect(s.basedOnNotice, isTrue);
      expect(s.noticeSource, NoticeSource.trustedFlagger);
      final own = structured((sor) {
        sor['basedOnNotice'] = true;
        sor['noticeSource'] = 'own_initiative';
      });
      expect(own.noticeSource, NoticeSource.ownInitiative);
    });

    test('is derived from basedOnNotice in a decision from before API 0.16.0', () {
      final notice = structured();
      expect(notice.noticeSourceName, isNull);
      expect(notice.noticeSource, NoticeSource.notice);
      final own = structured((sor) => sor['basedOnNotice'] = false);
      expect(own.noticeSourceName, isNull);
      expect(own.noticeSource, NoticeSource.ownInitiative);
      expect(NoticeSource.fromBasedOnNotice(basedOnNotice: true), NoticeSource.notice);
      expect(NoticeSource.fromBasedOnNotice(basedOnNotice: false), NoticeSource.ownInitiative);
    });

    test('falls back to basedOnNotice for a value this version does not know', () {
      final s = structured((sor) => sor['noticeSource'] = 'court_order');
      expect(s.noticeSource, NoticeSource.notice);
      expect(s.noticeSourceName, 'court_order');
      expect(s.toJson()['noticeSource'], 'court_order');
      final own = structured((sor) {
        sor['basedOnNotice'] = false;
        sor['noticeSource'] = 'court_order';
      });
      expect(own.noticeSource, NoticeSource.ownInitiative);
      expect(structured((sor) => sor['noticeSource'] = '').noticeSource, NoticeSource.notice);
    });

    test('a wrong type is a FormatException', () {
      expect(() => structured((sor) => sor['noticeSource'] = 1), throwsFormatException);
    });

    test('is written for an old decision as well, so the model stays valid', () {
      expect(structured().toJson()['noticeSource'], 'notice');
      expect(structured((sor) => sor['basedOnNotice'] = false).toJson()['noticeSource'], 'own_initiative');
    });

    test('NoticeSource.tryParse', () {
      expect(NoticeSource.tryParse('trusted_flagger'), NoticeSource.trustedFlagger);
      expect(NoticeSource.tryParse('trustedFlagger'), isNull);
      expect(NoticeSource.tryParse('nope'), isNull);
      expect([for (final s in NoticeSource.values) s.wireName], ['notice', 'trusted_flagger', 'own_initiative']);
    });

    test('survives a decision round trip', () {
      final json = jsonDecode(decisionCreated) as Map<String, Object?>;
      (((json['decision']! as Map<String, Object?>)['statementOfReasons']! as Map<String, Object?>)['structured']!
          as Map<String, Object?>)['noticeSource'] = 'trusted_flagger';
      final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
      final again = ModerationDecision.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>);
      expect(again.statementOfReasons.structured.noticeSource, NoticeSource.trustedFlagger);
      expect(again.toJson(), d.toJson());
    });
  });

  group('automation (API 0.19.0)', () {
    SorDetails structured([void Function(Map<String, Object?> structured)? change]) {
      final json = jsonDecode(decisionCreated) as Map<String, Object?>;
      final decision = json['decision']! as Map<String, Object?>;
      final sor = (decision['statementOfReasons']! as Map<String, Object?>)['structured']! as Map<String, Object?>;
      change?.call(sor);
      return (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision.statementOfReasons.structured;
    }

    test('reads every value', () {
      for (final (wire, automation) in [
        ('none', Automation.none),
        ('partial', Automation.partial),
        ('full', Automation.full),
      ]) {
        final s = structured((sor) => sor['automation'] = wire);
        expect(s.automation, automation, reason: wire);
        expect(s.automationName, wire);
        expect(s.toJson()['automation'], wire);
      }
    });

    test('partial is not an automated decision, full is', () {
      // A moderator confirmed an AI suggestion: automatedDecision stays false.
      final partial = structured((sor) => sor['automation'] = 'partial');
      expect(partial.automatedDecision, isFalse);
      expect(partial.automation.usesAutomatedMeans, isTrue);
      final full = structured((sor) {
        sor['automation'] = 'full';
        sor['automatedDecision'] = true;
      });
      expect(full.automatedDecision, isTrue);
      expect(full.automation.usesAutomatedMeans, isTrue);
      expect(Automation.none.usesAutomatedMeans, isFalse);
    });

    test('is none in a decision from before API 0.19.0', () {
      final s = structured();
      expect(s.automationName, isNull);
      expect(s.automation, Automation.none);
      expect(s.automation.usesAutomatedMeans, isFalse);
    });

    test('is none for a value this version does not know, the raw value stays', () {
      final s = structured((sor) => sor['automation'] = 'assisted');
      expect(s.automation, Automation.none);
      expect(s.automationName, 'assisted');
      expect(s.toJson()['automation'], 'assisted');
      expect(structured((sor) => sor['automation'] = '').automation, Automation.none);
      expect(structured((sor) => sor['automation'] = 'Partial').automation, Automation.none);
    });

    test('a wrong type is a FormatException', () {
      expect(() => structured((sor) => sor['automation'] = 1), throwsFormatException);
      expect(() => structured((sor) => sor['automation'] = true), throwsFormatException);
    });

    test('is written for an old decision as well, so the model stays valid', () {
      expect(structured().toJson()['automation'], 'none');
    });

    test('Automation.tryParse', () {
      expect(Automation.tryParse('partial'), Automation.partial);
      expect(Automation.tryParse('FULL'), isNull);
      expect(Automation.tryParse('nope'), isNull);
      expect([for (final a in Automation.values) a.wireName], ['none', 'partial', 'full']);
    });

    test('survives a decision round trip', () {
      for (final wire in ['none', 'partial', 'full', 'assisted']) {
        final json = jsonDecode(decisionCreated) as Map<String, Object?>;
        (((json['decision']! as Map<String, Object?>)['statementOfReasons']! as Map<String, Object?>)['structured']!
            as Map<String, Object?>)['automation'] = wire;
        final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
        final again = ModerationDecision.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>);
        expect(again.statementOfReasons.structured.automationName, wire);
        expect(again.statementOfReasons.structured.automation, Automation.tryParse(wire) ?? Automation.none);
        expect(again.toJson(), d.toJson());
      }
    });
  });

  test('a decision survives a JSON round trip', () {
    final d = (parse(decisionCreated) as DecisionCreatedEvent).decision;
    final again = ModerationDecision.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>);
    expect(again.toJson(), d.toJson());
  });

  test('a decision from the subject file has no content', () {
    final json = jsonDecode(decisionCreated) as Map<String, Object?>;
    final decision = json['decision']! as Map<String, Object?>
      ..remove('content')
      ..['action'] = 'restore'
      ..remove('suspendUntil')
      ..['policies'] = <Object?>[];
    final d = ModerationDecision.fromJson(decision);
    expect(d.externalContentId, isNull);
    expect(d.action, ModerationAction.restore);
    expect(d.policies, isEmpty);
  });

  test('appealId and replacesDecisionId are optional', () {
    final json = jsonDecode(decisionCreated) as Map<String, Object?>;
    final decision = json['decision']! as Map<String, Object?>;
    final plain = ModerationDecision.fromJson(decision);
    expect(plain.appealId, isNull);
    expect(plain.replacesDecisionId, isNull);
    decision
      ..['appealId'] = '01J0000000000000000000APPL'
      ..['replacesDecisionId'] = '01J0000000000000000000DECI';
    final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
    expect(d.appealId, '01J0000000000000000000APPL');
    expect(d.replacesDecisionId, '01J0000000000000000000DECI');
    expect(ModerationDecision.fromJson(d.toJson()).toJson(), d.toJson());
  });

  test('reviewId is optional', () {
    final json = jsonDecode(decisionCreated) as Map<String, Object?>;
    final decision = json['decision']! as Map<String, Object?>;
    final plain = ModerationDecision.fromJson(decision);
    expect(plain.reviewId, isNull);
    expect(plain.toJson().containsKey('reviewId'), isFalse);
    decision['reviewId'] = '01K6T2R0000000000000000000';
    final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
    expect(d.reviewId, '01K6T2R0000000000000000000');
    expect(d.toJson()['reviewId'], '01K6T2R0000000000000000000');
    expect(
        ModerationDecision.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>).toJson(), d.toJson());
  });

  test('restoreScope is optional and tolerates unknown values', () {
    final json = jsonDecode(decisionCreated) as Map<String, Object?>;
    final decision = json['decision']! as Map<String, Object?>
      ..['action'] = 'restore'
      ..remove('suspendUntil');
    final plain = ModerationDecision.fromJson(decision);
    expect([plain.restoreScopeName, plain.restoreScope], [null, null]);
    expect(plain.toJson().containsKey('restoreScope'), isFalse);
    for (final scope in RestoreScope.values) {
      decision['restoreScope'] = scope.name;
      final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
      expect(d.restoreScope, scope);
      expect(d.toJson()['restoreScope'], scope.name);
      expect(
        ModerationDecision.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>).toJson(),
        d.toJson(),
      );
    }
    decision['restoreScope'] = 'profile'; // a scope of a later version of Limenia
    final unknown = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
    expect(unknown.restoreScope, isNull);
    expect(unknown.restoreScopeName, 'profile');
    expect(unknown.toJson()['restoreScope'], 'profile');
    decision['restoreScope'] = 7;
    expect(() => LimeniaEvent.fromJson(json), throwsFormatException);
  });

  test('RestoreScope.tryParse', () {
    expect(RestoreScope.tryParse('content'), RestoreScope.content);
    expect(RestoreScope.tryParse('account'), RestoreScope.account);
    expect(RestoreScope.tryParse('Content'), isNull);
    expect(RestoreScope.tryParse(''), isNull);
  });

  group('ModerationDecision.changesUserStatus', () {
    const reviewId = '01K6T2R0000000000000000000';

    // A decision as in the event decision.created, with another action.
    ModerationDecision decisionWith(String action, {bool forReview = false, String? restoreScope}) {
      final json = jsonDecode(decisionCreated) as Map<String, Object?>;
      final decision = json['decision']! as Map<String, Object?>
        ..['action'] = action
        ..remove('suspendUntil');
      if (forReview) {
        // What Limenia sends for a new decision on a review request after a complaint.
        decision
          ..['reviewId'] = reviewId
          ..['appealId'] = '01K6S1APPEAL0000000000000A'
          ..['replacesDecisionId'] = '01K6T2D0000000000000000000';
      }
      if (restoreScope != null) decision['restoreScope'] = restoreScope;
      return (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
    }

    test('for a restore follows restoreScope', () {
      expect(decisionWith('restore', restoreScope: 'account').changesUserStatus, isTrue);
      expect(decisionWith('restore').changesUserStatus, isTrue); // Limenia before API 0.13.2
      final content = decisionWith('restore', restoreScope: 'content');
      expect(content.action!.changesUserStatus, isTrue); // the action alone does not know
      expect(content.changesUserStatus, isFalse);
      // A scope this version does not know may keep the status.
      expect(decisionWith('restore', restoreScope: 'profile').changesUserStatus, isFalse);
      // What Limenia sends for a restore on a review request from API 0.13.2.
      expect(decisionWith('restore', forReview: true, restoreScope: 'content').changesUserStatus, isFalse);
    });

    test('ignores restoreScope for other actions', () {
      for (final action in ModerationAction.values.where((a) => a != ModerationAction.restore)) {
        expect(
          decisionWith(action.wireName, restoreScope: 'content').changesUserStatus,
          action.changesUserStatus,
          reason: action.wireName,
        );
      }
    });

    test('is false for a restore with reviewId and true for a restore without it', () {
      final plain = decisionWith('restore');
      expect(plain.reviewId, isNull);
      expect(plain.changesUserStatus, isTrue);

      final review = decisionWith('restore', forReview: true);
      expect(review.action, ModerationAction.restore);
      expect(review.reviewId, reviewId);
      expect(review.appealId, '01K6S1APPEAL0000000000000A');
      expect(review.replacesDecisionId, '01K6T2D0000000000000000000');
      expect(review.action!.changesUserStatus, isTrue); // the action alone does not know
      expect(review.changesUserStatus, isFalse);
    });

    test('follows the action without reviewId', () {
      for (final action in ModerationAction.values) {
        expect(decisionWith(action.wireName).changesUserStatus, action.changesUserStatus, reason: action.wireName);
      }
      expect(decisionWith('shadow_ban').changesUserStatus, isFalse);
    });

    test('is false for every action with reviewId', () {
      for (final action in ModerationAction.values) {
        expect(decisionWith(action.wireName, forReview: true).changesUserStatus, isFalse, reason: action.wireName);
      }
      expect(decisionWith('shadow_ban', forReview: true).changesUserStatus, isFalse);
    });
  });

  test('an unknown action stays readable', () {
    final json = jsonDecode(decisionCreated) as Map<String, Object?>;
    (json['decision']! as Map<String, Object?>)['action'] = 'shadow_ban';
    final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
    expect(d.action, isNull);
    expect(d.actionName, 'shadow_ban');
  });

  test('subject.status_changed', () {
    final event = parse(statusChanged) as SubjectStatusChangedEvent;
    expect(event.subject, const SubjectStatus.active('u_112'));
    expect(event.createdAt, DateTime.utc(2026, 10, 8, 8, 15, 2, 481, 233));
  });

  test('appeal.resolved', () {
    final event = parse(appealResolved);
    expect(event, isA<AppealResolvedEvent>());
    expect(event.type, 'appeal.resolved');
    final a = (event as AppealResolvedEvent).appeal;
    expect(a.externalAppealId, 'appeal_17');
    expect(a.appellantType, AppellantType.subject);
    expect(a.outcome, AppealOutcome.changed);
    expect(a.statementText, startsWith('Response to your complaint\n\n'));
    expect(a.resolvedAt, DateTime.utc(2026, 10, 5, 9));
    expect(a.newDecisionId, '01K6S1DECISION000000000NEW');
    expect(AppealResolution.fromJson(a.toJson()).toJson(), a.toJson());
  });

  test('reports.resolved', () {
    final event = parse(reportsResolved);
    expect(event, isA<ReportsResolvedEvent>());
    expect(event.type, 'reports.resolved');
    final r = (event as ReportsResolvedEvent).reports;
    expect(r.action, ModerationAction.dismiss);
    expect(r.policies, isEmpty);
    expect(r.appealDeadline, DateTime.utc(2027, 4, 1, 10));
    expect(r.reports.map((i) => i.externalReportId ?? i.reportId), ['rep_77', '01K6REPORT0000000000000002']);
    expect(ReportsResolution.fromJson(r.toJson()).toJson(), r.toJson());
  });

  test('review.decided', () {
    final event = parse(reviewDecided);
    expect(event, isA<ReviewDecidedEvent>());
    expect(event.type, 'review.decided');
    expect(event.createdAt, DateTime.utc(2026, 10, 3, 9, 12, 0, 123, 456));
    final r = (event as ReviewDecidedEvent).review;
    expect(r.id, '01K6T2R0000000000000000000');
    expect(r.externalReviewId, 'upload_881');
    expect(r.type, 'profile_photo');
    expect(r.outcome, ReviewOutcome.rejected);
    expect(r.decidedAt, DateTime.utc(2026, 10, 3, 9, 12, 0, 98, 765));
    expect(r.decisionId, '01K6T2D0000000000000000000');
    expect(r.externalContentId, 'photo_881');
    expect(ReviewResolution.fromJson(r.toJson()).toJson(), r.toJson());
  });

  test('review.decided with an unknown outcome throws a FormatException', () {
    final json = jsonDecode(reviewDecided) as Map<String, Object?>;
    (json['review']! as Map<String, Object?>)['outcome'] = 'postponed';
    expect(() => LimeniaEvent.fromJson(json), throwsFormatException);
  });

  test('a rejected review request comes as decision.created with reject_submission', () {
    final json = jsonDecode(decisionCreated) as Map<String, Object?>;
    final decision = json['decision']! as Map<String, Object?>
      ..['id'] = '01K6T2D0000000000000000000'
      ..['action'] = 'reject_submission'
      ..remove('suspendUntil')
      ..['content'] = {'externalContentId': 'photo_881'};
    ((decision['statementOfReasons']! as Map<String, Object?>)['structured']! as Map<String, Object?>)
      ..['action'] = 'reject_submission'
      ..remove('endsAt');
    final d = (LimeniaEvent.fromJson(json) as DecisionCreatedEvent).decision;
    expect(d.action, ModerationAction.rejectSubmission);
    expect(d.statementOfReasons.structured.action, ModerationAction.rejectSubmission);
    expect(d.action!.informsAffectedUser, isTrue);
    expect(d.action!.targetsContent, isTrue);
    expect(d.action!.changesUserStatus, isFalse);
    // The status of the author stays as it is.
    expect(const SubjectStatus.active('u_112').afterDecision(d), const SubjectStatus.active('u_112'));
  });

  test('test.ping and unknown types', () {
    expect(parse('{"id":"e","type":"test.ping","createdAt":"2026-10-01T10:00:00Z","app":{"id":"a","slug":"s"}}'),
        isA<TestPingEvent>());
    final unknown = parse('{"id":"e","type":"appeal.created","createdAt":"2026-10-01T10:00:00Z",'
        '"app":{"id":"a","slug":"s"},"appeal":{"id":"x"}}');
    expect(unknown, isA<UnknownLimeniaEvent>());
    expect(unknown.type, 'appeal.created');
    expect((unknown as UnknownLimeniaEvent).json['appeal'], {'id': 'x'});
  });

  test('broken events throw a FormatException', () {
    expect(() => parse('{"id":"e","type":"test.ping","createdAt":"yesterday","app":{"id":"a","slug":"s"}}'),
        throwsFormatException);
    expect(
        () => parse(
            '{"id":"e","type":"decision.created","createdAt":"2026-10-01T10:00:00Z","app":{"id":"a","slug":"s"}}'),
        throwsFormatException);
  });

  test('ModerationAction', () {
    expect(ModerationAction.tryParse('remove_content'), ModerationAction.removeContent);
    expect(ModerationAction.tryParse('nope'), isNull);
    expect(ModerationAction.values.where((a) => a.changesUserStatus).map((a) => a.wireName),
        ['warn_user', 'suspend_user', 'ban_user', 'restore']);
    expect(ModerationAction.tryParse('reject_submission'), ModerationAction.rejectSubmission);
    expect(ModerationAction.values.where((a) => a.targetsContent).map((a) => a.wireName),
        ['remove_content', 'restrict_content', 'reject_submission']);
    expect(ModerationAction.values.where((a) => !a.informsAffectedUser), [ModerationAction.dismiss]);
  });
}
