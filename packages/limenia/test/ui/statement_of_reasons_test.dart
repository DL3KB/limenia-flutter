import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

import 'support/harness.dart';

void main() {
  group('text layout', () {
    testWidgets('shows the ready-made text as selectable plain text', (tester) async {
      const text = 'Entscheidung über deinen Inhalt\n\nMaßnahme: Entfernung des Inhalts.\n'
          'Sachverhalt: **fett** <b>kein HTML</b> [Link](https://example.com)';
      await pumpApp(tester, LimeniaStatementOfReasonsView(statement: statement(text: text)));
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, text);
      // Nothing is interpreted: no rich text, no links.
      expect(selectable.textSpan, isNull);
      expect(find.text('Maßnahme'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a complaint button calls back', (tester) async {
      var appeals = 0;
      await pumpApp(tester, LimeniaStatementOfReasonsView(statement: statement(), onAppeal: () => appeals++));
      await tester.tap(find.text('Beschwerde einreichen'));
      expect(appeals, 1);
    });

    testWidgets('the button follows the language of the app, the text stays as sent', (tester) async {
      await pumpApp(tester, LimeniaStatementOfReasonsView(statement: statement(), onAppeal: () {}), locale: english);
      expect(find.text('Submit a complaint'), findsOneWidget);
      expect(findText(statement().text), findsOneWidget);
    });
  });

  group('structured layout', () {
    testWidgets('shows every section with German labels', (tester) async {
      await pumpApp(
        tester,
        LimeniaStatementOfReasonsView(
          layout: SorLayout.structured,
          statement: statement(
            action: 'suspend_user',
            endsAt: DateTime(2026, 10, 14, 14, 30),
            facts: 'Mehrere beleidigende Kommentare.',
            grounds: const [
              SorGround(basis: LegalBasis.terms, policyCode: 'harassment_hate', title: 'Belästigung und Hassrede'),
              SorGround(
                  basis: LegalBasis.law,
                  policyCode: 'incitement',
                  title: 'Volksverhetzung',
                  lawReference: '§ 130 StGB'),
            ],
            redress: 'Du kannst dich innerhalb von sechs Monaten beschweren.',
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('Maßnahme'), findsOneWidget);
      expect(find.text('Vorübergehende Sperre des Kontos'), findsOneWidget);
      expect(find.text('Endet am'), findsOneWidget);
      expect(find.text('14.10.2026 14:30'), findsOneWidget);
      expect(find.text('Geltungsbereich'), findsOneWidget);
      expect(find.text('Die gesamte App'), findsOneWidget);
      expect(find.text('Sachverhalt'), findsOneWidget);
      expect(find.text('Mehrere beleidigende Kommentare.'), findsOneWidget);
      expect(find.text('Anlass'), findsOneWidget);
      expect(find.text('Eine Meldung durch andere Nutzer'), findsOneWidget);
      expect(find.text('Automatisierte Mittel'), findsOneWidget);
      expect(find.text(LimeniaUiStrings.de.sorAutomationNone), findsOneWidget);
      expect(find.text('Grundlage'), findsOneWidget);
      expect(find.text('Belästigung und Hassrede'), findsOneWidget);
      expect(find.text('Verstoß gegen die Nutzungsbedingungen'), findsOneWidget);
      expect(find.text('Volksverhetzung'), findsOneWidget);
      expect(find.text('Rechtswidriger Inhalt: § 130 StGB'), findsOneWidget);
      expect(find.text('Rechtsbehelfe'), findsOneWidget);
      expect(find.text('Du kannst dich innerhalb von sechs Monaten beschweren.'), findsOneWidget);
      // The ready-made text is not shown in this layout.
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('labels in English, the texts of the tenant stay as sent', (tester) async {
      await pumpApp(
        tester,
        LimeniaStatementOfReasonsView(
          layout: SorLayout.structured,
          statement: statement(action: 'remove_content', facts: 'Beleidigung.'),
        ),
        locale: english,
      );
      expect(find.text('Measure'), findsOneWidget);
      expect(find.text('Removal of the content'), findsOneWidget);
      expect(find.text('Scope'), findsOneWidget);
      expect(find.text('The whole app'), findsOneWidget);
      expect(find.text('Facts'), findsOneWidget);
      expect(find.text('Beleidigung.'), findsOneWidget);
      expect(find.text('What led to the decision'), findsOneWidget);
      expect(find.text('Grounds'), findsOneWidget);
      expect(find.text('Violation of the terms of service'), findsOneWidget);
      expect(find.text('Redress'), findsOneWidget);
      expect(find.text('Ends on'), findsNothing);
    });

    testWidgets('a law ground without a reference', (tester) async {
      await pumpApp(
        tester,
        LimeniaStatementOfReasonsView(
          layout: SorLayout.structured,
          statement: statement(
            grounds: const [SorGround(basis: LegalBasis.law, policyCode: 'illegal', title: 'Illegale Inhalte')],
          ),
        ),
      );
      expect(find.text('Rechtswidriger Inhalt'), findsOneWidget);
    });

    testWidgets('no scope for dismiss and restore, no empty sections', (tester) async {
      for (final action in ['dismiss', 'restore']) {
        await pumpApp(
          tester,
          LimeniaStatementOfReasonsView(
            layout: SorLayout.structured,
            statement: statement(action: action, facts: '  ', grounds: const [], redress: ''),
          ),
        );
        expect(find.text('Geltungsbereich'), findsNothing);
        expect(find.text('Sachverhalt'), findsNothing);
        expect(find.text('Grundlage'), findsNothing);
        expect(find.text('Rechtsbehelfe'), findsNothing);
        expect(find.text('Maßnahme'), findsOneWidget);
      }
    });

    group('what led to the decision', () {
      for (final (source, basedOnNotice, text) in [
        ('notice', true, 'Eine Meldung durch andere Nutzer'),
        ('trusted_flagger', true, 'Die Meldung eines vertrauenswürdigen Hinweisgebers'),
        ('own_initiative', false, 'Eine eigene Prüfung'),
        (null, false, 'Eine eigene Prüfung'), // before API 0.16.0
        (null, true, 'Eine Meldung durch andere Nutzer'),
      ]) {
        testWidgets('$source, basedOnNotice $basedOnNotice', (tester) async {
          await pumpApp(
            tester,
            LimeniaStatementOfReasonsView(
              layout: SorLayout.structured,
              statement: statement(noticeSource: source, basedOnNotice: basedOnNotice),
            ),
          );
          expect(find.text(text), findsOneWidget);
        });
      }
    });

    group('automated means (Art. 17(3)(c) DSA)', () {
      Finder highlighted(String text) => find.descendant(of: find.byType(DecoratedBox), matching: find.text(text));

      testWidgets('partial: always shown and highlighted', (tester) async {
        await pumpApp(
          tester,
          LimeniaStatementOfReasonsView(layout: SorLayout.structured, statement: statement(automation: 'partial')),
        );
        expect(highlighted(LimeniaUiStrings.de.sorAutomationPartial), findsOneWidget);
        expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
      });

      testWidgets('partial with automated detection names both', (tester) async {
        await pumpApp(
          tester,
          LimeniaStatementOfReasonsView(
            layout: SorLayout.structured,
            statement: statement(automation: 'partial', automatedDetection: true),
          ),
          locale: english,
        );
        expect(
          highlighted('${LimeniaUiStrings.en.sorAutomatedDetection} ${LimeniaUiStrings.en.sorAutomationPartial}'),
          findsOneWidget,
        );
      });

      testWidgets('full: an automatic decision', (tester) async {
        await pumpApp(
          tester,
          LimeniaStatementOfReasonsView(layout: SorLayout.structured, statement: statement(automation: 'full')),
        );
        expect(highlighted(LimeniaUiStrings.de.sorAutomationFull), findsOneWidget);
      });

      testWidgets('none with automated detection: detected automatically, a person decided', (tester) async {
        await pumpApp(
          tester,
          LimeniaStatementOfReasonsView(
            layout: SorLayout.structured,
            statement: statement(automation: 'none', automatedDetection: true),
          ),
        );
        expect(find.text(LimeniaUiStrings.de.sorAutomatedDetection), findsOneWidget);
        expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
      });

      testWidgets('missing or unknown counts as none', (tester) async {
        for (final automation in [null, 'something_new']) {
          await pumpApp(
            tester,
            LimeniaStatementOfReasonsView(layout: SorLayout.structured, statement: statement(automation: automation)),
          );
          expect(find.text(LimeniaUiStrings.de.sorAutomationNone), findsOneWidget);
        }
      });
    });

    testWidgets('an unknown action falls back to the ready-made text', (tester) async {
      final unknown = statement(action: 'shadow_ban', text: 'Entscheidung über dein Konto\n\nMaßnahme: neu.');
      await pumpApp(tester, LimeniaStatementOfReasonsView(layout: SorLayout.structured, statement: unknown));
      expect(find.byType(SelectableText), findsOneWidget);
      expect(findText(unknown.text), findsOneWidget);
      expect(find.text('Maßnahme'), findsNothing);
    });
  });

  group('large text and accessibility', () {
    for (final layout in SorLayout.values) {
      for (final size in [smallPhone, phone]) {
        testWidgets('text scale 2.0 without overflow, ${layout.name}, ${size.width.toInt()} wide', (tester) async {
          await pumpApp(
            tester,
            LimeniaStatementOfReasonsView(
              layout: layout,
              statement: statement(
                endsAt: DateTime(2026, 10, 14, 14, 30),
                automation: 'partial',
                automatedDetection: true,
                facts: 'Sehr langer Sachverhalt ' * 20,
                grounds: const [
                  SorGround(
                    basis: LegalBasis.law,
                    policyCode: 'incitement',
                    title: 'Volksverhetzung und Aufforderung zu Straftaten',
                    lawReference: '§ 130 StGB, § 111 StGB',
                  ),
                ],
              ),
              onAppeal: () {},
            ),
            textScale: 2,
            size: size,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('meets the accessibility guidelines, ${brightness.name}', (tester) async {
        await pumpApp(
          tester,
          LimeniaStatementOfReasonsView(
            layout: SorLayout.structured,
            statement: statement(automation: 'partial'),
            onAppeal: () {},
          ),
          brightness: brightness,
        );
        await expectAccessible(tester);
      });
    }

    testWidgets('section labels are headings for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, LimeniaStatementOfReasonsView(layout: SorLayout.structured, statement: statement()));
      expect(tester.getSemantics(find.text('Maßnahme')), isSemantics(isHeader: true));
      expect(tester.getSemantics(find.text('Grundlage')), isSemantics(isHeader: true));
      handle.dispose();
    });
  });
}
