// Example app with every widget of package:limenia/ui.dart. It runs without a backend:
// the callbacks below stand in for `Limenia.report` and `Limenia.appeal`,
// which in a real app send through the backend of the app (see README.md).
//
// Query parameters open a screen directly, e.g. for screenshots:
//   ?screen=report|appeal|reasons|restriction  &open=1 (opens the sheet)
//   &lang=de|en  &theme=light|dark
//   &layout=text|structured (reasons)  &status=warned|suspended|banned  &full=1 (restriction)
//   &semantics=1 (builds the semantics tree on the web, for automated tests)
import 'package:flutter/cupertino.dart' show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:limenia/limenia.dart';
import 'package:limenia/ui.dart';

/// Keeps the semantics tree for `?semantics=1` as long as the app runs.
SemanticsHandle? semanticsHandle;

void main() {
  final query = Uri.base.queryParameters;
  runApp(ExampleApp(query: query));
  if (query['semantics'] == '1') semanticsHandle = SemanticsBinding.instance.ensureSemantics();
}

/// The time the demo data is relative to, so that the suspension lies ahead.
final _start = DateTime.now().toUtc().copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0);

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.query = const {}});

  final Map<String, String> query;

  static ExampleAppState of(BuildContext context) => context.findAncestorStateOfType<ExampleAppState>()!;

  @override
  State<ExampleApp> createState() => ExampleAppState();
}

class ExampleAppState extends State<ExampleApp> {
  late Locale locale = Locale(widget.query['lang'] == 'en' ? 'en' : 'de');
  late ThemeMode themeMode = widget.query['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;

  void toggleLanguage() => setState(() => locale = Locale(locale.languageCode == 'de' ? 'en' : 'de'));

  void toggleTheme() => setState(() => themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E6B5E);
    final query = widget.query;
    final open = query['open'] == '1';
    return MaterialApp(
      title: 'Limenia UI',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('de'), Locale('en')],
      // Real apps add GlobalMaterialLocalizations from flutter_localizations.
      // The example keeps to the dependencies of the package and uses the
      // English texts of the framework (tooltips) in German as well.
      localizationsDelegates: const [
        _AnyLocale<MaterialLocalizations>(DefaultMaterialLocalizations()),
        _AnyLocale<CupertinoLocalizations>(DefaultCupertinoLocalizations()),
        _AnyLocale<WidgetsLocalizations>(DefaultWidgetsLocalizations()),
      ],
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      themeMode: themeMode,
      home: switch (query['screen']) {
        'report' => ReportDemo(openSheet: open),
        'appeal' => AppealDemo(openSheet: open),
        'reasons' => ReasonsDemo(structured: query['layout'] == 'structured'),
        'restriction' => RestrictionDemo(
            status: SanctionStatus.values.asNameMap()[query['status']] ?? SanctionStatus.suspended,
            fullScreen: query['full'] == '1',
          ),
        _ => const HomePage(),
      },
    );
  }
}

/// A scaffold with switches for language and theme.
class DemoScaffold extends StatelessWidget {
  const DemoScaffold({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final app = ExampleApp.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: app.toggleLanguage,
            child: Text(german ? 'EN' : 'DE', semanticsLabel: german ? 'English' : 'Deutsch'),
          ),
          IconButton(
            onPressed: app.toggleTheme,
            tooltip: dark ? 'Light' : 'Dark',
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Centers [children] in a scroll view no wider than a phone in portrait.
class DemoColumn extends StatelessWidget {
  const DemoColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return DemoScaffold(
      title: 'Limenia UI',
      body: DemoColumn(
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(german ? 'Meldedialog' : 'Report sheet'),
            onTap: () => push(const ReportDemo()),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(german ? 'Beschwerdeformular' : 'Complaint form'),
            onTap: () => push(const AppealDemo()),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(german ? 'Begründung (Statement of Reasons)' : 'Statement of reasons'),
            onTap: () => push(const ReasonsDemo()),
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: Text(german ? 'Sperrhinweis' : 'Restriction notice'),
            onTap: () => push(const RestrictionDemo()),
          ),
        ],
      ),
    );
  }
}

// Report

enum DemoReportOutcome { sent, sentWithWarning, queued, failed, reporterSuspended, expired, error }

/// Stands in for `limenia.report(...)`.
Future<ReportResult> fakeReport(ReportDraft draft, DemoReportOutcome outcome) async {
  debugPrint('fake report: $draft'); // ReportDraft.toString leaves out the text
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  const receipt = ReportReceipt(reportId: 'rep_demo', caseId: 'case_demo', caseCreated: true);
  return switch (outcome) {
    DemoReportOutcome.sent => const ReportSent('demo', receipt),
    DemoReportOutcome.sentWithWarning => ReportSent(
        'demo',
        ReportReceipt(
          reportId: 'rep_demo',
          caseId: 'case_demo',
          caseCreated: false,
          reporterWarning: ReporterWarning(issuedAt: _start),
        ),
      ),
    DemoReportOutcome.queued => ReportQueued('demo', Exception('offline')),
    DemoReportOutcome.failed => const ReportFailed('demo', LimeniaException(400, code: 'validation_failed')),
    DemoReportOutcome.reporterSuspended => ReportFailed(
        'demo',
        LimeniaException(403, code: 'reporter_suspended', suspendedUntil: _start.add(const Duration(days: 14))),
      ),
    DemoReportOutcome.expired => ReportExpired('demo', _start.subtract(const Duration(days: 8))),
    DemoReportOutcome.error => throw Exception('The backend of the app is not reachable.'),
  };
}

class ReportDemo extends StatefulWidget {
  const ReportDemo({super.key, this.openSheet = false});

  final bool openSheet;

  @override
  State<ReportDemo> createState() => _ReportDemoState();
}

class _ReportDemoState extends State<ReportDemo> {
  DemoReportOutcome _outcome = DemoReportOutcome.sent;
  GoodFaithConfirmation _goodFaith = GoodFaithConfirmation.hidden;
  ReportResult? _last;

  @override
  void initState() {
    super.initState();
    if (widget.openSheet) WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final result = await showLimeniaReportSheet(
      context,
      goodFaith: _goodFaith,
      onSubmit: (draft) => fakeReport(draft, _outcome),
    );
    if (mounted) setState(() => _last = result);
  }

  @override
  Widget build(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    final theme = Theme.of(context);
    return DemoScaffold(
      title: german ? 'Meldedialog' : 'Report sheet',
      body: DemoColumn(
        children: [
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(child: Text('M')),
                      const SizedBox(width: 12),
                      Expanded(child: Text('maxi_99', style: theme.textTheme.titleSmall)),
                      IconButton(
                        onPressed: _open,
                        tooltip: german ? 'Melden' : 'Report',
                        icon: const Icon(Icons.flag_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(german ? 'Ein Beitrag, den jemand melden möchte.' : 'A post someone wants to report.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<DemoReportOutcome>(
            initialValue: _outcome,
            decoration: InputDecoration(labelText: german ? 'Antwort des Backends' : 'Answer of the backend'),
            items: [
              for (final o in DemoReportOutcome.values) DropdownMenuItem(value: o, child: Text(o.name)),
            ],
            onChanged: (o) => setState(() => _outcome = o ?? _outcome),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GoodFaithConfirmation>(
            initialValue: _goodFaith,
            decoration: InputDecoration(labelText: german ? 'Bestätigung der Angaben' : 'Good-faith confirmation'),
            items: [
              for (final g in GoodFaithConfirmation.values) DropdownMenuItem(value: g, child: Text(g.name)),
            ],
            onChanged: (g) => setState(() => _goodFaith = g ?? _goodFaith),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.flag_outlined),
            label: Text(german ? 'Meldedialog öffnen' : 'Open the report sheet'),
          ),
          const SizedBox(height: 16),
          Text('${german ? 'Letztes Ergebnis' : 'Last result'}: ${_last?.runtimeType ?? '–'}'),
        ],
      ),
    );
  }
}

// Complaint

enum DemoAppealOutcome { sent, queued, failed, windowClosed, alreadyOpen, notAllowed, reporterSuspended, expired }

/// Stands in for `limenia.appeal(...)`.
Future<AppealResult> fakeAppeal(String text, DemoAppealOutcome outcome) async {
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  AppealFailed refused(int status, String code, {DateTime? until}) =>
      AppealFailed('demo', LimeniaException(status, code: code, suspendedUntil: until));
  return switch (outcome) {
    DemoAppealOutcome.sent => const AppealSent('demo', AppealReceipt(appealId: 'app_demo', status: AppealStatus.open)),
    DemoAppealOutcome.queued => AppealQueued('demo', Exception('offline')),
    DemoAppealOutcome.failed => refused(400, 'validation_failed'),
    DemoAppealOutcome.windowClosed => refused(409, 'appeal_window_closed'),
    DemoAppealOutcome.alreadyOpen => refused(409, 'appeal_already_open'),
    DemoAppealOutcome.notAllowed => refused(403, 'appeal_not_allowed'),
    DemoAppealOutcome.reporterSuspended =>
      refused(403, 'reporter_suspended', until: _start.add(const Duration(days: 14))),
    DemoAppealOutcome.expired => AppealExpired('demo', _start.subtract(const Duration(days: 8))),
  };
}

/// The outcome the complaint demos answer with, shared by every screen.
final _appealOutcome = ValueNotifier(DemoAppealOutcome.sent);

Future<AppealResult?> openAppealSheet(BuildContext context) => showLimeniaAppealSheet(
      context,
      topic: AppealTopic.fromDecision(sampleDecision()),
      onSubmit: (text) => fakeAppeal(text, _appealOutcome.value),
    );

class AppealDemo extends StatefulWidget {
  const AppealDemo({super.key, this.openSheet = false});

  final bool openSheet;

  @override
  State<AppealDemo> createState() => _AppealDemoState();
}

class _AppealDemoState extends State<AppealDemo> {
  // A new key resets the embedded form.
  Key _formKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    if (widget.openSheet) WidgetsBinding.instance.addPostFrameCallback((_) => openAppealSheet(context));
  }

  @override
  Widget build(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    return DemoScaffold(
      title: german ? 'Beschwerdeformular' : 'Complaint form',
      body: DemoColumn(
        children: [
          LimeniaAppealForm(
            key: _formKey,
            topic: AppealTopic.fromDecision(sampleDecision()),
            onSubmit: (text) => fakeAppeal(text, _appealOutcome.value),
            onClose: () => setState(() => _formKey = UniqueKey()),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: _appealOutcome,
            builder: (context, outcome, _) => DropdownButtonFormField<DemoAppealOutcome>(
              initialValue: outcome,
              decoration: InputDecoration(labelText: german ? 'Antwort des Backends' : 'Answer of the backend'),
              items: [
                for (final o in DemoAppealOutcome.values) DropdownMenuItem(value: o, child: Text(o.name)),
              ],
              onChanged: (o) => _appealOutcome.value = o ?? outcome,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => openAppealSheet(context),
            child: Text(german ? 'Als Sheet öffnen' : 'Open as a sheet'),
          ),
        ],
      ),
    );
  }
}

// Statement of reasons

String _utc(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} UTC';

/// A suspension as Limenia sends it in `decision.created`, for a tenant in
/// German, decided with a suggestion of the AI pre-screening.
ModerationDecision sampleDecision() {
  final until = _start.add(const Duration(days: 7));
  const facts = 'Mehrere beleidigende Kommentare unter Beiträgen anderer Nutzer.';
  const redress = 'Du kannst dich innerhalb von sechs Monaten in der App beschweren. Außerdem kannst du eine '
      'zertifizierte außergerichtliche Streitbeilegungsstelle anrufen oder vor Gericht gehen.';
  return ModerationDecision(
    id: '01K6G5H1TR8W4QZ3M0XCB7NDEC',
    actionName: 'suspend_user',
    suspendUntil: until,
    externalUserId: 'u_112',
    policies: const [
      PolicyRef(code: 'harassment_hate', title: 'Belästigung und Hassrede'),
      PolicyRef(code: 'insult', title: 'Beleidigung'),
    ],
    decidedAt: _start,
    statementOfReasons: StatementOfReasons(
      locale: 'de',
      text: 'Entscheidung über dein Konto\n\n'
          'Maßnahme: vorübergehende Sperre des Kontos bis ${_utc(until)}.\n'
          'Geltungsbereich: die gesamte App.\n'
          'Sachverhalt: $facts\n'
          'Die Entscheidung erfolgte nach einer Meldung durch andere Nutzer.\n'
          'Ein automatisiertes System hat den Inhalt eingeschätzt und diese Entscheidung vorgeschlagen; ein Mensch '
          'hat den Vorschlag geprüft und die Entscheidung getroffen.\n'
          'Grundlage:\n'
          '- Belästigung und Hassrede (Verstoß gegen die Nutzungsbedingungen)\n'
          '- Beleidigung (rechtswidriger Inhalt: § 185 StGB)\n'
          'Rechtsbehelfe: $redress',
      structured: SorDetails(
        actionName: 'suspend_user',
        endsAt: until,
        territorialScope: 'app',
        facts: facts,
        basedOnNotice: true,
        noticeSourceName: 'notice',
        automatedDetection: false,
        automatedDecision: false,
        automationName: 'partial',
        grounds: const [
          SorGround(basis: LegalBasis.terms, policyCode: 'harassment_hate', title: 'Belästigung und Hassrede'),
          SorGround(basis: LegalBasis.law, policyCode: 'insult', title: 'Beleidigung', lawReference: '§ 185 StGB'),
        ],
        redress: redress,
      ),
    ),
  );
}

class ReasonsDemo extends StatefulWidget {
  const ReasonsDemo({super.key, this.structured = false});

  final bool structured;

  @override
  State<ReasonsDemo> createState() => _ReasonsDemoState();
}

class _ReasonsDemoState extends State<ReasonsDemo> {
  late SorLayout _layout = widget.structured ? SorLayout.structured : SorLayout.text;

  @override
  Widget build(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    return DemoScaffold(
      title: german ? 'Begründung' : 'Statement of reasons',
      body: DemoColumn(
        children: [
          SegmentedButton<SorLayout>(
            segments: [
              const ButtonSegment(value: SorLayout.text, label: Text('Text')),
              ButtonSegment(value: SorLayout.structured, label: Text(german ? 'Strukturiert' : 'Structured')),
            ],
            selected: {_layout},
            onSelectionChanged: (s) => setState(() => _layout = s.single),
          ),
          const SizedBox(height: 24),
          LimeniaStatementOfReasonsView(
            statement: sampleDecision().statementOfReasons,
            layout: _layout,
            onAppeal: () => openAppealSheet(context),
          ),
        ],
      ),
    );
  }
}

// Restriction

class RestrictionDemo extends StatefulWidget {
  const RestrictionDemo({super.key, this.status = SanctionStatus.suspended, this.fullScreen = false});

  final SanctionStatus status;
  final bool fullScreen;

  @override
  State<RestrictionDemo> createState() => _RestrictionDemoState();
}

class _RestrictionDemoState extends State<RestrictionDemo> {
  late SanctionStatus _status = widget.status;
  late bool _fullScreen = widget.fullScreen;

  SubjectStatus get _subjectStatus => SubjectStatus(
        externalUserId: 'u_112',
        status: _status,
        suspendedUntil: _status == SanctionStatus.suspended ? _start.add(const Duration(days: 7)) : null,
      );

  void _showReasons() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ReasonsDemo(structured: true)),
      );

  @override
  Widget build(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    final title = german ? 'Sperrhinweis' : 'Restriction notice';
    if (_fullScreen && _subjectStatus.isRestrictedAt(DateTime.now())) {
      return DemoScaffold(
        title: title,
        body: LimeniaRestrictionScreen(
          status: _subjectStatus,
          onShowReasons: _showReasons,
          onAppeal: () => openAppealSheet(context),
          footer: TextButton(
            onPressed: () => setState(() => _fullScreen = false),
            child: Text(german ? 'Zurück zur Demo' : 'Back to the demo'),
          ),
        ),
      );
    }
    return DemoScaffold(
      title: title,
      body: DemoColumn(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SanctionStatus.values)
                ChoiceChip(
                  label: Text(s.name),
                  selected: s == _status,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
          SwitchListTile(
            value: _fullScreen,
            onChanged: (v) => setState(() => _fullScreen = v),
            title: Text(german ? 'Als ganze Seite' : 'As a full page'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          LimeniaRestrictionNotice(
            status: _subjectStatus,
            onShowReasons: _showReasons,
            onAppeal: () => openAppealSheet(context),
          ),
          const SizedBox(height: 16),
          for (var i = 1; i <= 3; i++)
            Card.outlined(
              child: ListTile(
                leading: CircleAvatar(child: Text('$i')),
                title: Text(german ? 'Beitrag $i' : 'Post $i'),
                subtitle: Text(german ? 'Ein Beitrag im Feed.' : 'A post in the feed.'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnyLocale<T> extends LocalizationsDelegate<T> {
  const _AnyLocale(this.value);

  final T value;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => SynchronousFuture<T>(value);

  @override
  bool shouldReload(_AnyLocale<T> old) => false;
}
