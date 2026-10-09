import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

import 'support/harness.dart';

ReportSent sent({ReporterWarning? warning}) => ReportSent(
      'key',
      ReportReceipt(reportId: 'rep_1', caseId: 'case_1', caseCreated: true, reporterWarning: warning),
    );

ReportQueued queued() => ReportQueued('key', Exception('offline'));

ReportFailed failed() => const ReportFailed('key', LimeniaException(400, code: 'validation_failed'));

ReportFailed reporterSuspended(DateTime? until) =>
    ReportFailed('key', LimeniaException(403, code: 'reporter_suspended', suspendedUntil: until));

ReportExpired expired() => ReportExpired('key', DateTime(2026, 9, 1));

/// Records the drafts and answers with [results] in turn (the last one
/// repeats).
class FakeSubmit {
  FakeSubmit(this.results);

  final List<FutureOr<ReportResult> Function()> results;
  final drafts = <ReportDraft>[];

  Future<ReportResult> call(ReportDraft draft) async {
    drafts.add(draft);
    return results[drafts.length > results.length ? results.length - 1 : drafts.length - 1]();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Enters [text] and leaves the field, so that the caret no longer keeps the
/// field on screen.
Future<void> typeText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> chooseAndSend(WidgetTester tester, {String category = 'Spam', String? text}) async {
  await tapVisible(tester, find.text(category));
  if (text != null) await typeText(tester, text);
  await tapVisible(tester, find.byType(FilledButton));
}

void main() {
  group('LimeniaReportForm', () {
    testWidgets('shows the German texts and the default categories', (tester) async {
      await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([sent]).call));
      expect(find.text('Melden'), findsOneWidget);
      expect(find.text('Warum meldest du das?'), findsOneWidget);
      for (final label in LimeniaUiStrings.de.categoryLabels.values) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(RadioListTile<String>), findsNWidgets(ReasonCategory.defaults.length));
      expect(find.text('Details (optional)'), findsOneWidget);
      expect(find.text('0 / 2000'), findsOneWidget);
      expect(find.text('Meldung senden'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byTooltip('Schließen'), findsNothing);
    });

    testWidgets('shows the English texts', (tester) async {
      await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([sent]).call, onClose: () {}), locale: english);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Why are you reporting this?'), findsOneWidget);
      expect(find.text('Harassment and hate speech'), findsOneWidget);
      expect(find.text('Send report'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('asks for a category before it sends', (tester) async {
      final submit = FakeSubmit([sent]);
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call));
      await tapVisible(tester, find.text('Meldung senden'));
      expect(submit.drafts, isEmpty);
      expect(findInLiveRegion('Bitte wähle einen Grund aus.'), findsOneWidget);

      await chooseAndSend(tester);
      expect(submit.drafts, [const ReportDraft(reasonCategory: 'spam')]);
    });

    testWidgets('sends the draft, shows the progress and then the thanks', (tester) async {
      final answer = Completer<ReportResult>();
      final submit = FakeSubmit([() => answer.future]);
      final results = <ReportResult>[];
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call, onResult: results.add));

      await tapVisible(tester, find.text('Belästigung und Hassrede'));
      await typeText(tester, 'Beleidigt mich in jedem Kommentar');
      expect(find.text('33 / 2000'), findsOneWidget);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(submit.drafts, [
        const ReportDraft(reasonCategory: 'harassment_hate', reasonText: 'Beleidigt mich in jedem Kommentar'),
      ]);
      expect(find.text('Wird gesendet …'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      // A second tap while sending does nothing.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(submit.drafts, hasLength(1));

      answer.complete(sent());
      await tester.pumpAndSettle();
      expect(findInLiveRegion('Danke für deine Meldung'), findsOneWidget);
      expect(find.text('Wir sehen sie uns an.'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsNothing);
      expect(results.single, isA<ReportSent>());
    });

    testWidgets('sends a text of white space only as null', (tester) async {
      final submit = FakeSubmit([sent]);
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call));
      await chooseAndSend(tester, category: 'Sonstiges', text: '  \n ');
      expect(submit.drafts.single.reasonText, isNull);
    });

    testWidgets('queued: will be sent when online, no retry', (tester) async {
      await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([queued]).call));
      await chooseAndSend(tester);
      expect(findInLiveRegion('Meldung gespeichert'), findsOneWidget);
      expect(find.text('Wir senden sie, sobald du wieder online bist.'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsNothing);
    });

    testWidgets('failed: offers a retry that sends the same draft again', (tester) async {
      final submit = FakeSubmit([failed, sent]);
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call));
      await chooseAndSend(tester, category: 'Betrug', text: 'Fake-Shop');
      expect(findInLiveRegion('Meldung nicht gesendet'), findsOneWidget);
      expect(find.text('Das hat leider nicht geklappt. Versuch es bitte noch einmal.'), findsOneWidget);

      await tapVisible(tester, find.text('Erneut versuchen'));
      expect(submit.drafts, hasLength(2));
      expect(submit.drafts[1], submit.drafts[0]);
      expect(find.text('Danke für deine Meldung'), findsOneWidget);
    });

    testWidgets('reporter suspended: shows the end, no retry', (tester) async {
      await pumpApp(
        tester,
        LimeniaReportForm(onSubmit: FakeSubmit([() => reporterSuspended(DateTime(2026, 10, 14, 14, 30))]).call),
      );
      await chooseAndSend(tester);
      expect(
        find.text('Wir bearbeiten deine Meldungen bis zum 14.10.2026 14:30 nicht, weil mehrere davon offensichtlich '
            'unbegründet waren.'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsNothing);
    });

    testWidgets('reporter suspended without an end', (tester) async {
      await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([() => reporterSuspended(null)]).call));
      await chooseAndSend(tester);
      expect(find.textContaining('zurzeit nicht'), findsOneWidget);
    });

    testWidgets('expired: asks to report again and offers a retry', (tester) async {
      await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([expired]).call));
      await chooseAndSend(tester);
      expect(
        find.text('Deine Meldung konnte nicht rechtzeitig gesendet werden. Bitte melde es noch einmal.'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('an error of the callback shows a failure and is reported', (tester) async {
      final results = <ReportResult>[];
      final submit = FakeSubmit([() => throw StateError('backend down'), sent]);
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call, onResult: results.add));
      await chooseAndSend(tester);
      expect(tester.takeException(), isA<StateError>());
      expect(find.text('Meldung nicht gesendet'), findsOneWidget);
      expect(results, isEmpty);

      await tapVisible(tester, find.text('Erneut versuchen'));
      expect(find.text('Danke für deine Meldung'), findsOneWidget);
    });

    testWidgets('shows the warning for a reporter (Art. 23 DSA)', (tester) async {
      await pumpApp(
        tester,
        LimeniaReportForm(onSubmit: FakeSubmit([() => sent(warning: ReporterWarning(issuedAt: DateTime(2026)))]).call),
      );
      await chooseAndSend(tester);
      expect(find.text('Danke für deine Meldung'), findsOneWidget);
      expect(find.text(LimeniaUiStrings.de.reporterWarning), findsOneWidget);
    });

    testWidgets('counts the text in code points like Limenia and blocks a longer one', (tester) async {
      final submit = FakeSubmit([sent]);
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call));
      await tapVisible(tester, find.text('Spam'));

      // A family emoji is one grapheme but five code points.
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      await typeText(tester, family * 401);
      expect(find.text('2005 / 2000'), findsOneWidget);
      expect(find.text('Bitte kürze deinen Text auf höchstens 2000 Zeichen.'), findsOneWidget);
      await tapVisible(tester, find.byType(FilledButton));
      expect(submit.drafts, isEmpty);

      await typeText(tester, family * 400);
      expect(find.text('2000 / 2000'), findsOneWidget);
      expect(find.text('Bitte kürze deinen Text auf höchstens 2000 Zeichen.'), findsNothing);
      await tapVisible(tester, find.byType(FilledButton));
      expect(submit.drafts.single.reasonText, family * 400);
      expect(
          validateReport(ReportRequest.user(
            reasonCategory: 'spam',
            subject: const ReportedUser('u'),
            reasonText: submit.drafts.single.reasonText,
          )),
          isEmpty);
    });

    testWidgets('accepts exactly the limit of the package', (tester) async {
      final submit = FakeSubmit([sent]);
      await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call));
      await chooseAndSend(tester, text: 'a' * ReportLimits.reasonTextLength);
      expect(submit.drafts.single.reasonText, hasLength(2000));
    });

    group('good faith', () {
      testWidgets('required: blocks until checked and sends true', (tester) async {
        final submit = FakeSubmit([sent]);
        await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call, goodFaith: GoodFaithConfirmation.required));
        expect(find.text(LimeniaUiStrings.de.goodFaithLabel), findsOneWidget);
        await chooseAndSend(tester);
        expect(submit.drafts, isEmpty);
        expect(findInLiveRegion('Bitte bestätige deine Angaben.'), findsOneWidget);

        await tapVisible(tester, find.byType(Checkbox));
        await tapVisible(tester, find.byType(FilledButton));
        expect(submit.drafts.single.goodFaithConfirmed, isTrue);
      });

      testWidgets('optional: sends unchecked as false', (tester) async {
        final submit = FakeSubmit([sent]);
        await pumpApp(tester, LimeniaReportForm(onSubmit: submit.call, goodFaith: GoodFaithConfirmation.optional));
        expect(find.byType(Checkbox), findsOneWidget);
        await chooseAndSend(tester);
        expect(submit.drafts.single.goodFaithConfirmed, isFalse);
      });

      testWidgets('optional: sends checked as true, in English', (tester) async {
        final submit = FakeSubmit([sent]);
        await pumpApp(
          tester,
          LimeniaReportForm(onSubmit: submit.call, goodFaith: GoodFaithConfirmation.optional),
          locale: english,
        );
        await tapVisible(tester, find.text(LimeniaUiStrings.en.goodFaithLabel));
        await chooseAndSend(tester);
        expect(submit.drafts.single.goodFaithConfirmed, isTrue);
      });

      testWidgets('the confirmation goes into ReportRequest.goodFaith as in the README', (tester) async {
        final requests = <ReportRequest>[];
        await pumpApp(
          tester,
          LimeniaReportForm(
            goodFaith: GoodFaithConfirmation.required,
            onSubmit: (draft) async {
              final request = ReportRequest.content(
                reasonCategory: draft.reasonCategory,
                reasonText: draft.reasonText,
                goodFaith: draft.goodFaithConfirmed,
                content: const ReportedContent(externalContentId: 'comment_1', contentType: 'comment'),
                author: const ReportedUser('u_1'),
              );
              requests.add(request);
              return sent();
            },
          ),
        );
        await tapVisible(tester, find.byType(Checkbox));
        await chooseAndSend(tester);
        final request = requests.single;
        expect(request.source, ReportSource.user);
        expect(request.toJson()['goodFaith'], isTrue);
        expect(validateReport(request), isEmpty);
      });
    });

    group('categories', () {
      testWidgets('custom categories replace the defaults', (tester) async {
        final submit = FakeSubmit([sent]);
        await pumpApp(
          tester,
          LimeniaReportForm(
            onSubmit: submit.call,
            categories: const [
              ReportCategoryOption(code: 'spam', label: 'Werbung'),
              ReportCategoryOption(code: 'cheating', label: 'Schummeln', description: 'Bots, Hacks und Exploits'),
            ],
          ),
        );
        expect(find.byType(RadioListTile<String>), findsNWidgets(2));
        expect(find.text('Bots, Hacks und Exploits'), findsOneWidget);
        expect(find.text('Belästigung und Hassrede'), findsNothing);
        await chooseAndSend(tester, category: 'Schummeln');
        expect(submit.drafts.single.reasonCategory, 'cheating');
      });

      testWidgets('an invalid code fails in debug mode', (tester) async {
        await pumpApp(
          tester,
          LimeniaReportForm(
            onSubmit: FakeSubmit([sent]).call,
            categories: const [ReportCategoryOption(code: 'Not valid', label: 'x')],
          ),
        );
        expect(tester.takeException(), isA<FlutterError>().having((e) => e.message, 'message', contains('Not valid')));
      });

      testWidgets('a code that appears twice fails in debug mode', (tester) async {
        await pumpApp(
          tester,
          LimeniaReportForm(
            onSubmit: FakeSubmit([sent]).call,
            categories: const [
              ReportCategoryOption(code: 'spam', label: 'a'),
              ReportCategoryOption(code: 'spam', label: 'b'),
            ],
          ),
        );
        expect(tester.takeException(), isA<FlutterError>());
      });

      test('defaults follow ReasonCategory.defaults with the labels of the strings', () {
        final defaults = ReportCategoryOption.defaults(LimeniaUiStrings.en);
        expect([for (final c in defaults) c.code], ReasonCategory.defaults);
        expect(defaults.first, const ReportCategoryOption(code: 'spam', label: 'Spam'));
      });
    });

    group('emergency hint', () {
      testWidgets('shows for self-harm and violence, not for others', (tester) async {
        await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([sent]).call));
        expect(find.text(LimeniaUiStrings.de.emergencyHint), findsNothing);
        await tapVisible(tester, find.text('Selbstgefährdung'));
        expect(findInLiveRegion(LimeniaUiStrings.de.emergencyHint), findsOneWidget);
        await tapVisible(tester, find.text('Gewalt'));
        expect(find.text(LimeniaUiStrings.de.emergencyHint), findsOneWidget);
        await tapVisible(tester, find.text('Spam'));
        expect(find.text(LimeniaUiStrings.de.emergencyHint), findsNothing);
      });

      testWidgets('takes its own text and categories', (tester) async {
        await pumpApp(
          tester,
          LimeniaReportForm(
            onSubmit: FakeSubmit([sent]).call,
            emergencyHint: const ReportEmergencyHint(categories: {'child_safety'}, text: 'Ruf 110 an.'),
          ),
        );
        await tapVisible(tester, find.text('Selbstgefährdung'));
        expect(find.text('Ruf 110 an.'), findsNothing);
        await tapVisible(tester, find.text('Schutz von Minderjährigen'));
        expect(find.text('Ruf 110 an.'), findsOneWidget);
      });

      testWidgets('can be turned off', (tester) async {
        await pumpApp(tester, LimeniaReportForm(onSubmit: FakeSubmit([sent]).call, emergencyHint: null));
        await tapVisible(tester, find.text('Selbstgefährdung'));
        expect(find.text(LimeniaUiStrings.de.emergencyHint), findsNothing);
      });
    });

    test('ReportDraft.toString leaves out the text', () {
      const draft = ReportDraft(reasonCategory: 'spam', reasonText: 'secret words');
      expect(draft.toString(), isNot(contains('secret')));
      expect(draft.toString(), contains('12 characters'));
    });
  });

  group('showLimeniaReportSheet', () {
    testWidgets('completes with null when closed before a result', (tester) async {
      Future<ReportResult?>? result;
      await pumpLauncher(
          tester, (context) => result = showLimeniaReportSheet(context, onSubmit: FakeSubmit([sent]).call));
      expect(find.text('Warum meldest du das?'), findsOneWidget);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Warum meldest du das?'), findsNothing);
      expect(await result, isNull);
    });

    testWidgets('completes with the last result', (tester) async {
      Future<ReportResult?>? result;
      final submit = FakeSubmit([failed, sent]);
      await pumpLauncher(
        tester,
        (context) => result = showLimeniaReportSheet(context, onSubmit: submit.call, title: 'Kommentar melden'),
      );
      expect(find.text('Kommentar melden'), findsOneWidget);
      await chooseAndSend(tester);
      await tapVisible(tester, find.text('Erneut versuchen'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Schließen'));
      expect(await result, isA<ReportSent>());
    });

    testWidgets('keeps the strings scope of the calling context', (tester) async {
      setViewSize(tester, phone);
      await tester.pumpWidget(
        TestApp(
          home: LimeniaUiStringsScope(
            strings: (locale) => LimeniaUiStrings.forLocale(locale).copyWith(reportSubmit: 'Abschicken'),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showLimeniaReportSheet(context, onSubmit: FakeSubmit([sent]).call),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Abschicken'), findsOneWidget);
    });

    testWidgets('explicit strings win', (tester) async {
      await pumpLauncher(
        tester,
        (context) => showLimeniaReportSheet(context, onSubmit: FakeSubmit([sent]).call, strings: LimeniaUiStrings.en),
      );
      expect(find.text('Send report'), findsOneWidget);
    });
  });

  group('large text and accessibility', () {
    for (final size in [smallPhone, phone]) {
      for (final brightness in Brightness.values) {
        testWidgets('text scale 2.0 without overflow, ${size.width.toInt()} wide, ${brightness.name}', (tester) async {
          final answer = Completer<ReportResult>();
          await pumpLauncher(
            tester,
            (context) => showLimeniaReportSheet(
              context,
              onSubmit: FakeSubmit([() => answer.future]).call,
              goodFaith: GoodFaithConfirmation.required,
            ),
            textScale: 2,
            size: size,
            brightness: brightness,
          );
          await tapVisible(tester, find.text('Meldung senden'));
          await tapVisible(tester, find.text('Selbstgefährdung'));
          await tapVisible(tester, find.byType(Checkbox));
          await typeText(tester, 'Text ' * 100);
          await tester.ensureVisible(find.byType(FilledButton));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          await tester.pump();
          expect(find.text('Wird gesendet …'), findsOneWidget);
          answer.complete(sent(warning: ReporterWarning(issuedAt: DateTime(2026))));
          await tester.pumpAndSettle();
          expect(find.text('Danke für deine Meldung'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('text scale 2.0 for every failure', (tester) async {
      for (final result in [queued, failed, expired, () => reporterSuspended(DateTime(2026, 10, 14, 14, 30))]) {
        await tester.pumpWidget(const SizedBox());
        await pumpLauncher(
          tester,
          (context) => showLimeniaReportSheet(context, onSubmit: FakeSubmit([result]).call),
          textScale: 2,
          size: smallPhone,
        );
        await chooseAndSend(tester);
        expect(find.byType(FilledButton), findsWidgets);
        expect(tester.takeException(), isNull);
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets('meets the accessibility guidelines, ${brightness.name}', (tester) async {
        await pumpApp(
          tester,
          LimeniaReportForm(
            onSubmit: FakeSubmit([sent]).call,
            goodFaith: GoodFaithConfirmation.optional,
            onClose: () {},
          ),
          brightness: brightness,
        );
        await tapVisible(tester, find.text('Gewalt'));
        await expectAccessible(tester);
        await tapVisible(tester, find.byType(FilledButton));
        await expectAccessible(tester);
      });
    }
  });
}
