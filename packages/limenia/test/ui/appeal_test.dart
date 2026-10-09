import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

import 'support/harness.dart';

AppealSent sent() => const AppealSent('key', AppealReceipt(appealId: 'app_1', status: AppealStatus.open));

AppealQueued queued() => AppealQueued('key', Exception('offline'));

AppealFailed refused(String code, {int status = 409, DateTime? suspendedUntil}) =>
    AppealFailed('key', LimeniaException(status, code: code, suspendedUntil: suspendedUntil));

AppealExpired expired() => AppealExpired('key', DateTime(2026, 9, 1));

/// Records the texts and answers with [results] in turn (the last one
/// repeats).
class FakeSubmit {
  FakeSubmit(this.results);

  final List<FutureOr<AppealResult> Function()> results;
  final texts = <String>[];

  Future<AppealResult> call(String text) async {
    texts.add(text);
    return results[texts.length > results.length ? results.length - 1 : texts.length - 1]();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> writeAndSend(WidgetTester tester, [String text = 'Das war ein Zitat aus einem Film.']) async {
  await typeText(tester, text);
  await tapVisible(tester, find.byType(FilledButton));
}

void main() {
  group('LimeniaAppealForm', () {
    testWidgets('shows the German texts, the topic of a decision and the deadline', (tester) async {
      await pumpApp(
        tester,
        LimeniaAppealForm(
          onSubmit: FakeSubmit([sent]).call,
          topic: AppealTopic.fromDecision(decision(decidedAt: DateTime.utc(2026, 10, 7, 12))),
        ),
      );
      expect(find.text('Beschwerde einreichen'), findsOneWidget);
      expect(find.text('Entscheidung'), findsOneWidget);
      expect(find.text('Entfernung des Inhalts'), findsOneWidget);
      expect(find.text('Belästigung und Hassrede'), findsOneWidget);
      expect(find.text('Entschieden am 07.10.2026'), findsOneWidget);
      expect(find.text(LimeniaUiStrings.de.appealInfo), findsOneWidget);
      expect(find.text('Du kannst dich bis zum 07.04.2027 beschweren.'), findsOneWidget);
      expect(find.text('Deine Begründung'), findsOneWidget);
      expect(find.text('0 / 5000'), findsOneWidget);
      expect(find.text('Beschwerde senden'), findsOneWidget);
    });

    testWidgets('shows the English texts', (tester) async {
      await pumpApp(
        tester,
        LimeniaAppealForm(
          onSubmit: FakeSubmit([sent]).call,
          topic: AppealTopic.fromDecision(decision(action: 'suspend_user', decidedAt: DateTime.utc(2026, 8, 31, 12))),
        ),
        locale: english,
      );
      expect(find.text('Submit a complaint'), findsOneWidget);
      expect(find.text('Temporary suspension of the account'), findsOneWidget);
      expect(find.text('Decided on Aug 31, 2026'), findsOneWidget);
      expect(find.text('You can complain until Feb 28, 2027.'), findsOneWidget);
      expect(find.text(LimeniaUiStrings.en.appealInfo), findsOneWidget);
      expect(find.text('Send complaint'), findsOneWidget);
    });

    testWidgets('a reporter sees the deadline Limenia sent', (tester) async {
      final resolution = ReportsResolution(
        decisionId: '01K6G5H1TR8W4QZ3M0XCB7NDEC',
        actionName: 'dismiss',
        policies: const [],
        decidedAt: DateTime.utc(2026, 10, 1, 12),
        appealDeadline: DateTime.utc(2027, 3, 30, 12),
        reports: const [],
      );
      await pumpApp(
        tester,
        LimeniaAppealForm(
          onSubmit: FakeSubmit([sent]).call,
          topic: AppealTopic.fromReportsResolution(resolution, title: 'Deine Meldung vom 1. Oktober'),
        ),
      );
      expect(find.text('Deine Meldung vom 1. Oktober'), findsOneWidget);
      expect(find.text('Keine Maßnahme, es wurde kein Verstoß festgestellt'), findsOneWidget);
      expect(find.text('Du kannst dich bis zum 30.03.2027 beschweren.'), findsOneWidget);
    });

    testWidgets('a plain title without a date, and no topic at all', (tester) async {
      await pumpApp(
        tester,
        LimeniaAppealForm(onSubmit: FakeSubmit([sent]).call, topic: const AppealTopic(title: 'Dein Foto')),
      );
      expect(find.text('Dein Foto'), findsOneWidget);
      expect(find.textContaining('bis zum'), findsNothing);

      await pumpApp(tester, LimeniaAppealForm(onSubmit: FakeSubmit([sent]).call));
      expect(find.text('Entscheidung'), findsNothing);
      expect(find.text(LimeniaUiStrings.de.appealInfo), findsOneWidget);
    });

    test('AppealTopic.deadline', () {
      expect(const AppealTopic().deadline, isNull);
      expect(AppealTopic(decidedAt: DateTime.utc(2026, 8, 31)).deadline, DateTime.utc(2027, 2, 28));
      expect(
        AppealTopic(decidedAt: DateTime.utc(2026, 8, 31), appealDeadline: DateTime.utc(2027, 3, 1)).deadline,
        DateTime.utc(2027, 3, 1),
      );
    });

    testWidgets('requires a text, also not only white space', (tester) async {
      final submit = FakeSubmit([sent]);
      await pumpApp(tester, LimeniaAppealForm(onSubmit: submit.call));
      expect(find.text('Bitte schreib kurz, warum du dich beschwerst.'), findsNothing);
      await tapVisible(tester, find.byType(FilledButton));
      expect(submit.texts, isEmpty);
      expect(find.text('Bitte schreib kurz, warum du dich beschwerst.'), findsOneWidget);

      await writeAndSend(tester, ' \n\t ');
      expect(submit.texts, isEmpty);
    });

    testWidgets('sends the text as entered, shows the progress and then the receipt', (tester) async {
      final answer = Completer<AppealResult>();
      final submit = FakeSubmit([() => answer.future]);
      final results = <AppealResult>[];
      await pumpApp(tester, LimeniaAppealForm(onSubmit: submit.call, onResult: results.add));
      await typeText(tester, ' Das war ein Zitat. ');
      expect(find.text('20 / 5000'), findsOneWidget);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(submit.texts, [' Das war ein Zitat. ']);
      expect(find.text('Wird gesendet …'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      answer.complete(sent());
      await tester.pumpAndSettle();
      expect(findInLiveRegion('Beschwerde eingegangen'), findsOneWidget);
      expect(find.text('Ein Mensch prüft deine Beschwerde, und du bekommst eine Antwort.'), findsOneWidget);
      expect(results.single, isA<AppealSent>());
    });

    testWidgets('counts like Limenia and blocks more than 5000 characters', (tester) async {
      final submit = FakeSubmit([sent]);
      await pumpApp(tester, LimeniaAppealForm(onSubmit: submit.call));
      await writeAndSend(tester, '\u{1F600}' * 5001);
      expect(find.text('5001 / 5000'), findsOneWidget);
      expect(find.text('Bitte kürze deinen Text auf höchstens 5000 Zeichen.'), findsOneWidget);
      expect(submit.texts, isEmpty);

      await writeAndSend(tester, '\u{1F600}' * 5000);
      expect(submit.texts.single.runes.length, AppealLimits.textLength);
    });

    testWidgets('queued: will be sent when online, no retry', (tester) async {
      await pumpApp(tester, LimeniaAppealForm(onSubmit: FakeSubmit([queued]).call));
      await writeAndSend(tester);
      expect(findInLiveRegion('Beschwerde gespeichert'), findsOneWidget);
      expect(find.text('Wir senden sie, sobald du wieder online bist.'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsNothing);
    });

    testWidgets('failed: a retry sends the same text again', (tester) async {
      final submit = FakeSubmit([() => refused('validation_failed', status: 400), sent]);
      await pumpApp(tester, LimeniaAppealForm(onSubmit: submit.call));
      await writeAndSend(tester, 'Mein Grund');
      expect(find.text('Beschwerde nicht gesendet'), findsOneWidget);
      expect(find.text('Das hat leider nicht geklappt. Versuch es bitte noch einmal.'), findsOneWidget);
      await tapVisible(tester, find.text('Erneut versuchen'));
      expect(submit.texts, ['Mein Grund', 'Mein Grund']);
      expect(find.text('Beschwerde eingegangen'), findsOneWidget);
    });

    testWidgets('expired: offers a retry', (tester) async {
      await pumpApp(tester, LimeniaAppealForm(onSubmit: FakeSubmit([expired]).call));
      await writeAndSend(tester);
      expect(find.text(LimeniaUiStrings.de.appealExpiredMessage), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('an error of the callback shows a failure and is reported', (tester) async {
      await pumpApp(tester, LimeniaAppealForm(onSubmit: FakeSubmit([() => throw TimeoutException('slow')]).call));
      await writeAndSend(tester);
      expect(tester.takeException(), isA<TimeoutException>());
      expect(find.text('Beschwerde nicht gesendet'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    for (final (code, message) in [
      ('appeal_window_closed', LimeniaUiStrings.de.appealWindowClosed),
      ('appeal_already_open', LimeniaUiStrings.de.appealAlreadyOpen),
      ('appeal_not_allowed', LimeniaUiStrings.de.appealNotAllowed),
    ]) {
      testWidgets('$code: explains it, no retry', (tester) async {
        await pumpApp(tester, LimeniaAppealForm(onSubmit: FakeSubmit([() => refused(code)]).call));
        await writeAndSend(tester);
        expect(findInLiveRegion('Beschwerde nicht gesendet'), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(find.text('Erneut versuchen'), findsNothing);
      });
    }

    testWidgets('reporter suspended: shows the end, no retry', (tester) async {
      await pumpApp(
        tester,
        LimeniaAppealForm(
          onSubmit: FakeSubmit([
            () => refused('reporter_suspended', status: 403, suspendedUntil: DateTime(2026, 11, 2, 9, 5)),
          ]).call,
        ),
        locale: english,
      );
      await writeAndSend(tester);
      expect(find.text('You cannot submit complaints as a reporter until Nov 2, 2026, 09:05.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('showLimeniaAppealSheet', () {
    testWidgets('completes with the result after closing', (tester) async {
      Future<AppealResult?>? result;
      await pumpLauncher(
        tester,
        (context) => result = showLimeniaAppealSheet(
          context,
          onSubmit: FakeSubmit([queued]).call,
          topic: AppealTopic.fromDecision(decision()),
        ),
      );
      expect(find.text('Entfernung des Inhalts'), findsOneWidget);
      await writeAndSend(tester);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Schließen'));
      expect(await result, isA<AppealQueued>());
    });

    testWidgets('completes with null when closed at once', (tester) async {
      Future<AppealResult?>? result;
      await pumpLauncher(
        tester,
        (context) => result = showLimeniaAppealSheet(context, onSubmit: FakeSubmit([sent]).call, title: 'Widerspruch'),
      );
      expect(find.text('Widerspruch'), findsOneWidget);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('large text and accessibility', () {
    for (final size in [smallPhone, phone]) {
      for (final brightness in Brightness.values) {
        testWidgets('text scale 2.0 without overflow, ${size.width.toInt()} wide, ${brightness.name}', (tester) async {
          await pumpLauncher(
            tester,
            (context) => showLimeniaAppealSheet(
              context,
              onSubmit: FakeSubmit([() => refused('appeal_already_open')]).call,
              topic:
                  AppealTopic.fromDecision(decision(action: 'restrict_content'), title: 'Dein Kommentar zu „Sommer“'),
            ),
            textScale: 2,
            size: size,
            brightness: brightness,
          );
          await tapVisible(tester, find.byType(FilledButton));
          await writeAndSend(tester, 'Begründung ' * 80);
          expect(find.text(LimeniaUiStrings.de.appealAlreadyOpen), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('meets the accessibility guidelines, ${brightness.name}', (tester) async {
        await pumpApp(
          tester,
          LimeniaAppealForm(
            onSubmit: FakeSubmit([sent]).call,
            topic: AppealTopic.fromDecision(decision()),
            onClose: () {},
          ),
          brightness: brightness,
        );
        await expectAccessible(tester);
        await writeAndSend(tester);
        await expectAccessible(tester);
      });
    }
  });
}
