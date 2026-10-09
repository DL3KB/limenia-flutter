import 'dart:async';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late FakeTransport transport;
  late FakeClock clock;
  late FakeTimers timers;
  late SubjectStatusWatcher watcher;
  late List<SubjectStatus> changes;

  final t0 = DateTime.utc(2026, 10, 2, 12);
  final t1 = t0.add(_s);
  final t2 = t0.add(_s * 2);
  const active = SubjectStatus.active('u');
  const warned = SubjectStatus(externalUserId: 'u', status: SanctionStatus.warned);
  const banned = SubjectStatus(externalUserId: 'u', status: SanctionStatus.banned);
  SubjectStatus suspendedUntil(DateTime until) =>
      SubjectStatus(externalUserId: 'u', status: SanctionStatus.suspended, suspendedUntil: until);
  ModerationDecision ban(DateTime at) => decision(action: 'ban_user', userId: 'u', decidedAt: at);
  ModerationDecision warn(DateTime at) => decision(action: 'warn_user', userId: 'u', decidedAt: at);
  ModerationDecision restore(DateTime at) => decision(action: 'restore', userId: 'u', decidedAt: at);
  ModerationDecision suspend(DateTime at, DateTime until) =>
      decision(action: 'suspend_user', userId: 'u', decidedAt: at, suspendUntil: until);
  // An action of a later version of Limenia.
  ModerationDecision unknown(DateTime at, {String userId = 'u', String? reviewId}) =>
      decision(action: 'shadow_ban', userId: userId, decidedAt: at, reviewId: reviewId);
  DecisionCreatedEvent decided(ModerationDecision d) =>
      DecisionCreatedEvent(id: 'e_${d.id}', createdAt: d.decidedAt, appId: 'a', appSlug: 's', decision: d);
  SubjectStatusChangedEvent statusChanged(SubjectStatus subject, DateTime at) => SubjectStatusChangedEvent(
        id: 'e_${at.microsecondsSinceEpoch}',
        createdAt: at,
        appId: 'a',
        appSlug: 's',
        subject: subject,
      );

  SubjectStatusWatcher build({bool refreshOnEvent = false}) => SubjectStatusWatcher(
        transport: transport,
        externalUserId: 'u',
        refreshOnEvent: refreshOnEvent,
        now: clock.call,
        createTimer: timers.create,
      );

  setUp(() {
    transport = FakeTransport();
    clock = FakeClock(t0);
    timers = FakeTimers();
    watcher = build();
    changes = [];
    watcher.changes.listen(changes.add);
  });

  tearDown(() => watcher.dispose());

  test('refresh fetches the status and emits changes only', () async {
    expect(watcher.current, isNull);
    expect(watcher.isRestricted, isFalse);
    transport.statusAnswers.addAll([banned, banned, active]);
    expect(await watcher.refresh(), banned);
    expect(watcher.isRestricted, isTrue);
    await watcher.refresh();
    await watcher.refresh();
    expect(changes, [banned, active]);
    expect(transport.statusCalls, ['u', 'u', 'u']);
  });

  test('refresh throws the errors of the transport', () async {
    transport.statusAnswers.add(const LimeniaException(503));
    await expectLater(watcher.refresh(), throwsA(isA<LimeniaException>()));
    expect(watcher.current, isNull);
  });

  test('a suspension ends on time', () async {
    final until = t0.add(const Duration(days: 1));
    transport.statusAnswers.add(suspendedUntil(until));
    await watcher.refresh();
    expect(watcher.isRestricted, isTrue);
    final timer = timers.active.single;
    expect(timer.duration, const Duration(days: 1));

    clock.now = until.subtract(const Duration(milliseconds: 5));
    timer.fire(); // a little early: no change, waits again
    expect(changes, [suspendedUntil(until)]);
    expect(timers.active.single.duration, const Duration(milliseconds: 5));

    clock.now = until;
    timers.active.single.fire();
    expect(changes, [suspendedUntil(until), active]);
    expect(watcher.isRestricted, isFalse);
    expect(timers.active, isEmpty);
  });

  test('a long suspension waits at most a day per timer', () async {
    // Browsers fire a timer of more than about 24.8 days at once.
    final until = t0.add(const Duration(days: 30));
    transport.statusAnswers.add(suspendedUntil(until));
    await watcher.refresh();
    for (var day = 1; day < 30; day++) {
      final timer = timers.active.single;
      expect(timer.duration, const Duration(days: 1));
      clock.now = t0.add(Duration(days: day));
      timer.fire(); // before the end: still suspended, waits again
      expect(watcher.current, suspendedUntil(until));
      expect(watcher.isRestricted, isTrue);
    }
    final last = timers.active.single;
    expect(last.duration, const Duration(days: 1));
    clock.now = until;
    last.fire();
    expect(watcher.current, active);
    expect(timers.active, isEmpty);
    expect(timers.timers, hasLength(30));
    expect(changes, [suspendedUntil(until), active]);
  });

  test('an ended suspension is active at once without a timer', () async {
    transport.statusAnswers.add(suspendedUntil(t0.subtract(const Duration(minutes: 1))));
    expect(await watcher.refresh(), active);
    expect(timers.active, isEmpty);
  });

  test('applies decisions for this user and ignores others', () {
    final until = t0.add(const Duration(days: 2));
    expect(watcher.handleDecision(decision(action: 'suspend_user', userId: 'u', decidedAt: t0, suspendUntil: until)),
        isTrue);
    expect(watcher.current, suspendedUntil(until));
    expect(watcher.handleDecision(decision(action: 'ban_user', userId: 'other', decidedAt: t0.add(_s))), isFalse);
    expect(watcher.handleDecision(decision(action: 'remove_content', userId: 'u', decidedAt: t0.add(_s))), isFalse);
    expect(watcher.handleDecision(decision(action: 'shadow_ban', userId: 'u', decidedAt: t0.add(_s))), isFalse);
    expect(changes, [suspendedUntil(until)]);
    expect(transport.statusCalls, isEmpty); // refreshOnEvent is off
  });

  test('ignores a restore about a review request', () async {
    transport.statusAnswers.add(banned);
    await watcher.refresh();
    final forReview =
        decision(action: 'restore', userId: 'u', decidedAt: t0.add(_s), reviewId: '01K6T2R0000000000000000000');
    expect(watcher.handleDecision(forReview), isFalse);
    expect(
      watcher.handleEvent(DecisionCreatedEvent(id: 'e1', createdAt: t0, appId: 'a', appSlug: 's', decision: forReview)),
      isFalse,
    );
    expect(watcher.current, banned);
    expect(watcher.isRestricted, isTrue);
    // It was not applied, so it does not make a real restore look old.
    expect(watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t0)), isTrue);
    expect(watcher.current, active);
    expect(changes, [banned, active]);
  });

  test('ignores events older than the last applied one', () {
    watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t0.add(_s * 2)));
    expect(watcher.handleDecision(decision(action: 'ban_user', userId: 'u', decidedAt: t0.add(_s))), isFalse);
    expect(watcher.current, active);
    final late = SubjectStatusChangedEvent(
      id: 'e',
      createdAt: t0.add(_s * 2),
      appId: 'a',
      appSlug: 's',
      subject: banned,
    );
    expect(watcher.handleEvent(late), isFalse);
    expect(transport.statusCalls, isEmpty); // refreshOnEvent is off
  });

  test('a redelivered event is ignored', () {
    for (final event in <LimeniaEvent>[
      decided(suspend(t0, t1)),
      statusChanged(active, t2),
      decided(warn(t2.add(_s))),
    ]) {
      expect(watcher.handleEvent(event), isTrue);
      expect(watcher.handleEvent(event), isFalse);
    }
    expect(changes, [suspendedUntil(t1), active, warned]);
  });

  group('events out of order', () {
    // Limenia applied the events of each test in the order written. The
    // watcher must end with the same status whichever arrives first.
    for (final first in ['older', 'newer']) {
      List<T> arrive<T>(List<T> events) => first == 'older' ? events : events.reversed.toList();

      test('a ban and a later warning leave the user banned, $first first', () {
        for (final d in arrive([ban(t1), warn(t2)])) {
          expect(watcher.handleDecision(d), isTrue);
        }
        expect(watcher.current, banned);
        expect(watcher.isRestricted, isTrue);
      });

      test('a restore and a later warning leave a banned user warned, $first first', () async {
        transport.statusAnswers.add(banned);
        await watcher.refresh();
        for (final d in arrive([restore(t1), warn(t2)])) {
          expect(watcher.handleDecision(d), isTrue);
        }
        expect(watcher.current, warned);
        expect(watcher.isRestricted, isFalse);
      });

      test('a lift and a later warning leave the user warned, $first first', () async {
        transport.statusAnswers.add(suspendedUntil(t0)); // ended, Limenia has not lifted it yet
        await watcher.refresh();
        for (final e in arrive<LimeniaEvent>([statusChanged(active, t1), decided(warn(t2))])) {
          expect(watcher.handleEvent(e), isTrue);
        }
        expect(watcher.current, warned);
      });

      test('a warning older than a later restore does not warn, $first first', () async {
        transport.statusAnswers.add(banned);
        await watcher.refresh();
        final applied = [
          for (final d in arrive([warn(t1), restore(t2)])) watcher.handleDecision(d)
        ];
        expect(applied, first == 'older' ? [true, true] : [true, false]);
        expect(watcher.current, active);
      });

      test('a warning after the end of a suspension leaves the user warned, $first first', () {
        // As in Limenia (API 0.13.2), the ended suspension counts as lifted.
        final t3 = t2.add(_s);
        clock.now = t3;
        for (final d in arrive([suspend(t1, t2), warn(t3)])) {
          expect(watcher.handleDecision(d), isTrue);
        }
        expect(watcher.current, warned);
      });

      test('a warning during a suspension keeps it, $first first', () {
        final t3 = t2.add(_s);
        clock.now = t2;
        for (final d in arrive([suspend(t1, t3), warn(t2)])) {
          expect(watcher.handleDecision(d), isTrue);
        }
        expect(watcher.current, suspendedUntil(t3));
        clock.now = t3;
        expect(watcher.current, active);
      });
    }
  });

  group('a warning after the end of a suspension, before Limenia lifted it', () {
    // From API 0.13.2 Limenia lifts the suspension with the warning and sends
    // subject.status_changed with the status after it, stamped with the time
    // of the decision.
    setUp(() async {
      transport.statusAnswers.add(suspendedUntil(t1));
      await watcher.refresh();
      clock.now = t2;
    });

    test('decision.created first', () {
      expect(watcher.handleEvent(decided(warn(t2))), isTrue);
      expect(watcher.current, warned);
      expect(watcher.handleEvent(statusChanged(warned, t2)), isTrue);
      expect(watcher.current, warned);
      expect(changes, [suspendedUntil(t1), warned]);
    });

    test('subject.status_changed first', () {
      expect(watcher.handleEvent(statusChanged(warned, t2)), isTrue);
      expect(watcher.handleEvent(decided(warn(t2))), isFalse);
      expect(watcher.current, warned);
      expect(changes, [suspendedUntil(t1), warned]);
    });

    test('without subject.status_changed', () {
      expect(watcher.handleDecision(warn(t2)), isTrue);
      expect(watcher.current, warned);
      expect(watcher.isRestricted, isFalse);
    });

    for (final banFirst in [false, true]) {
      test('a later ban wins over warning and lift, ${banFirst ? 'the ban' : 'the lift'} first', () {
        final t3 = t2.add(_s);
        final events = <LimeniaEvent>[statusChanged(warned, t2), decided(warn(t2)), decided(ban(t3))];
        final applied = [for (final e in banFirst ? events.reversed : events) watcher.handleEvent(e)];
        expect(applied, banFirst ? [true, false, false] : [true, false, true]);
        expect(watcher.current, banned);
      });
    }
  });

  test('ignores a restore of the content', () async {
    transport.statusAnswers.add(banned);
    await watcher.refresh();
    final contentOnly = decision(action: 'restore', userId: 'u', decidedAt: t1, restoreScope: 'content');
    expect(contentOnly.changesUserStatus, isFalse);
    expect(watcher.handleDecision(contentOnly), isFalse);
    expect(watcher.handleEvent(decided(contentOnly)), isFalse);
    expect(watcher.current, banned);
    expect(watcher.isRestricted, isTrue);
    // It was not applied, so it does not make an older restore of the account look old.
    expect(watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t0, restoreScope: 'account')),
        isTrue);
    expect(watcher.current, active);
    expect(changes, [banned, active]);
  });

  test('ignores subject.status_changed for another user', () {
    expect(watcher.handleEvent(statusChanged(const SubjectStatus.active('other'), t2)), isFalse);
    expect(watcher.current, isNull);
    // It moved no watermark: an older ban of this user still applies.
    expect(watcher.handleDecision(ban(t1)), isTrue);
    expect(changes, [banned]);
  });

  test('handleEvent takes decisions and status changes', () {
    final event = DecisionCreatedEvent(
      id: 'e1',
      createdAt: t0,
      appId: 'a',
      appSlug: 's',
      decision: decision(action: 'ban_user', userId: 'u', decidedAt: t0),
    );
    expect(watcher.handleEvent(event), isTrue);
    final lifted =
        SubjectStatusChangedEvent(id: 'e2', createdAt: t0.add(_s), appId: 'a', appSlug: 's', subject: active);
    expect(watcher.handleEvent(lifted), isTrue);
    expect(watcher.handleEvent(TestPingEvent(id: 'e3', createdAt: t0.add(_s * 2), appId: 'a', appSlug: 's')), isFalse);
    expect(changes, [banned, active]);
  });

  test('a warning keeps a suspension that is known', () async {
    final until = t0.add(const Duration(days: 1));
    transport.statusAnswers.add(suspendedUntil(until));
    await watcher.refresh();
    expect(watcher.handleDecision(decision(action: 'warn_user', userId: 'u', decidedAt: t0)), isTrue);
    expect(watcher.current, suspendedUntil(until));
  });

  group('refreshOnEvent', () {
    late List<Object> errors;

    setUp(() {
      errors = [];
      watcher.dispose();
      watcher = SubjectStatusWatcher(
        transport: transport,
        externalUserId: 'u',
        now: clock.call,
        createTimer: timers.create,
        onRefreshError: (e, _) => errors.add(e),
      );
      changes = [];
      watcher.changes.listen(changes.add);
    });

    test('reconciles with Limenia after an event', () async {
      transport.statusAnswers.add(banned);
      watcher.handleDecision(decision(action: 'warn_user', userId: 'u', decidedAt: t0));
      await pumpEventQueue();
      expect(transport.statusCalls, ['u']);
      expect(changes.map((s) => s.status), [SanctionStatus.warned, SanctionStatus.banned]);
    });

    test('a decision about a review request starts no refresh', () async {
      expect(watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t0, reviewId: 'r')), isFalse);
      await pumpEventQueue();
      expect(transport.statusCalls, isEmpty);
      expect(changes, isEmpty);
    });

    test('a restore of the content starts no refresh, one with an unknown scope asks Limenia', () async {
      transport.statusAnswers.add(banned);
      expect(
        watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t0, restoreScope: 'content')),
        isFalse,
      );
      await pumpEventQueue();
      expect(transport.statusCalls, isEmpty);

      // A scope of a later version of Limenia may lift the account or not.
      expect(
        watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t1, restoreScope: 'profile')),
        isFalse,
      );
      await pumpEventQueue();
      expect(transport.statusCalls, ['u']);
      expect(watcher.current, banned);

      // Not about this user or about a review request: nothing to ask.
      expect(
        watcher.handleDecision(decision(action: 'restore', userId: 'other', decidedAt: t2, restoreScope: 'profile')),
        isFalse,
      );
      expect(
        watcher.handleDecision(
            decision(action: 'restore', userId: 'u', decidedAt: t2, restoreScope: 'profile', reviewId: 'r')),
        isFalse,
      );
      await pumpEventQueue();
      expect(transport.statusCalls, ['u']);
      expect(errors, isEmpty);
    });

    test('a refresh started before an event does not overwrite it', () async {
      final stale = Completer<SubjectStatus>();
      transport.statusAnswers.addAll([stale, active]);
      final before = watcher.refresh();
      watcher.handleDecision(decision(action: 'ban_user', userId: 'u', decidedAt: t0));
      await pumpEventQueue(); // the refresh after the event says active
      stale.complete(banned); // the older answer arrives last
      await before;
      expect(watcher.current, active);
      expect(changes, [banned, active]);
    });

    test('reports errors of its own refreshes', () async {
      transport.statusAnswers.add(const NetworkException());
      watcher.handleDecision(decision(action: 'ban_user', userId: 'u', decidedAt: t0));
      await pumpEventQueue();
      expect(errors.single, isA<NetworkException>());
      expect(watcher.current, banned);
    });

    test('an event older than the last status asks Limenia', () async {
      transport.statusAnswers.addAll([active, banned]);
      expect(watcher.handleEvent(statusChanged(active, t2)), isTrue);
      await pumpEventQueue();
      // The ban has the older time, but Limenia may have stored it after the lift.
      expect(watcher.handleDecision(ban(t1)), isFalse);
      expect(watcher.current, active);
      await pumpEventQueue();
      expect(transport.statusCalls, ['u', 'u']);
      expect(watcher.current, banned);
      expect(errors, isEmpty);
    });

    test('a redelivered event does not ask Limenia again', () async {
      transport.statusAnswers.addAll([suspendedUntil(t1), active, warned]);
      for (final event in <LimeniaEvent>[
        decided(suspend(t0, t1)),
        statusChanged(active, t2),
        decided(warn(t2.add(_s))),
      ]) {
        expect(watcher.handleEvent(event), isTrue);
        await pumpEventQueue();
        expect(watcher.handleEvent(event), isFalse);
        await pumpEventQueue();
      }
      expect(transport.statusCalls, ['u', 'u', 'u']);
      expect(errors, isEmpty);
    });

    test('a decision with an unknown action asks Limenia', () async {
      transport.statusAnswers.addAll([banned, active]);
      expect(watcher.handleDecision(unknown(t2)), isFalse);
      await pumpEventQueue();
      expect(transport.statusCalls, ['u']);
      expect(watcher.current, banned);

      // Not about this user, about a review request, or known to keep the
      // status: nothing to ask.
      expect(watcher.handleDecision(unknown(t2, userId: 'other')), isFalse);
      expect(watcher.handleDecision(unknown(t2, reviewId: '01K6T2R0000000000000000000')), isFalse);
      expect(watcher.handleDecision(decision(action: 'remove_content', userId: 'u', decidedAt: t2)), isFalse);
      await pumpEventQueue();
      expect(transport.statusCalls, ['u']);

      // It moved no watermark: an older restore still applies, and not as a warning.
      expect(watcher.handleDecision(restore(t1)), isTrue);
      expect(watcher.current, active);
      await pumpEventQueue();
      expect(transport.statusCalls, ['u', 'u']);
      expect(errors, isEmpty);
    });

    test('handleEvent after dispose ignores other events and throws for this user', () async {
      watcher.dispose();
      expect(watcher.handleEvent(TestPingEvent(id: 'e1', createdAt: t0, appId: 'a', appSlug: 's')), isFalse);
      expect(watcher.handleEvent(statusChanged(const SubjectStatus.active('other'), t0)), isFalse);
      expect(watcher.handleEvent(decided(decision(action: 'remove_content', userId: 'u', decidedAt: t0))), isFalse);
      expect(watcher.handleEvent(decided(unknown(t0))), isFalse);
      expect(() => watcher.handleEvent(decided(ban(t0))), throwsStateError);
      expect(() => watcher.handleEvent(decided(warn(t0))), throwsStateError);
      expect(() => watcher.handleEvent(statusChanged(active, t0)), throwsStateError);
      await pumpEventQueue();
      expect(transport.statusCalls, isEmpty);
      expect(errors, isEmpty);
    });
  });

  test('tryRefresh reports errors instead of throwing', () async {
    final errors = <Object>[];
    final quiet =
        SubjectStatusWatcher(transport: transport, externalUserId: 'u', onRefreshError: (e, _) => errors.add(e));
    transport.statusAnswers.addAll([const NetworkException(), banned]);
    expect(await quiet.tryRefresh(), isNull);
    expect(errors.single, isA<NetworkException>());
    expect(await quiet.tryRefresh(), banned);
    quiet.dispose();
    expect(await quiet.tryRefresh(), isNull);
  });

  test('stream starts with the current status', () async {
    transport.statusAnswers.add(banned);
    await watcher.refresh();
    final seen = <SubjectStatus>[];
    final sub = watcher.stream.listen(seen.add);
    watcher.handleDecision(decision(action: 'restore', userId: 'u', decidedAt: t0));
    await pumpEventQueue();
    expect(seen, [banned, active]);
    await sub.cancel();
  });

  test('dispose closes the streams and stops the timer', () async {
    transport.statusAnswers.add(suspendedUntil(t0.add(const Duration(hours: 1))));
    await watcher.refresh();
    final done = watcher.stream.toList();
    watcher.dispose();
    expect(timers.active, isEmpty);
    expect(await done, hasLength(1));
    expect(() => watcher.refresh(), throwsStateError);
  });
}

const _s = Duration(seconds: 1);
