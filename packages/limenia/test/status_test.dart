import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 12);
  final until = DateTime.utc(2026, 10, 3, 12);
  final suspended = SubjectStatus(externalUserId: 'u', status: SanctionStatus.suspended, suspendedUntil: until);

  test('fromJson and toJson', () {
    final json = {'externalUserId': 'u', 'status': 'suspended', 'suspendedUntil': '2026-10-03T12:00:00.000Z'};
    expect(SubjectStatus.fromJson(json), suspended);
    expect(suspended.toJson(), json);
    expect(() => SubjectStatus.fromJson({'externalUserId': 'u', 'status': 'muted'}), throwsFormatException);
  });

  test('a suspension ends at suspendedUntil', () {
    expect(suspended.effectiveAt(now), suspended);
    expect(suspended.isRestrictedAt(now), isTrue);
    expect(suspended.effectiveAt(until), const SubjectStatus.active('u'));
    expect(suspended.isRestrictedAt(until), isFalse);
  });

  test('banned and warned', () {
    const banned = SubjectStatus(externalUserId: 'u', status: SanctionStatus.banned);
    const warned = SubjectStatus(externalUserId: 'u', status: SanctionStatus.warned);
    expect(banned.isRestrictedAt(now), isTrue);
    expect(warned.isRestrictedAt(now), isFalse);
  });

  group('afterDecision follows the rules of Limenia', () {
    const active = SubjectStatus.active('u');
    const banned = SubjectStatus(externalUserId: 'u', status: SanctionStatus.banned);
    SubjectStatus after(
      SubjectStatus s,
      String action, {
      DateTime? decidedAt,
      DateTime? suspendUntil,
      String? reviewId,
      String? restoreScope,
    }) =>
        s.afterDecision(decision(
          action: action,
          userId: 'u',
          decidedAt: decidedAt ?? now,
          suspendUntil: suspendUntil,
          reviewId: reviewId,
          restoreScope: restoreScope,
        ));

    test('warn changes an active user only', () {
      expect(after(active, 'warn_user').status, SanctionStatus.warned);
      expect(after(suspended, 'warn_user'), suspended);
    });
    test('a warning after the end of a suspension makes the user warned', () {
      // Limenia lifts the ended suspension with the decision (API 0.13.2).
      const warned = SubjectStatus(externalUserId: 'u', status: SanctionStatus.warned);
      expect(after(suspended, 'warn_user', decidedAt: until), warned);
      expect(after(suspended, 'warn_user', decidedAt: until.add(const Duration(days: 3))), warned);
      expect(after(suspended, 'warn_user', decidedAt: until.subtract(const Duration(microseconds: 1))), suspended);
      expect(after(banned, 'warn_user', decidedAt: until), banned);
    });
    test('suspend and ban replace the status', () {
      expect(after(banned, 'suspend_user', suspendUntil: until), suspended);
      expect(after(suspended, 'ban_user'), banned);
    });
    test('a restore of the account makes the user active', () {
      expect(after(suspended, 'restore', restoreScope: 'account'), active);
      expect(after(banned, 'restore', restoreScope: 'account'), active);
      expect(after(banned, 'restore'), active); // Limenia before API 0.13.2
    });
    test('a restore of the content keeps the status', () {
      expect(after(suspended, 'restore', restoreScope: 'content'), suspended);
      expect(after(banned, 'restore', restoreScope: 'content'), banned);
      // So does a scope this version does not know (the watcher asks Limenia).
      expect(after(banned, 'restore', restoreScope: 'profile'), banned);
    });
    test('a decision about a review request keeps the status, a restore too', () {
      expect(after(suspended, 'restore', reviewId: '01K6T2R0000000000000000000'), suspended);
      expect(after(banned, 'restore', reviewId: '01K6T2R0000000000000000000'), banned);
      for (final action in ModerationAction.values) {
        expect(after(banned, action.wireName, reviewId: 'r', suspendUntil: until), banned, reason: action.wireName);
        expect(after(active, action.wireName, reviewId: 'r', suspendUntil: until), active, reason: action.wireName);
      }
    });
    test('other actions keep the status', () {
      for (final action in ['dismiss', 'remove_content', 'restrict_content', 'unknown_action']) {
        expect(after(suspended, action), suspended, reason: action);
      }
    });
  });
}
