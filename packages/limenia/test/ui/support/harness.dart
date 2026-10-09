import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia/limenia.dart';

/// Logical size of a phone, as in the screenshots.
const phone = Size(390, 844);

/// A small phone, to provoke overflows.
const smallPhone = Size(320, 568);

const german = Locale('de');
const english = Locale('en');

/// Sets the size of the test view in logical pixels.
void setViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
}

/// Pumps [child] in an app with [locale], [brightness] and [textScale], in a
/// scroll view unless [scroll] is false.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  Locale locale = german,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = phone,
  bool scroll = true,
  Widget Function(Widget child)? wrap,
}) async {
  setViewSize(tester, size);
  await tester.pumpWidget(
    TestApp(
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      wrap: wrap,
      home: Scaffold(
        body: SafeArea(
          child: scroll ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: child) : child,
        ),
      ),
    ),
  );
}

/// Pumps a button that runs [open] with its context, e.g. to show a sheet,
/// taps it and settles.
Future<void> pumpLauncher(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  Locale locale = german,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = phone,
  Widget Function(Widget child)? wrap,
}) async {
  setViewSize(tester, size);
  await tester.pumpWidget(
    TestApp(
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      wrap: wrap,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => open(context), child: const Text('open')),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// A [MaterialApp] for the tests.
class TestApp extends StatelessWidget {
  const TestApp({
    super.key,
    required this.home,
    this.locale = german,
    this.brightness = Brightness.light,
    this.textScale = 1,
    this.wrap,
  });

  final Widget home;
  final Locale locale;
  final Brightness brightness;
  final double textScale;
  final Widget Function(Widget child)? wrap;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: locale,
        supportedLocales: const [german, english],
        localizationsDelegates: const [
          _AnyLocale<MaterialLocalizations>(DefaultMaterialLocalizations()),
          _AnyLocale<CupertinoLocalizations>(DefaultCupertinoLocalizations()),
          _AnyLocale<WidgetsLocalizations>(DefaultWidgetsLocalizations()),
        ],
        theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: brightness),
        builder: (context, child) {
          Widget app = MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
          if (wrap != null) app = wrap!(app);
          return app;
        },
        home: home,
      );
}

/// The English localizations of the framework for every locale, so that the
/// tests run in German without flutter_localizations.
class _AnyLocale<T> extends LocalizationsDelegate<T> {
  const _AnyLocale(this.value);

  final T value;

  @override
  Type get type => T;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => SynchronousFuture<T>(value);

  @override
  bool shouldReload(_AnyLocale<T> old) => false;
}

/// A text widget whose data is exactly [text], also a [SelectableText].
Finder findText(String text) => find.byWidgetPredicate(
      (w) => (w is Text && w.data == text) || (w is SelectableText && w.data == text),
      description: 'text "$text"',
    );

/// Whether a widget in a live region shows [text].
Finder findInLiveRegion(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
    );

/// Checks the accessibility guidelines of Flutter on the current screen.
Future<void> expectAccessible(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

/// A statement of reasons with the given structured values.
StatementOfReasons statement({
  String action = 'suspend_user',
  String text = 'Entscheidung über dein Konto\n\nMaßnahme: vorübergehende Sperre des Kontos.',
  DateTime? endsAt,
  String facts = 'Beleidigende Kommentare.',
  bool basedOnNotice = true,
  String? noticeSource = 'notice',
  bool automatedDetection = false,
  String? automation = 'none',
  List<SorGround> grounds = const [
    SorGround(basis: LegalBasis.terms, policyCode: 'harassment_hate', title: 'Belästigung und Hassrede'),
  ],
  String redress = 'Du kannst dich innerhalb von sechs Monaten beschweren.',
}) =>
    StatementOfReasons(
      locale: 'de',
      text: text,
      structured: SorDetails(
        actionName: action,
        endsAt: endsAt,
        territorialScope: 'app',
        facts: facts,
        basedOnNotice: basedOnNotice,
        noticeSourceName: noticeSource,
        automatedDetection: automatedDetection,
        automatedDecision: automation == 'full',
        automationName: automation,
        grounds: grounds,
        redress: redress,
      ),
    );

/// A decision with [statement].
ModerationDecision decision({
  String action = 'remove_content',
  DateTime? decidedAt,
  DateTime? suspendUntil,
  List<PolicyRef> policies = const [PolicyRef(code: 'harassment_hate', title: 'Belästigung und Hassrede')],
}) =>
    ModerationDecision(
      id: '01K6G5H1TR8W4QZ3M0XCB7NDEC',
      actionName: action,
      suspendUntil: suspendUntil,
      externalUserId: 'u_112',
      policies: policies,
      statementOfReasons: statement(action: action, endsAt: suspendUntil),
      decidedAt: decidedAt ?? DateTime.utc(2026, 10, 7, 12),
    );
