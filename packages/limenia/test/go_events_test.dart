// Parses the webhook events exactly as the Limenia backend builds them. The
// fixtures in test/fixtures/events were generated from the code of the
// backend, not from the spec or the docs, so this test
// fails when the package cannot read what Limenia really sends.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

LimeniaEvent fixture(String name) =>
    LimeniaEvent.fromJson(jsonDecode(File('test/fixtures/events/$name.json').readAsStringSync()) as JsonMap);

T event<T extends LimeniaEvent>(String name) {
  final e = fixture(name);
  expect(e, isA<T>(), reason: name);
  return e as T;
}

void main() {
  final createdAt = DateTime.utc(2026, 10, 1, 10, 0, 0, 123, 456);
  final until = DateTime.utc(2026, 10, 8, 8);
  final later = DateTime.utc(2026, 10, 1, 11, 30, 0, 623, 456);

  test('every fixture is a known event with the common fields', () {
    final files = Directory('test/fixtures/events').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    expect(files, isNotEmpty);
    for (final file in files) {
      final e = LimeniaEvent.fromJson(jsonDecode(file.readAsStringSync()) as JsonMap);
      expect(e, isNot(isA<UnknownLimeniaEvent>()), reason: file.path);
      expect(e.createdAt, createdAt, reason: file.path);
      expect(e.appSlug, 'photoapp', reason: file.path);
      expect(e.id, startsWith('evt_'), reason: file.path);
    }
  });

  test('test.ping', () => event<TestPingEvent>('test_ping'));

  group('decision.created', () {
    test('suspension with content, user and two grounds', () {
      final d = event<DecisionCreatedEvent>('decision_suspend').decision;
      expect(d.action, ModerationAction.suspendUser);
      expect(d.suspendUntil, until);
      expect(d.externalContentId, 'comment_5521');
      expect(d.externalUserId, 'u_112');
      expect(d.policies.map((p) => p.code), ['harassment_hate', 'hate']);
      expect(d.statementOfReasons.locale, 'de');
      final s = d.statementOfReasons.structured;
      expect(s.endsAt, until);
      expect(s.grounds.map((g) => g.basis), [LegalBasis.terms, LegalBasis.law]);
      expect(s.grounds.last.lawReference, '§ 130 StGB');
      expect(d.changesUserStatus, isTrue);
      expect([d.appealId, d.replacesDecisionId, d.reviewId], [null, null, null]);
    });

    test('dismissal without content, user, policies or texts', () {
      final d = event<DecisionCreatedEvent>('decision_dismiss_minimal').decision;
      expect(d.action, ModerationAction.dismiss);
      expect([d.externalContentId, d.externalUserId, d.suspendUntil], [null, null, null]);
      expect(d.policies, isEmpty);
      expect(d.statementOfReasons.text, isEmpty);
      expect(d.statementOfReasons.structured.grounds, isEmpty);
      expect(d.changesUserStatus, isFalse);
    });

    test('actions against the user change the status', () {
      expect(event<DecisionCreatedEvent>('decision_ban_user_only').decision.externalContentId, isNull);
      for (final name in ['decision_ban_user_only', 'decision_warn']) {
        expect(event<DecisionCreatedEvent>(name).decision.changesUserStatus, isTrue, reason: name);
      }
      expect(event<DecisionCreatedEvent>('decision_remove_content').decision.changesUserStatus, isFalse);
    });

    test('restore of the account after a complaint names complaint and replaced decision', () {
      final d = event<DecisionCreatedEvent>('decision_restore_after_appeal').decision;
      expect(d.action, ModerationAction.restore);
      expect(d.appealId, 'apl_1');
      expect(d.replacesDecisionId, 'dec_suspend');
      expect(d.reviewId, isNull);
      // Stored without a scope, as before API 0.13.2: Limenia sends what it did.
      expect(d.restoreScope, RestoreScope.account);
      expect(d.changesUserStatus, isTrue);
      const banned = SubjectStatus(externalUserId: 'u_112', status: SanctionStatus.banned);
      expect(banned.afterDecision(d), const SubjectStatus.active('u_112'));
    });

    test('restore of the content after a complaint keeps the status', () {
      final d = event<DecisionCreatedEvent>('decision_restore_content').decision;
      expect(d.action, ModerationAction.restore);
      expect(d.restoreScopeName, 'content');
      expect(d.restoreScope, RestoreScope.content);
      expect(d.externalContentId, 'comment_1');
      expect([d.appealId, d.replacesDecisionId, d.reviewId], ['apl_4', 'dec_remove', null]);
      expect(d.action!.changesUserStatus, isTrue); // the action alone does not know
      expect(d.changesUserStatus, isFalse);
      final suspended = SubjectStatus(externalUserId: 'u_112', status: SanctionStatus.suspended, suspendedUntil: until);
      expect(suspended.afterDecision(d), suspended);
    });

    test('only a restore has a restoreScope', () {
      final names = [
        for (final file in Directory('test/fixtures/events').listSync().whereType<File>())
          if (file.uri.pathSegments.last case final name when name.endsWith('.json')) name.replaceAll('.json', ''),
      ];
      final decisions = [
        for (final name in names)
          if (fixture(name) case DecisionCreatedEvent(:final decision)) decision,
      ];
      expect(decisions.where((d) => d.action == ModerationAction.restore), hasLength(3));
      for (final d in decisions) {
        expect(d.restoreScope != null, d.action == ModerationAction.restore, reason: d.id);
      }
    });

    test('decisions on a review request never change the status', () {
      final reject = event<DecisionCreatedEvent>('decision_reject_submission').decision;
      expect(reject.action, ModerationAction.rejectSubmission);
      expect(reject.reviewId, 'rev_1');
      expect(reject.externalContentId, 'photo_77');
      expect(reject.changesUserStatus, isFalse);

      final restrict = event<DecisionCreatedEvent>('decision_restrict_on_review').decision;
      expect(restrict.action, ModerationAction.restrictContent);
      expect([restrict.reviewId, restrict.appealId, restrict.replacesDecisionId], ['rev_1', 'apl_3', 'dec_review']);
      expect(restrict.changesUserStatus, isFalse);

      final restore = event<DecisionCreatedEvent>('decision_restore_on_review').decision;
      expect([restore.reviewId, restore.appealId, restore.replacesDecisionId], ['rev_1', 'apl_2', 'dec_review']);
      expect(restore.restoreScope, RestoreScope.content);
      expect(restore.changesUserStatus, isFalse);
      const banned = SubjectStatus(externalUserId: 'u_112', status: SanctionStatus.banned);
      expect(banned.afterDecision(restore), banned);
    });
  });

  test('subject.status_changed', () {
    expect(event<SubjectStatusChangedEvent>('subject_status_active').subject, const SubjectStatus.active('u_112'));
    final s = event<SubjectStatusChangedEvent>('subject_status_suspended').subject;
    expect(s.status, SanctionStatus.suspended);
    expect(s.suspendedUntil, until);
    // A warning that lifts an ended suspension (API 0.13.2).
    expect(
      event<SubjectStatusChangedEvent>('subject_status_warned').subject,
      const SubjectStatus(externalUserId: 'u_112', status: SanctionStatus.warned),
    );
  });

  test('the statement of reasons of every decision has a noticeSource this version reads', () {
    final files = Directory('test/fixtures/events').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    for (final file in files) {
      final e = LimeniaEvent.fromJson(jsonDecode(file.readAsStringSync()) as JsonMap);
      if (e is! DecisionCreatedEvent) continue;
      final s = e.decision.statementOfReasons.structured;
      // Fixtures from before API 0.16.0 have no noticeSource and derive it from basedOnNotice.
      if (s.noticeSourceName != null) {
        expect(NoticeSource.tryParse(s.noticeSourceName!), isNotNull, reason: file.path);
      }
      expect(s.noticeSource, isA<NoticeSource>(), reason: file.path);
    }
  });

  test('the statement of reasons of every decision has an automation this version reads', () {
    final files = Directory('test/fixtures/events').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    for (final file in files) {
      final e = LimeniaEvent.fromJson(jsonDecode(file.readAsStringSync()) as JsonMap);
      if (e is! DecisionCreatedEvent) continue;
      final s = e.decision.statementOfReasons.structured;
      // Fixtures from before API 0.19.0 have no automation and are none.
      if (s.automationName != null) {
        expect(Automation.tryParse(s.automationName!), isNotNull, reason: file.path);
      }
      // automatedDecision is true only for a full automation.
      expect(s.automatedDecision, s.automation == Automation.full, reason: file.path);
    }
  });

  test('automation of decisions, as the backend writes it', () {
    final none = event<DecisionCreatedEvent>('decision_suspend').decision.statementOfReasons.structured;
    expect([none.automationName, none.automation, none.automatedDecision], ['none', Automation.none, false]);
    final partial = event<DecisionCreatedEvent>('decision_automation_partial').decision.statementOfReasons.structured;
    expect([
      partial.automationName,
      partial.automation,
      partial.automatedDecision
    ], [
      'partial',
      Automation.partial,
      false,
    ]);
    final full = event<DecisionCreatedEvent>('decision_automation_full').decision.statementOfReasons.structured;
    expect([full.automationName, full.automation, full.automatedDecision], ['full', Automation.full, true]);
  });

  group('appeal.resolved', () {
    test('changed', () {
      final a = event<AppealResolvedEvent>('appeal_resolved_changed').appeal;
      expect(a.outcome, AppealOutcome.changed);
      expect(a.appellantType, AppellantType.subject);
      expect(a.externalAppealId, 'app-appeal-1');
      expect(a.newDecisionId, 'dec_appeal');
      expect(a.resolvedAt, later);
    });

    test('upheld, without optional IDs', () {
      final a = event<AppealResolvedEvent>('appeal_resolved_upheld').appeal;
      expect(a.outcome, AppealOutcome.upheld);
      expect(a.appellantType, AppellantType.reporter);
      expect([a.externalAppealId, a.newDecisionId], [null, null]);
    });
  });

  group('reports.resolved', () {
    test('with reports', () {
      final r = event<ReportsResolvedEvent>('reports_resolved').reports;
      expect(r.decisionId, 'dec_suspend');
      expect(r.action, ModerationAction.suspendUser);
      expect(r.decidedAt, createdAt);
      expect(r.appealDeadline, DateTime.utc(2027, 4, 1, 10, 0, 0, 123, 456));
      expect(r.reports.map((x) => (x.reportId, x.externalReportId)), [('rep_1', 'app-report-1'), ('rep_2', null)]);
      expect(r.policies.map((p) => p.code), ['harassment_hate', 'hate']);
    });

    test('empty lists', () {
      final r = event<ReportsResolvedEvent>('reports_resolved_empty').reports;
      expect(r.reports, isEmpty);
      expect(r.policies, isEmpty);
    });
  });

  group('review.decided', () {
    test('rejected', () {
      final r = event<ReviewDecidedEvent>('review_decided_rejected').review;
      expect(r.outcome, ReviewOutcome.rejected);
      expect(r.type, 'profile_photo');
      expect(r.externalReviewId, 'app-review-1');
      expect(r.decisionId, 'dec_review');
      expect(r.externalContentId, 'photo_77');
      expect(r.decidedAt, later);
    });

    test('approved has no decision', () {
      final r = event<ReviewDecidedEvent>('review_decided_approved').review;
      expect(r.outcome, ReviewOutcome.approved);
      expect([r.decisionId, r.externalReviewId], [null, null]);
      expect(r.externalContentId, 'photo_78');
    });

    test('restricted', () {
      final r = event<ReviewDecidedEvent>('review_decided_restricted').review;
      expect(r.outcome, ReviewOutcome.restricted);
      expect(r.decisionId, 'dec_restrict');
    });
  });
}
