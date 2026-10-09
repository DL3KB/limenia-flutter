import 'package:flutter/widgets.dart';
import 'package:limenia/limenia.dart';

/// The texts of the Limenia widgets, with built-in German ([de]) and English
/// ([en]) versions.
///
/// The widgets pick the strings in this order:
///
/// 1. the `strings` argument of a widget or `show…` function,
/// 2. the nearest [LimeniaUiStringsScope],
/// 3. [forLocale] with the locale of the app (`Localizations.localeOf`):
///    German for `de`, English for every other language.
///
/// Change single texts with [copyWith], e.g. the emergency hint with the
/// number of a helpline:
///
/// ```dart
/// LimeniaUiStrings.de.copyWith(emergencyHint: 'Du brauchst Hilfe? …')
/// ```
///
/// Texts with values are functions, such as [suspendedMessage]. Dates and times
/// arrive there already formatted by [formatDate] or [formatDateTime], in the
/// local time zone of the device.
///
/// The texts of the tenant (the ready-made statement of reasons, the facts
/// written by the moderator, the titles of the policies and the redress text)
/// come from Limenia in the language of the tenant and are shown unchanged.
@immutable
final class LimeniaUiStrings {
  /// Creates a complete set of strings. Usually you start from [de] or [en]
  /// and change single texts with [copyWith].
  const LimeniaUiStrings({
    required this.close,
    required this.tryAgain,
    required this.sending,
    required this.characterCount,
    required this.textTooLong,
    required this.formatDate,
    required this.formatDateTime,
    required this.reportTitle,
    required this.reportCategoryQuestion,
    required this.reportCategoryRequired,
    required this.categoryLabels,
    required this.reportTextLabel,
    required this.reportTextHint,
    required this.goodFaithLabel,
    required this.goodFaithRequired,
    required this.emergencyHint,
    required this.reportSubmit,
    required this.reportSentTitle,
    required this.reportSentMessage,
    required this.reportQueuedTitle,
    required this.reportQueuedMessage,
    required this.reportFailedTitle,
    required this.reportFailedMessage,
    required this.reportExpiredMessage,
    required this.reporterWarning,
    required this.reporterSuspended,
    required this.appealTitle,
    required this.appealTopicLabel,
    required this.appealDecidedOn,
    required this.appealInfo,
    required this.appealDeadline,
    required this.appealTextLabel,
    required this.appealTextHint,
    required this.appealTextRequired,
    required this.appealSubmit,
    required this.appealSentTitle,
    required this.appealSentMessage,
    required this.appealQueuedTitle,
    required this.appealQueuedMessage,
    required this.appealFailedTitle,
    required this.appealFailedMessage,
    required this.appealExpiredMessage,
    required this.appealWindowClosed,
    required this.appealAlreadyOpen,
    required this.appealNotAllowed,
    required this.appealReporterSuspended,
    required this.actionLabels,
    required this.sorMeasure,
    required this.sorEndsAt,
    required this.sorScope,
    required this.sorScopeApp,
    required this.sorFacts,
    required this.sorNoticeSource,
    required this.sorNoticeSourceNotice,
    required this.sorNoticeSourceTrustedFlagger,
    required this.sorNoticeSourceOwnInitiative,
    required this.sorAutomation,
    required this.sorAutomationNone,
    required this.sorAutomatedDetection,
    required this.sorAutomationPartial,
    required this.sorAutomationFull,
    required this.sorGrounds,
    required this.sorGroundTerms,
    required this.sorGroundLaw,
    required this.sorRedress,
    required this.submitComplaint,
    required this.showReasons,
    required this.warnedTitle,
    required this.warnedMessage,
    required this.suspendedTitle,
    required this.suspendedMessage,
    required this.bannedTitle,
    required this.bannedMessage,
  });

  // General

  /// Button and tooltip that closes a sheet or a result.
  final String close;

  /// Button that sends a failed report or complaint again.
  final String tryAgain;

  /// Shown, and read by screen readers, while a report or complaint is sent.
  final String sending;

  /// Counter below a text field: [count] characters of at most [limit].
  final String Function(int count, int limit) characterCount;

  /// Error of a text field whose text is longer than [limit] characters.
  final String Function(int limit) textTooLong;

  /// A date without time, in the local time zone of the device.
  final String Function(DateTime date) formatDate;

  /// A date with time, in the local time zone of the device.
  final String Function(DateTime dateTime) formatDateTime;

  // Report

  /// Title of the report sheet.
  final String reportTitle;

  /// Question above the categories of a report.
  final String reportCategoryQuestion;

  /// Error when the user sends a report without a category.
  final String reportCategoryRequired;

  /// Labels of the default categories ([ReasonCategory.defaults]) by code,
  /// matching the default policies Limenia creates for every tenant.
  final Map<String, String> categoryLabels;

  /// Label of the optional free text of a report.
  final String reportTextLabel;

  /// Hint inside the empty free text field of a report.
  final String reportTextHint;

  /// Label of the checkbox that confirms a report in good faith
  /// (Art. 16(2)(d) DSA), see `GoodFaithConfirmation`.
  final String goodFaithLabel;

  /// Error when the good-faith confirmation is required and not checked.
  final String goodFaithRequired;

  /// Hint shown for the categories of a `ReportEmergencyHint`, e.g. self-harm
  /// and violence, unless the hint brings its own text.
  final String emergencyHint;

  /// Button that sends a report.
  final String reportSubmit;

  /// Title after Limenia has the report ([ReportSent]).
  final String reportSentTitle;

  /// Message after Limenia has the report ([ReportSent]).
  final String reportSentMessage;

  /// Title when the report waits for a connection ([ReportQueued]).
  final String reportQueuedTitle;

  /// Message when the report waits for a connection ([ReportQueued]).
  final String reportQueuedMessage;

  /// Title when the report could not be sent ([ReportFailed], [ReportExpired]
  /// or an error of the callback).
  final String reportFailedTitle;

  /// Message when the report could not be sent and may succeed when tried
  /// again.
  final String reportFailedMessage;

  /// Message when the report waited too long and was dropped
  /// ([ReportExpired]).
  final String reportExpiredMessage;

  /// Warning for a reporter whose reports were often manifestly unfounded
  /// (Art. 23 DSA, [ReportSent.reporterWarning]).
  final String reporterWarning;

  /// Message when Limenia does not process the reports of this person
  /// ([ReportFailed.isReporterSuspended]), with the formatted end of the
  /// suspension or null if it is not known.
  final String Function(String? until) reporterSuspended;

  // Complaint

  /// Title of the complaint form, also of the button that opens it.
  final String appealTitle;

  /// Label above the summary of the decision the complaint is about.
  final String appealTopicLabel;

  /// When the decision was taken, with the formatted [date].
  final String Function(String date) appealDecidedOn;

  /// What a complaint is: the six-month window, free of charge, decided by a
  /// person (Art. 20 DSA).
  final String appealInfo;

  /// Until when a complaint is possible, with the formatted [date].
  final String Function(String date) appealDeadline;

  /// Label of the text field of a complaint.
  final String appealTextLabel;

  /// Hint inside the empty text field of a complaint.
  final String appealTextHint;

  /// Error when the user sends a complaint without text.
  final String appealTextRequired;

  /// Button that sends a complaint.
  final String appealSubmit;

  /// Title after Limenia has the complaint ([AppealSent]).
  final String appealSentTitle;

  /// Message after Limenia has the complaint ([AppealSent]).
  final String appealSentMessage;

  /// Title when the complaint waits for a connection ([AppealQueued]).
  final String appealQueuedTitle;

  /// Message when the complaint waits for a connection ([AppealQueued]).
  final String appealQueuedMessage;

  /// Title when the complaint could not be sent ([AppealFailed],
  /// [AppealExpired] or an error of the callback).
  final String appealFailedTitle;

  /// Message when the complaint could not be sent and may succeed when tried
  /// again.
  final String appealFailedMessage;

  /// Message when the complaint waited too long and was dropped
  /// ([AppealExpired]).
  final String appealExpiredMessage;

  /// Message for `appeal_window_closed`: the six months have passed.
  final String appealWindowClosed;

  /// Message for `appeal_already_open`: this person already has an open
  /// complaint against the decision.
  final String appealAlreadyOpen;

  /// Message for `appeal_not_allowed`: this person cannot complain against
  /// this decision.
  final String appealNotAllowed;

  /// Message for `reporter_suspended` ([AppealFailed.isReporterSuspended]),
  /// with the formatted end of the suspension or null if it is not known.
  final String Function(String? until) appealReporterSuspended;

  // Decisions and statement of reasons

  /// The measure of a decision by action, e.g. in the statement of reasons and
  /// the summary of a complaint.
  final Map<ModerationAction, String> actionLabels;

  /// Label of the measure in the statement of reasons.
  final String sorMeasure;

  /// Label of the end of a temporary restriction ([SorDetails.endsAt]).
  final String sorEndsAt;

  /// Label of the territorial scope ([SorDetails.territorialScope]).
  final String sorScope;

  /// The territorial scope `app`: the whole app.
  final String sorScopeApp;

  /// Label of the facts written by the moderator ([SorDetails.facts]).
  final String sorFacts;

  /// Label of what led to the decision ([SorDetails.noticeSource]).
  final String sorNoticeSource;

  /// [NoticeSource.notice]: reports of users.
  final String sorNoticeSourceNotice;

  /// [NoticeSource.trustedFlagger]: a report of a trusted flagger (Art. 22
  /// DSA), never with its name.
  final String sorNoticeSourceTrustedFlagger;

  /// [NoticeSource.ownInitiative]: an own review of the provider.
  final String sorNoticeSourceOwnInitiative;

  /// Label of the use of automated means (Art. 17(3)(c) DSA).
  final String sorAutomation;

  /// [Automation.none] without [SorDetails.automatedDetection]: no automated
  /// means were used.
  final String sorAutomationNone;

  /// [SorDetails.automatedDetection]: the matter was detected automatically,
  /// a person decided.
  final String sorAutomatedDetection;

  /// [Automation.partial]: a moderator took and confirmed the suggestion of an
  /// automated assessment.
  final String sorAutomationPartial;

  /// [Automation.full]: an automatic decision without a moderator.
  final String sorAutomationFull;

  /// Label of the grounds of a decision ([SorDetails.grounds]).
  final String sorGrounds;

  /// A ground with [LegalBasis.terms]: a violation of the terms of the app.
  final String sorGroundTerms;

  /// A ground with [LegalBasis.law]: illegal content, with the law reference
  /// of the policy or null if it has none.
  final String Function(String? lawReference) sorGroundLaw;

  /// Label of the redress text of the tenant ([SorDetails.redress]).
  final String sorRedress;

  /// Button that starts a complaint against a decision.
  final String submitComplaint;

  /// Button that shows the statement of reasons of a restriction.
  final String showReasons;

  // Restrictions

  /// Title of the notice for a warned user ([SanctionStatus.warned]).
  final String warnedTitle;

  /// Message of the notice for a warned user.
  final String warnedMessage;

  /// Title of the notice for a suspended user ([SanctionStatus.suspended]).
  final String suspendedTitle;

  /// Message for a suspended user, with the formatted end of the suspension or
  /// null if it is not known.
  final String Function(String? until) suspendedMessage;

  /// Title of the notice for a banned user ([SanctionStatus.banned]).
  final String bannedTitle;

  /// Message of the notice for a banned user.
  final String bannedMessage;

  /// German strings, informal ("du").
  static const de = LimeniaUiStrings(
    close: 'Schließen',
    tryAgain: 'Erneut versuchen',
    sending: 'Wird gesendet …',
    characterCount: _characterCount,
    textTooLong: _deTextTooLong,
    formatDate: _deFormatDate,
    formatDateTime: _deFormatDateTime,
    reportTitle: 'Melden',
    reportCategoryQuestion: 'Warum meldest du das?',
    reportCategoryRequired: 'Bitte wähle einen Grund aus.',
    categoryLabels: {
      ReasonCategory.spam: 'Spam',
      ReasonCategory.harassmentHate: 'Belästigung und Hassrede',
      ReasonCategory.violence: 'Gewalt',
      ReasonCategory.sexualContent: 'Sexuelle Inhalte',
      ReasonCategory.childSafety: 'Schutz von Minderjährigen',
      ReasonCategory.fraud: 'Betrug',
      ReasonCategory.copyright: 'Urheberrecht',
      ReasonCategory.privacy: 'Datenschutz',
      ReasonCategory.selfHarm: 'Selbstgefährdung',
      ReasonCategory.other: 'Sonstiges',
    },
    reportTextLabel: 'Details (optional)',
    reportTextHint: 'Was genau ist das Problem?',
    goodFaithLabel: 'Ich bestätige, dass meine Angaben nach bestem Wissen richtig und vollständig sind.',
    goodFaithRequired: 'Bitte bestätige deine Angaben.',
    emergencyHint: 'Ist jemand in akuter Gefahr? Dann ruf sofort den Notruf an, in der EU die 112. '
        'Eine Meldung hier ersetzt keine Hilfe im Notfall.',
    reportSubmit: 'Meldung senden',
    reportSentTitle: 'Danke für deine Meldung',
    reportSentMessage: 'Wir sehen sie uns an.',
    reportQueuedTitle: 'Meldung gespeichert',
    reportQueuedMessage: 'Wir senden sie, sobald du wieder online bist.',
    reportFailedTitle: 'Meldung nicht gesendet',
    reportFailedMessage: 'Das hat leider nicht geklappt. Versuch es bitte noch einmal.',
    reportExpiredMessage: 'Deine Meldung konnte nicht rechtzeitig gesendet werden. Bitte melde es noch einmal.',
    reporterWarning: 'Mehrere deiner Meldungen waren offensichtlich unbegründet. Weitere solche Meldungen können '
        'dazu führen, dass wir deine Meldungen eine Zeit lang nicht bearbeiten.',
    reporterSuspended: _deReporterSuspended,
    appealTitle: 'Beschwerde einreichen',
    appealTopicLabel: 'Entscheidung',
    appealDecidedOn: _deAppealDecidedOn,
    appealInfo: 'Du kannst dich bis zu sechs Monate nach der Entscheidung beschweren. Das ist kostenlos, und ein '
        'Mensch prüft deine Beschwerde.',
    appealDeadline: _deAppealDeadline,
    appealTextLabel: 'Deine Begründung',
    appealTextHint: 'Warum ist die Entscheidung aus deiner Sicht falsch?',
    appealTextRequired: 'Bitte schreib kurz, warum du dich beschwerst.',
    appealSubmit: 'Beschwerde senden',
    appealSentTitle: 'Beschwerde eingegangen',
    appealSentMessage: 'Ein Mensch prüft deine Beschwerde, und du bekommst eine Antwort.',
    appealQueuedTitle: 'Beschwerde gespeichert',
    appealQueuedMessage: 'Wir senden sie, sobald du wieder online bist.',
    appealFailedTitle: 'Beschwerde nicht gesendet',
    appealFailedMessage: 'Das hat leider nicht geklappt. Versuch es bitte noch einmal.',
    appealExpiredMessage:
        'Deine Beschwerde konnte nicht rechtzeitig gesendet werden. Bitte reiche sie noch einmal ein.',
    appealWindowClosed: 'Die Frist für eine Beschwerde gegen diese Entscheidung ist abgelaufen.',
    appealAlreadyOpen: 'Du hast gegen diese Entscheidung schon eine Beschwerde eingereicht. Du bekommst eine Antwort, '
        'sobald sie geprüft ist.',
    appealNotAllowed: 'Gegen diese Entscheidung kannst du keine Beschwerde einreichen.',
    appealReporterSuspended: _deAppealReporterSuspended,
    actionLabels: {
      ModerationAction.dismiss: 'Keine Maßnahme, es wurde kein Verstoß festgestellt',
      ModerationAction.removeContent: 'Entfernung des Inhalts',
      ModerationAction.restrictContent: 'Einschränkung der Sichtbarkeit des Inhalts',
      ModerationAction.warnUser: 'Verwarnung',
      ModerationAction.suspendUser: 'Vorübergehende Sperre des Kontos',
      ModerationAction.banUser: 'Dauerhafte Sperre des Kontos',
      ModerationAction.restore: 'Aufhebung einer früheren Einschränkung',
      ModerationAction.rejectSubmission: 'Ablehnung der Veröffentlichung des Inhalts',
    },
    sorMeasure: 'Maßnahme',
    sorEndsAt: 'Endet am',
    sorScope: 'Geltungsbereich',
    sorScopeApp: 'Die gesamte App',
    sorFacts: 'Sachverhalt',
    sorNoticeSource: 'Anlass',
    sorNoticeSourceNotice: 'Eine Meldung durch andere Nutzer',
    sorNoticeSourceTrustedFlagger: 'Die Meldung eines vertrauenswürdigen Hinweisgebers',
    sorNoticeSourceOwnInitiative: 'Eine eigene Prüfung',
    sorAutomation: 'Automatisierte Mittel',
    sorAutomationNone: 'Für die Erkennung und die Entscheidung wurden keine automatisierten Mittel eingesetzt.',
    sorAutomatedDetection: 'Der Anlass wurde automatisiert erkannt, entschieden hat ein Mensch.',
    sorAutomationPartial: 'Ein automatisiertes System hat den Inhalt eingeschätzt und diese Entscheidung '
        'vorgeschlagen. Ein Mensch hat den Vorschlag geprüft und die Entscheidung getroffen.',
    sorAutomationFull: 'Die Entscheidung wurde automatisiert getroffen, ohne Prüfung durch einen Menschen.',
    sorGrounds: 'Grundlage',
    sorGroundTerms: 'Verstoß gegen die Nutzungsbedingungen',
    sorGroundLaw: _deGroundLaw,
    sorRedress: 'Rechtsbehelfe',
    submitComplaint: 'Beschwerde einreichen',
    showReasons: 'Begründung ansehen',
    warnedTitle: 'Verwarnung',
    warnedMessage: 'Du hast eine Verwarnung erhalten. Dein Konto kannst du weiter nutzen.',
    suspendedTitle: 'Konto vorübergehend gesperrt',
    suspendedMessage: _deSuspendedMessage,
    bannedTitle: 'Konto dauerhaft gesperrt',
    bannedMessage: 'Dein Konto wurde dauerhaft gesperrt.',
  );

  /// English strings.
  static const en = LimeniaUiStrings(
    close: 'Close',
    tryAgain: 'Try again',
    sending: 'Sending…',
    characterCount: _characterCount,
    textTooLong: _enTextTooLong,
    formatDate: _enFormatDate,
    formatDateTime: _enFormatDateTime,
    reportTitle: 'Report',
    reportCategoryQuestion: 'Why are you reporting this?',
    reportCategoryRequired: 'Please choose a reason.',
    categoryLabels: {
      ReasonCategory.spam: 'Spam',
      ReasonCategory.harassmentHate: 'Harassment and hate speech',
      ReasonCategory.violence: 'Violence',
      ReasonCategory.sexualContent: 'Sexual content',
      ReasonCategory.childSafety: 'Protection of minors',
      ReasonCategory.fraud: 'Fraud',
      ReasonCategory.copyright: 'Copyright',
      ReasonCategory.privacy: 'Privacy',
      ReasonCategory.selfHarm: 'Self-harm',
      ReasonCategory.other: 'Other',
    },
    reportTextLabel: 'Details (optional)',
    reportTextHint: 'What exactly is the problem?',
    goodFaithLabel: 'I confirm that the information in this report is accurate and complete to the best of my '
        'knowledge.',
    goodFaithRequired: 'Please confirm your information.',
    emergencyHint: 'Is someone in immediate danger? Call the emergency services right away, 112 in the EU. '
        'A report here is no substitute for help in an emergency.',
    reportSubmit: 'Send report',
    reportSentTitle: 'Thanks for your report',
    reportSentMessage: 'We will review it.',
    reportQueuedTitle: 'Report saved',
    reportQueuedMessage: 'It will be sent as soon as you are online.',
    reportFailedTitle: 'Report not sent',
    reportFailedMessage: 'Something went wrong. Please try again.',
    reportExpiredMessage: 'Your report could not be sent in time. Please report it again.',
    reporterWarning: 'Several of your reports were manifestly unfounded. Further such reports can lead to us not '
        'processing your reports for a while.',
    reporterSuspended: _enReporterSuspended,
    appealTitle: 'Submit a complaint',
    appealTopicLabel: 'Decision',
    appealDecidedOn: _enAppealDecidedOn,
    appealInfo: 'You can complain up to six months after the decision. It is free of charge, and a person will '
        'review your complaint.',
    appealDeadline: _enAppealDeadline,
    appealTextLabel: 'Your reasons',
    appealTextHint: 'Why do you think the decision is wrong?',
    appealTextRequired: 'Please write briefly why you are complaining.',
    appealSubmit: 'Send complaint',
    appealSentTitle: 'Complaint received',
    appealSentMessage: 'A person will review your complaint, and you will get an answer.',
    appealQueuedTitle: 'Complaint saved',
    appealQueuedMessage: 'It will be sent as soon as you are online.',
    appealFailedTitle: 'Complaint not sent',
    appealFailedMessage: 'Something went wrong. Please try again.',
    appealExpiredMessage: 'Your complaint could not be sent in time. Please submit it again.',
    appealWindowClosed: 'The deadline for a complaint against this decision has passed.',
    appealAlreadyOpen: 'You have already submitted a complaint against this decision. You will get an answer once '
        'it has been reviewed.',
    appealNotAllowed: 'You cannot submit a complaint against this decision.',
    appealReporterSuspended: _enAppealReporterSuspended,
    actionLabels: {
      ModerationAction.dismiss: 'No measure, no violation was found',
      ModerationAction.removeContent: 'Removal of the content',
      ModerationAction.restrictContent: 'Restricted visibility of the content',
      ModerationAction.warnUser: 'Warning',
      ModerationAction.suspendUser: 'Temporary suspension of the account',
      ModerationAction.banUser: 'Permanent suspension of the account',
      ModerationAction.restore: 'Lifting of an earlier restriction',
      ModerationAction.rejectSubmission: 'Refusal to publish the content',
    },
    sorMeasure: 'Measure',
    sorEndsAt: 'Ends on',
    sorScope: 'Scope',
    sorScopeApp: 'The whole app',
    sorFacts: 'Facts',
    sorNoticeSource: 'What led to the decision',
    sorNoticeSourceNotice: 'A report by other users',
    sorNoticeSourceTrustedFlagger: 'A report by a trusted flagger',
    sorNoticeSourceOwnInitiative: 'Our own review',
    sorAutomation: 'Automated means',
    sorAutomationNone: 'No automated means were used to detect the matter or to decide.',
    sorAutomatedDetection: 'The matter was detected by automated means; a person decided.',
    sorAutomationPartial: 'An automated system assessed the content and suggested this decision. A person reviewed '
        'the suggestion and took the decision.',
    sorAutomationFull: 'The decision was taken by automated means, without review by a person.',
    sorGrounds: 'Grounds',
    sorGroundTerms: 'Violation of the terms of service',
    sorGroundLaw: _enGroundLaw,
    sorRedress: 'Redress',
    submitComplaint: 'Submit a complaint',
    showReasons: 'Show reasons',
    warnedTitle: 'Warning',
    warnedMessage: 'You have received a warning. You can still use your account.',
    suspendedTitle: 'Account temporarily suspended',
    suspendedMessage: _enSuspendedMessage,
    bannedTitle: 'Account permanently suspended',
    bannedMessage: 'Your account has been permanently suspended.',
  );

  /// The built-in strings for [locale]: [de] for German, [en] for every other
  /// language.
  static LimeniaUiStrings forLocale(Locale locale) => locale.languageCode == 'de' ? de : en;

  /// The strings for the widgets at [context]: from the nearest
  /// [LimeniaUiStringsScope], otherwise [forLocale] with the locale of the app
  /// (English without one).
  static LimeniaUiStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    final scope = context.dependOnInheritedWidgetOfExactType<LimeniaUiStringsScope>();
    return scope == null ? forLocale(locale) : scope.strings(locale);
  }

  /// A copy with the given texts replaced.
  LimeniaUiStrings copyWith({
    String? close,
    String? tryAgain,
    String? sending,
    String Function(int count, int limit)? characterCount,
    String Function(int limit)? textTooLong,
    String Function(DateTime date)? formatDate,
    String Function(DateTime dateTime)? formatDateTime,
    String? reportTitle,
    String? reportCategoryQuestion,
    String? reportCategoryRequired,
    Map<String, String>? categoryLabels,
    String? reportTextLabel,
    String? reportTextHint,
    String? goodFaithLabel,
    String? goodFaithRequired,
    String? emergencyHint,
    String? reportSubmit,
    String? reportSentTitle,
    String? reportSentMessage,
    String? reportQueuedTitle,
    String? reportQueuedMessage,
    String? reportFailedTitle,
    String? reportFailedMessage,
    String? reportExpiredMessage,
    String? reporterWarning,
    String Function(String? until)? reporterSuspended,
    String? appealTitle,
    String? appealTopicLabel,
    String Function(String date)? appealDecidedOn,
    String? appealInfo,
    String Function(String date)? appealDeadline,
    String? appealTextLabel,
    String? appealTextHint,
    String? appealTextRequired,
    String? appealSubmit,
    String? appealSentTitle,
    String? appealSentMessage,
    String? appealQueuedTitle,
    String? appealQueuedMessage,
    String? appealFailedTitle,
    String? appealFailedMessage,
    String? appealExpiredMessage,
    String? appealWindowClosed,
    String? appealAlreadyOpen,
    String? appealNotAllowed,
    String Function(String? until)? appealReporterSuspended,
    Map<ModerationAction, String>? actionLabels,
    String? sorMeasure,
    String? sorEndsAt,
    String? sorScope,
    String? sorScopeApp,
    String? sorFacts,
    String? sorNoticeSource,
    String? sorNoticeSourceNotice,
    String? sorNoticeSourceTrustedFlagger,
    String? sorNoticeSourceOwnInitiative,
    String? sorAutomation,
    String? sorAutomationNone,
    String? sorAutomatedDetection,
    String? sorAutomationPartial,
    String? sorAutomationFull,
    String? sorGrounds,
    String? sorGroundTerms,
    String Function(String? lawReference)? sorGroundLaw,
    String? sorRedress,
    String? submitComplaint,
    String? showReasons,
    String? warnedTitle,
    String? warnedMessage,
    String? suspendedTitle,
    String Function(String? until)? suspendedMessage,
    String? bannedTitle,
    String? bannedMessage,
  }) =>
      LimeniaUiStrings(
        close: close ?? this.close,
        tryAgain: tryAgain ?? this.tryAgain,
        sending: sending ?? this.sending,
        characterCount: characterCount ?? this.characterCount,
        textTooLong: textTooLong ?? this.textTooLong,
        formatDate: formatDate ?? this.formatDate,
        formatDateTime: formatDateTime ?? this.formatDateTime,
        reportTitle: reportTitle ?? this.reportTitle,
        reportCategoryQuestion: reportCategoryQuestion ?? this.reportCategoryQuestion,
        reportCategoryRequired: reportCategoryRequired ?? this.reportCategoryRequired,
        categoryLabels: categoryLabels ?? this.categoryLabels,
        reportTextLabel: reportTextLabel ?? this.reportTextLabel,
        reportTextHint: reportTextHint ?? this.reportTextHint,
        goodFaithLabel: goodFaithLabel ?? this.goodFaithLabel,
        goodFaithRequired: goodFaithRequired ?? this.goodFaithRequired,
        emergencyHint: emergencyHint ?? this.emergencyHint,
        reportSubmit: reportSubmit ?? this.reportSubmit,
        reportSentTitle: reportSentTitle ?? this.reportSentTitle,
        reportSentMessage: reportSentMessage ?? this.reportSentMessage,
        reportQueuedTitle: reportQueuedTitle ?? this.reportQueuedTitle,
        reportQueuedMessage: reportQueuedMessage ?? this.reportQueuedMessage,
        reportFailedTitle: reportFailedTitle ?? this.reportFailedTitle,
        reportFailedMessage: reportFailedMessage ?? this.reportFailedMessage,
        reportExpiredMessage: reportExpiredMessage ?? this.reportExpiredMessage,
        reporterWarning: reporterWarning ?? this.reporterWarning,
        reporterSuspended: reporterSuspended ?? this.reporterSuspended,
        appealTitle: appealTitle ?? this.appealTitle,
        appealTopicLabel: appealTopicLabel ?? this.appealTopicLabel,
        appealDecidedOn: appealDecidedOn ?? this.appealDecidedOn,
        appealInfo: appealInfo ?? this.appealInfo,
        appealDeadline: appealDeadline ?? this.appealDeadline,
        appealTextLabel: appealTextLabel ?? this.appealTextLabel,
        appealTextHint: appealTextHint ?? this.appealTextHint,
        appealTextRequired: appealTextRequired ?? this.appealTextRequired,
        appealSubmit: appealSubmit ?? this.appealSubmit,
        appealSentTitle: appealSentTitle ?? this.appealSentTitle,
        appealSentMessage: appealSentMessage ?? this.appealSentMessage,
        appealQueuedTitle: appealQueuedTitle ?? this.appealQueuedTitle,
        appealQueuedMessage: appealQueuedMessage ?? this.appealQueuedMessage,
        appealFailedTitle: appealFailedTitle ?? this.appealFailedTitle,
        appealFailedMessage: appealFailedMessage ?? this.appealFailedMessage,
        appealExpiredMessage: appealExpiredMessage ?? this.appealExpiredMessage,
        appealWindowClosed: appealWindowClosed ?? this.appealWindowClosed,
        appealAlreadyOpen: appealAlreadyOpen ?? this.appealAlreadyOpen,
        appealNotAllowed: appealNotAllowed ?? this.appealNotAllowed,
        appealReporterSuspended: appealReporterSuspended ?? this.appealReporterSuspended,
        actionLabels: actionLabels ?? this.actionLabels,
        sorMeasure: sorMeasure ?? this.sorMeasure,
        sorEndsAt: sorEndsAt ?? this.sorEndsAt,
        sorScope: sorScope ?? this.sorScope,
        sorScopeApp: sorScopeApp ?? this.sorScopeApp,
        sorFacts: sorFacts ?? this.sorFacts,
        sorNoticeSource: sorNoticeSource ?? this.sorNoticeSource,
        sorNoticeSourceNotice: sorNoticeSourceNotice ?? this.sorNoticeSourceNotice,
        sorNoticeSourceTrustedFlagger: sorNoticeSourceTrustedFlagger ?? this.sorNoticeSourceTrustedFlagger,
        sorNoticeSourceOwnInitiative: sorNoticeSourceOwnInitiative ?? this.sorNoticeSourceOwnInitiative,
        sorAutomation: sorAutomation ?? this.sorAutomation,
        sorAutomationNone: sorAutomationNone ?? this.sorAutomationNone,
        sorAutomatedDetection: sorAutomatedDetection ?? this.sorAutomatedDetection,
        sorAutomationPartial: sorAutomationPartial ?? this.sorAutomationPartial,
        sorAutomationFull: sorAutomationFull ?? this.sorAutomationFull,
        sorGrounds: sorGrounds ?? this.sorGrounds,
        sorGroundTerms: sorGroundTerms ?? this.sorGroundTerms,
        sorGroundLaw: sorGroundLaw ?? this.sorGroundLaw,
        sorRedress: sorRedress ?? this.sorRedress,
        submitComplaint: submitComplaint ?? this.submitComplaint,
        showReasons: showReasons ?? this.showReasons,
        warnedTitle: warnedTitle ?? this.warnedTitle,
        warnedMessage: warnedMessage ?? this.warnedMessage,
        suspendedTitle: suspendedTitle ?? this.suspendedTitle,
        suspendedMessage: suspendedMessage ?? this.suspendedMessage,
        bannedTitle: bannedTitle ?? this.bannedTitle,
        bannedMessage: bannedMessage ?? this.bannedMessage,
      );
}

/// Overrides the strings of the Limenia widgets below it, per locale.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => LimeniaUiStringsScope(
///     strings: (locale) => LimeniaUiStrings.forLocale(locale).copyWith(reportTitle: 'Beitrag melden'),
///     child: child!,
///   ),
/// )
/// ```
///
/// Put it above the [Navigator] (in `MaterialApp.builder`) to reach every
/// route. The `show…` functions of this package also take the scope of the
/// context they are called with into their sheet.
class LimeniaUiStringsScope extends InheritedWidget {
  /// Creates a scope that gives the widgets below it the strings of
  /// [strings] for the locale of the app.
  const LimeniaUiStringsScope({super.key, required this.strings, required super.child});

  /// The strings for a locale, e.g. [LimeniaUiStrings.forLocale] with some
  /// texts changed.
  final LimeniaUiStrings Function(Locale locale) strings;

  /// The nearest scope above [context], or null.
  static LimeniaUiStringsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LimeniaUiStringsScope>();

  @override
  bool updateShouldNotify(LimeniaUiStringsScope oldWidget) => strings != oldWidget.strings;
}

/// The end of the window for a complaint against a decision taken at
/// [decidedAt], as Limenia computes it: six calendar months later, on the
/// last day of the target month if it is shorter (31 August to 28 February),
/// at the time of day of the decision. In UTC.
///
/// Limenia sends this date to reporters as `appealDeadline`
/// ([ReportsResolution.appealDeadline]); for the affected user the app
/// computes it from [ModerationDecision.decidedAt].
DateTime appealDeadlineFor(DateTime decidedAt) {
  final d = decidedAt.toUtc();
  final first = DateTime.utc(d.year, d.month + 6);
  final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(
    first.year,
    first.month,
    d.day > lastDay ? lastDay : d.day,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
    d.microsecond,
  );
}

String _two(int n) => n.toString().padLeft(2, '0');

String _characterCount(int count, int limit) => '$count / $limit';

String _deTextTooLong(int limit) => 'Bitte kürze deinen Text auf höchstens $limit Zeichen.';

String _enTextTooLong(int limit) => 'Please shorten your text to at most $limit characters.';

/// `07.10.2026`
String _deFormatDate(DateTime date) {
  final t = date.toLocal();
  return '${_two(t.day)}.${_two(t.month)}.${t.year}';
}

/// `07.10.2026 14:30`
String _deFormatDateTime(DateTime dateTime) {
  final t = dateTime.toLocal();
  return '${_deFormatDate(t)} ${_two(t.hour)}:${_two(t.minute)}';
}

const _enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `Oct 7, 2026`
String _enFormatDate(DateTime date) {
  final t = date.toLocal();
  return '${_enMonths[t.month - 1]} ${t.day}, ${t.year}';
}

/// `Oct 7, 2026, 14:30`
String _enFormatDateTime(DateTime dateTime) {
  final t = dateTime.toLocal();
  return '${_enFormatDate(t)}, ${_two(t.hour)}:${_two(t.minute)}';
}

String _deReporterSuspended(String? until) => until == null
    ? 'Wir bearbeiten deine Meldungen zurzeit nicht, weil mehrere davon offensichtlich unbegründet waren.'
    : 'Wir bearbeiten deine Meldungen bis zum $until nicht, weil mehrere davon offensichtlich unbegründet waren.';

String _enReporterSuspended(String? until) => until == null
    ? 'We are not processing your reports at the moment because several of them were manifestly unfounded.'
    : 'We will not process your reports until $until because several of them were manifestly unfounded.';

String _deAppealDecidedOn(String date) => 'Entschieden am $date';

String _enAppealDecidedOn(String date) => 'Decided on $date';

String _deAppealDeadline(String date) => 'Du kannst dich bis zum $date beschweren.';

String _enAppealDeadline(String date) => 'You can complain until $date.';

String _deAppealReporterSuspended(String? until) => until == null
    ? 'Als meldende Person kannst du dich zurzeit nicht beschweren.'
    : 'Als meldende Person kannst du dich bis zum $until nicht beschweren.';

String _enAppealReporterSuspended(String? until) => until == null
    ? 'You cannot submit complaints as a reporter at the moment.'
    : 'You cannot submit complaints as a reporter until $until.';

String _deGroundLaw(String? lawReference) =>
    lawReference == null || lawReference.isEmpty ? 'Rechtswidriger Inhalt' : 'Rechtswidriger Inhalt: $lawReference';

String _enGroundLaw(String? lawReference) =>
    lawReference == null || lawReference.isEmpty ? 'Illegal content' : 'Illegal content: $lawReference';

String _deSuspendedMessage(String? until) =>
    until == null ? 'Dein Konto ist vorübergehend gesperrt.' : 'Dein Konto ist bis zum $until gesperrt.';

String _enSuspendedMessage(String? until) =>
    until == null ? 'Your account is temporarily suspended.' : 'Your account is suspended until $until.';
