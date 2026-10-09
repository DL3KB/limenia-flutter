import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

import 'support/harness.dart';

final now = DateTime(2026, 10, 7, 12);

SubjectStatus status(SanctionStatus status, {DateTime? until}) =>
    SubjectStatus(externalUserId: 'u_112', status: status, suspendedUntil: until);

/// A transport for a watcher that never calls it (`refreshOnEvent: false`).
class _NoTransport implements LimeniaTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Color? bannerColor(WidgetTester tester) => tester
    .widgetList<Material>(find.descendant(of: find.byType(LimeniaRestrictionNotice), matching: find.byType(Material)))
    .first
    .color;

void main() {
  group('LimeniaRestrictionNotice', () {
    testWidgets('shows nothing for an active user', (tester) async {
      await pumpApp(tester, LimeniaRestrictionNotice(status: const SubjectStatus.active('u_112'), now: () => now));
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('warned: a soft banner', (tester) async {
      await pumpApp(tester, LimeniaRestrictionNotice(status: status(SanctionStatus.warned), now: () => now));
      expect(findInLiveRegion('Verwarnung'), findsOneWidget);
      expect(find.text('Du hast eine Verwarnung erhalten. Dein Konto kannst du weiter nutzen.'), findsOneWidget);
      final context = tester.element(find.byType(LimeniaRestrictionNotice));
      expect(bannerColor(tester), Theme.of(context).colorScheme.secondaryContainer);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('suspended: a prominent notice with the end in local time', (tester) async {
      await pumpApp(
        tester,
        LimeniaRestrictionNotice(
          status: status(SanctionStatus.suspended, until: DateTime(2026, 10, 14, 14, 30)),
          now: () => now,
        ),
      );
      expect(find.text('Konto vorübergehend gesperrt'), findsOneWidget);
      expect(find.text('Dein Konto ist bis zum 14.10.2026 14:30 gesperrt.'), findsOneWidget);
      final context = tester.element(find.byType(LimeniaRestrictionNotice));
      expect(bannerColor(tester), Theme.of(context).colorScheme.errorContainer);
    });

    testWidgets('suspended in English', (tester) async {
      await pumpApp(
        tester,
        LimeniaRestrictionNotice(
          status: status(SanctionStatus.suspended, until: DateTime(2026, 10, 14, 14, 30)),
          now: () => now,
        ),
        locale: english,
      );
      expect(find.text('Account temporarily suspended'), findsOneWidget);
      expect(find.text('Your account is suspended until Oct 14, 2026, 14:30.'), findsOneWidget);
    });

    testWidgets('a suspension that has ended shows nothing', (tester) async {
      await pumpApp(
        tester,
        LimeniaRestrictionNotice(
          status: status(SanctionStatus.suspended, until: now.subtract(const Duration(minutes: 1))),
          now: () => now,
        ),
      );
      expect(find.text('Konto vorübergehend gesperrt'), findsNothing);

      await pumpApp(
        tester,
        LimeniaRestrictionNotice(status: status(SanctionStatus.suspended, until: now), now: () => now),
      );
      expect(find.text('Konto vorübergehend gesperrt'), findsNothing);
    });

    testWidgets('disappears by itself when the suspension ends', (tester) async {
      var clock = now;
      await pumpApp(
        tester,
        LimeniaRestrictionNotice(
          status: status(SanctionStatus.suspended, until: now.add(const Duration(hours: 1))),
          now: () => clock,
        ),
      );
      expect(find.text('Konto vorübergehend gesperrt'), findsOneWidget);

      clock = now.add(const Duration(minutes: 59));
      await tester.pump(const Duration(minutes: 59));
      expect(find.text('Konto vorübergehend gesperrt'), findsOneWidget);

      clock = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Konto vorübergehend gesperrt'), findsNothing);
    });

    testWidgets('a long suspension waits in steps of at most a day', (tester) async {
      var clock = now;
      await pumpApp(
        tester,
        LimeniaRestrictionNotice(
          status: status(SanctionStatus.suspended, until: now.add(const Duration(days: 3))),
          now: () => clock,
        ),
      );
      for (var day = 1; day < 3; day++) {
        clock = now.add(Duration(days: day));
        await tester.pump(const Duration(days: 1));
        expect(find.text('Konto vorübergehend gesperrt'), findsOneWidget);
      }
      clock = now.add(const Duration(days: 3));
      await tester.pump(const Duration(days: 1));
      expect(find.text('Konto vorübergehend gesperrt'), findsNothing);
    });

    testWidgets('banned: a prominent notice', (tester) async {
      await pumpApp(tester, LimeniaRestrictionNotice(status: status(SanctionStatus.banned), now: () => now));
      expect(find.text('Konto dauerhaft gesperrt'), findsOneWidget);
      expect(find.text('Dein Konto wurde dauerhaft gesperrt.'), findsOneWidget);
    });

    testWidgets('buttons for the reasons and a complaint', (tester) async {
      final taps = <String>[];
      await pumpApp(
        tester,
        LimeniaRestrictionNotice(
          status: status(SanctionStatus.banned),
          now: () => now,
          onShowReasons: () => taps.add('reasons'),
          onAppeal: () => taps.add('appeal'),
        ),
      );
      await tester.tap(find.text('Begründung ansehen'));
      await tester.tap(find.text('Beschwerde einreichen'));
      expect(taps, ['reasons', 'appeal']);
    });

    testWidgets('a suspension without an end', (tester) async {
      await pumpApp(tester, LimeniaRestrictionNotice(status: status(SanctionStatus.suspended), now: () => now));
      expect(find.text('Dein Konto ist vorübergehend gesperrt.'), findsOneWidget);
    });
  });

  group('LimeniaRestrictionScreen', () {
    testWidgets('suspended: title, end, buttons and footer', (tester) async {
      final taps = <String>[];
      await pumpApp(
        tester,
        LimeniaRestrictionScreen(
          status: status(SanctionStatus.suspended, until: DateTime(2026, 10, 14, 14, 30)),
          now: () => now,
          onShowReasons: () => taps.add('reasons'),
          onAppeal: () => taps.add('appeal'),
          footer: TextButton(onPressed: () => taps.add('logout'), child: const Text('Abmelden')),
        ),
        scroll: false,
      );
      expect(findInLiveRegion('Konto vorübergehend gesperrt'), findsOneWidget);
      expect(find.text('Dein Konto ist bis zum 14.10.2026 14:30 gesperrt.'), findsOneWidget);
      await tester.tap(find.text('Begründung ansehen'));
      await tester.tap(find.text('Beschwerde einreichen'));
      await tester.tap(find.text('Abmelden'));
      expect(taps, ['reasons', 'appeal', 'logout']);
    });

    testWidgets('banned in English', (tester) async {
      await pumpApp(
        tester,
        LimeniaRestrictionScreen(status: status(SanctionStatus.banned), now: () => now, onAppeal: () {}),
        locale: english,
        scroll: false,
      );
      expect(find.text('Account permanently suspended'), findsOneWidget);
      expect(find.text('Your account has been permanently suspended.'), findsOneWidget);
      expect(find.text('Submit a complaint'), findsOneWidget);
      expect(find.text('Show reasons'), findsNothing);
    });

    testWidgets('shows nothing for active, warned and an ended suspension', (tester) async {
      for (final s in [
        const SubjectStatus.active('u_112'),
        status(SanctionStatus.warned),
        status(SanctionStatus.suspended, until: now.subtract(const Duration(seconds: 1))),
      ]) {
        await pumpApp(tester, LimeniaRestrictionScreen(status: s, now: () => now), scroll: false);
        expect(find.byType(Icon), findsNothing, reason: '$s');
        expect(find.byType(Text), findsNothing, reason: '$s');
      }
    });
  });

  group('LimeniaSubjectStatusBuilder', () {
    testWidgets('builds with the current status of the watcher and again on changes', (tester) async {
      final watcher = SubjectStatusWatcher(
        transport: _NoTransport(),
        externalUserId: 'u_112',
        refreshOnEvent: false,
        now: () => now,
      );
      addTearDown(watcher.dispose);
      final seen = <SubjectStatus?>[];
      await pumpApp(
        tester,
        LimeniaSubjectStatusBuilder(
          watcher: watcher,
          builder: (context, status) {
            seen.add(status);
            return status == null ? const Text('unknown') : LimeniaRestrictionNotice(status: status, now: () => now);
          },
        ),
      );
      expect(find.text('unknown'), findsOneWidget);

      watcher.handleDecision(decision(action: 'ban_user', decidedAt: now.toUtc()));
      await tester.pump();
      expect(find.text('Konto dauerhaft gesperrt'), findsOneWidget);
      expect(seen.last?.status, SanctionStatus.banned);
    });

    testWidgets('follows a new watcher', (tester) async {
      SubjectStatusWatcher newWatcher() => SubjectStatusWatcher(
            transport: _NoTransport(),
            externalUserId: 'u_112',
            refreshOnEvent: false,
            now: () => now,
          );
      final first = newWatcher();
      final second = newWatcher();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget build(SubjectStatusWatcher watcher) => LimeniaSubjectStatusBuilder(
            watcher: watcher,
            builder: (context, status) => Text(status?.status.name ?? 'unknown'),
          );

      await pumpApp(tester, build(first));
      await pumpApp(tester, build(second));
      first.handleDecision(decision(action: 'ban_user', decidedAt: now.toUtc()));
      await tester.pump();
      expect(find.text('unknown'), findsOneWidget);
      second.handleDecision(decision(action: 'warn_user', decidedAt: now.toUtc()));
      await tester.pump();
      expect(find.text('warned'), findsOneWidget);
    });
  });

  group('large text and accessibility', () {
    for (final s in [
      status(SanctionStatus.warned),
      status(SanctionStatus.suspended, until: DateTime(2026, 12, 24, 18)),
      status(SanctionStatus.banned),
    ]) {
      testWidgets('text scale 2.0 without overflow, ${s.status.name}', (tester) async {
        await pumpApp(
          tester,
          Column(
            children: [
              LimeniaRestrictionNotice(status: s, now: () => now, onShowReasons: () {}, onAppeal: () {}),
              SizedBox(
                height: 600,
                child: LimeniaRestrictionScreen(
                  status: s,
                  now: () => now,
                  onShowReasons: () {},
                  onAppeal: () {},
                  footer: OutlinedButton(onPressed: () {}, child: const Text('Abmelden')),
                ),
              ),
            ],
          ),
          textScale: 2,
          size: smallPhone,
        );
        expect(tester.takeException(), isNull);
      });

      for (final brightness in Brightness.values) {
        testWidgets('meets the accessibility guidelines, ${s.status.name}, ${brightness.name}', (tester) async {
          await pumpApp(
            tester,
            LimeniaRestrictionNotice(status: s, now: () => now, onShowReasons: () {}, onAppeal: () {}),
            brightness: brightness,
          );
          await expectAccessible(tester);
          await pumpApp(
            tester,
            LimeniaRestrictionScreen(status: s, now: () => now, onShowReasons: () {}, onAppeal: () {}),
            brightness: brightness,
            scroll: false,
          );
          await expectAccessible(tester);
        });
      }
    }
  });
}
