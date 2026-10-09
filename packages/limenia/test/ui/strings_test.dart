import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

import 'support/harness.dart';

void main() {
  group('LimeniaUiStrings', () {
    test('forLocale picks German for de and English for every other language', () {
      expect(LimeniaUiStrings.forLocale(const Locale('de')), same(LimeniaUiStrings.de));
      expect(LimeniaUiStrings.forLocale(const Locale('de', 'AT')), same(LimeniaUiStrings.de));
      expect(LimeniaUiStrings.forLocale(const Locale('en')), same(LimeniaUiStrings.en));
      expect(LimeniaUiStrings.forLocale(const Locale('fr')), same(LimeniaUiStrings.en));
    });

    test('labels every default category and every action in both languages', () {
      for (final strings in [LimeniaUiStrings.de, LimeniaUiStrings.en]) {
        expect(strings.categoryLabels.keys, unorderedEquals(ReasonCategory.defaults));
        expect(strings.actionLabels.keys, unorderedEquals(ModerationAction.values));
        expect(strings.categoryLabels.values.every((l) => l.isNotEmpty), isTrue);
      }
      expect(LimeniaUiStrings.de.categoryLabels[ReasonCategory.harassmentHate], 'Belästigung und Hassrede');
      expect(LimeniaUiStrings.de.categoryLabels[ReasonCategory.childSafety], 'Schutz von Minderjährigen');
      expect(LimeniaUiStrings.en.categoryLabels[ReasonCategory.selfHarm], 'Self-harm');
    });

    test('copyWith replaces the given texts and keeps the others', () {
      final changed = LimeniaUiStrings.de.copyWith(
        reportTitle: 'Beitrag melden',
        suspendedMessage: (until) => 'Gesperrt bis $until',
      );
      expect(changed.reportTitle, 'Beitrag melden');
      expect(changed.suspendedMessage('morgen'), 'Gesperrt bis morgen');
      expect(changed.reportSubmit, LimeniaUiStrings.de.reportSubmit);
      expect(changed.categoryLabels, same(LimeniaUiStrings.de.categoryLabels));
      expect(changed.formatDateTime, same(LimeniaUiStrings.de.formatDateTime));
    });

    test('texts with values', () {
      const de = LimeniaUiStrings.de;
      const en = LimeniaUiStrings.en;
      expect(de.suspendedMessage('14.10.2026 14:30'), 'Dein Konto ist bis zum 14.10.2026 14:30 gesperrt.');
      expect(de.suspendedMessage(null), 'Dein Konto ist vorübergehend gesperrt.');
      expect(en.suspendedMessage('Oct 14, 2026, 14:30'), 'Your account is suspended until Oct 14, 2026, 14:30.');
      expect(de.sorGroundLaw('§ 130 StGB'), 'Rechtswidriger Inhalt: § 130 StGB');
      expect(de.sorGroundLaw(null), 'Rechtswidriger Inhalt');
      expect(en.sorGroundLaw(''), 'Illegal content');
      expect(de.textTooLong(2000), 'Bitte kürze deinen Text auf höchstens 2000 Zeichen.');
      expect(en.characterCount(12, 5000), '12 / 5000');
      expect(de.appealDeadline('07.04.2027'), 'Du kannst dich bis zum 07.04.2027 beschweren.');
      expect(en.appealDeadline('Apr 7, 2027'), 'You can complain until Apr 7, 2027.');
    });
  });

  group('dates', () {
    test('German: dd.MM.yyyy HH:mm in local time', () {
      const de = LimeniaUiStrings.de;
      expect(de.formatDateTime(DateTime(2026, 10, 7, 14, 30)), '07.10.2026 14:30');
      expect(de.formatDateTime(DateTime(2026, 1, 1, 0, 5)), '01.01.2026 00:05');
      expect(de.formatDate(DateTime(2026, 12, 31, 23, 59)), '31.12.2026');
    });

    test('English: MMM d, yyyy, HH:mm in local time', () {
      const en = LimeniaUiStrings.en;
      expect(en.formatDateTime(DateTime(2026, 10, 7, 14, 30)), 'Oct 7, 2026, 14:30');
      expect(en.formatDateTime(DateTime(2026, 1, 1, 0, 5)), 'Jan 1, 2026, 00:05');
      expect(en.formatDate(DateTime(2026, 12, 31, 23, 59)), 'Dec 31, 2026');
      expect(en.formatDate(DateTime(2027, 5, 9)), 'May 9, 2027');
    });

    test('a UTC time is shown in the local time zone', () {
      final utc = DateTime.utc(2026, 10, 7, 12, 30);
      final local = utc.toLocal();
      expect(LimeniaUiStrings.de.formatDateTime(utc), LimeniaUiStrings.de.formatDateTime(local));
    });
  });

  group('appealDeadlineFor', () {
    test('six calendar months later at the same time, in UTC', () {
      expect(appealDeadlineFor(DateTime.utc(2026, 10, 7, 12, 30, 15)), DateTime.utc(2027, 4, 7, 12, 30, 15));
      expect(appealDeadlineFor(DateTime.utc(2026, 1, 15)), DateTime.utc(2026, 7, 15));
      expect(appealDeadlineFor(DateTime.utc(2026, 10, 7)).isUtc, isTrue);
    });

    test('the last day of a shorter target month', () {
      expect(appealDeadlineFor(DateTime.utc(2026, 8, 31, 9)), DateTime.utc(2027, 2, 28, 9));
      expect(appealDeadlineFor(DateTime.utc(2027, 8, 31)), DateTime.utc(2028, 2, 29));
      expect(appealDeadlineFor(DateTime.utc(2026, 3, 31)), DateTime.utc(2026, 9, 30));
      expect(appealDeadlineFor(DateTime.utc(2026, 12, 31)), DateTime.utc(2027, 6, 30));
    });

    test('a local time counts as the same instant in UTC', () {
      final local = DateTime(2026, 10, 7, 12);
      expect(appealDeadlineFor(local), appealDeadlineFor(local.toUtc()));
    });
  });

  group('LimeniaUiStrings.of', () {
    Future<LimeniaUiStrings> stringsAt(WidgetTester tester,
        {required Locale locale, Widget Function(Widget)? wrap}) async {
      late LimeniaUiStrings strings;
      await pumpApp(
        tester,
        Builder(
          builder: (context) {
            strings = LimeniaUiStrings.of(context);
            return const SizedBox();
          },
        ),
        locale: locale,
        wrap: wrap,
      );
      return strings;
    }

    testWidgets('follows the locale of the app', (tester) async {
      expect(await stringsAt(tester, locale: german), same(LimeniaUiStrings.de));
      expect(await stringsAt(tester, locale: english), same(LimeniaUiStrings.en));
    });

    testWidgets('falls back to English without Localizations', (tester) async {
      late LimeniaUiStrings strings;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            strings = LimeniaUiStrings.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(strings, same(LimeniaUiStrings.en));
    });

    testWidgets('takes the strings of a LimeniaUiStringsScope for the locale', (tester) async {
      final strings = await stringsAt(
        tester,
        locale: german,
        wrap: (child) => LimeniaUiStringsScope(
          strings: (locale) => LimeniaUiStrings.forLocale(locale).copyWith(reportTitle: 'Beitrag melden'),
          child: child,
        ),
      );
      expect(strings.reportTitle, 'Beitrag melden');
      expect(strings.reportSubmit, 'Meldung senden');
    });
  });
}
