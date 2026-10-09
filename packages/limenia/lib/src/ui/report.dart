import 'package:flutter/material.dart';
import 'package:limenia/limenia.dart';

import 'common.dart';
import 'strings.dart';

/// What the user entered in the report form, handed to the `onSubmit`
/// callback of [LimeniaReportForm] and [showLimeniaReportSheet].
///
/// Build a [ReportRequest] from it and send it with `Limenia.report`:
///
/// ```dart
/// onSubmit: (draft) => limenia.report(
///   ReportRequest.content(
///     reasonCategory: draft.reasonCategory,
///     reasonText: draft.reasonText,
///     goodFaith: draft.goodFaithConfirmed, // only with ReportSource.user, the default
///     content: ReportedContent(externalContentId: comment.id, contentType: 'comment'),
///     author: ReportedUser(comment.authorId),
///   ),
/// ),
/// ```
@immutable
final class ReportDraft {
  /// Creates a draft.
  const ReportDraft({required this.reasonCategory, this.reasonText, this.goodFaithConfirmed = false});

  /// Code of the chosen category, for [ReportRequest.reasonCategory]. It
  /// passes [ReasonCategory.isValid].
  final String reasonCategory;

  /// The free text of the user as entered, for [ReportRequest.reasonText].
  /// Null if the user wrote nothing but white space. Within
  /// [ReportLimits.reasonTextLength] characters.
  final String? reasonText;

  /// Whether the user confirmed that the report is accurate and complete
  /// (Art. 16(2)(d) DSA), see [GoodFaithConfirmation]. Always false while the
  /// form does not ask for it.
  ///
  /// Pass it on as [ReportRequest.goodFaith] (`limenia` 0.11.0, Limenia API
  /// 0.22.0): Limenia stores it and shows it to moderators. `false` counts as
  /// not confirmed, the same as leaving the field out. Only for a report of
  /// a user ([ReportSource.user], the default of [ReportRequest.content] and
  /// [ReportRequest.user]): with [ReportSource.system] Limenia rejects the
  /// field, also as `false`.
  final bool goodFaithConfirmed;

  @override
  bool operator ==(Object other) =>
      other is ReportDraft &&
      other.reasonCategory == reasonCategory &&
      other.reasonText == reasonText &&
      other.goodFaithConfirmed == goodFaithConfirmed;

  @override
  int get hashCode => Object.hash(reasonCategory, reasonText, goodFaithConfirmed);

  /// Leaves out the text of the user, so that it never ends up in a log.
  @override
  String toString() =>
      'ReportDraft($reasonCategory, reasonText: ${reasonText == null ? 'none' : '${limeniaLength(reasonText!)} characters'}, '
      'goodFaithConfirmed: $goodFaithConfirmed)';
}

/// A category the user can choose in the report form.
@immutable
final class ReportCategoryOption {
  /// Creates a category. [code] must pass [ReasonCategory.isValid]; use the
  /// codes of the policies of the tenant, so that moderators see their titles.
  const ReportCategoryOption({required this.code, required this.label, this.description});

  /// Code sent as [ReportRequest.reasonCategory], e.g. [ReasonCategory.spam].
  final String code;

  /// What the user sees, in the language of the app.
  final String label;

  /// Optional explanation below the label.
  final String? description;

  /// The default categories ([ReasonCategory.defaults]) with the labels of
  /// [strings] ([LimeniaUiStrings.categoryLabels]).
  static List<ReportCategoryOption> defaults(LimeniaUiStrings strings) => [
        for (final code in ReasonCategory.defaults)
          ReportCategoryOption(code: code, label: strings.categoryLabels[code] ?? code),
      ];

  @override
  bool operator ==(Object other) =>
      other is ReportCategoryOption && other.code == code && other.label == label && other.description == description;

  @override
  int get hashCode => Object.hash(code, label, description);
}

/// Whether the report form asks the user to confirm that the report is
/// accurate and complete (Art. 16(2)(d) DSA).
enum GoodFaithConfirmation {
  /// No checkbox. The default.
  hidden,

  /// A checkbox the user may leave unchecked.
  optional,

  /// A checkbox the user must check to send the report.
  required,
}

/// A short hint in the report form for categories where someone may be in
/// danger, e.g. to call the emergency services. Pass null to
/// [LimeniaReportForm.emergencyHint] to never show one.
@immutable
final class ReportEmergencyHint {
  /// Creates a hint for [categories], with [text] or the built-in
  /// [LimeniaUiStrings.emergencyHint].
  const ReportEmergencyHint({this.categories = defaultCategories, this.text});

  /// Self-harm and violence.
  static const defaultCategories = {ReasonCategory.selfHarm, ReasonCategory.violence};

  /// Category codes for which the hint is shown.
  final Set<String> categories;

  /// The text, e.g. with a helpline of your country. Null for
  /// [LimeniaUiStrings.emergencyHint].
  final String? text;
}

/// Shows the report form ([LimeniaReportForm]) in a modal bottom sheet.
///
/// The sheet calls [onSubmit] with what the user entered and shows its
/// result. It completes with the last result when it closes, or null if the
/// user closed it before a result arrived (the report goes on in [onSubmit]).
/// The other arguments are those of [LimeniaReportForm].
///
/// ```dart
/// final result = await showLimeniaReportSheet(
///   context,
///   onSubmit: (draft) => limenia.report(ReportRequest.content(...)),
/// );
/// ```
Future<ReportResult?> showLimeniaReportSheet(
  BuildContext context, {
  required Future<ReportResult> Function(ReportDraft draft) onSubmit,
  List<ReportCategoryOption>? categories,
  GoodFaithConfirmation goodFaith = GoodFaithConfirmation.hidden,
  ReportEmergencyHint? emergencyHint = const ReportEmergencyHint(),
  String? title,
  LimeniaUiStrings? strings,
}) async {
  ReportResult? last;
  await showLimeniaSheet(
    context,
    (sheetContext) => LimeniaReportForm(
      onSubmit: onSubmit,
      categories: categories,
      goodFaith: goodFaith,
      emergencyHint: emergencyHint,
      title: title,
      strings: strings,
      onResult: (result) => last = result,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
  return last;
}

/// A form to report content or a user: a category, an optional text and,
/// if configured, a confirmation of good faith. It never sends anything
/// itself: it calls [onSubmit] and shows the [ReportResult] it returns.
///
/// [showLimeniaReportSheet] shows it in a bottom sheet. To embed it in a page,
/// put it in a scroll view: it is as tall as its content.
///
/// The free text is checked with `validateReport` of package:limenia: at most
/// [ReportLimits.reasonTextLength] characters (Unicode code points), never
/// stricter than Limenia.
class LimeniaReportForm extends StatefulWidget {
  /// Creates the form.
  const LimeniaReportForm({
    super.key,
    required this.onSubmit,
    this.categories,
    this.goodFaith = GoodFaithConfirmation.hidden,
    this.emergencyHint = const ReportEmergencyHint(),
    this.title,
    this.strings,
    this.onResult,
    this.onClose,
  });

  /// Sends the report, usually with `Limenia.report`, and returns its result.
  /// If it throws, the form shows a failure with "Try again" and reports the
  /// error to [FlutterError.reportError].
  final Future<ReportResult> Function(ReportDraft draft) onSubmit;

  /// The categories to choose from, in this order. Null for the default
  /// categories of Limenia ([ReportCategoryOption.defaults]). Every code must
  /// pass [ReasonCategory.isValid] and appear once.
  final List<ReportCategoryOption>? categories;

  /// Whether to ask for a confirmation of good faith. Hidden by default.
  final GoodFaithConfirmation goodFaith;

  /// The hint for categories where someone may be in danger. Null for none.
  final ReportEmergencyHint? emergencyHint;

  /// Title of the form, [LimeniaUiStrings.reportTitle] by default.
  final String? title;

  /// Texts of the form. Null for [LimeniaUiStrings.of].
  final LimeniaUiStrings? strings;

  /// Called with every result of [onSubmit].
  final ValueChanged<ReportResult>? onResult;

  /// Called by the close button. Without it there is none, and the result
  /// stays on screen.
  final VoidCallback? onClose;

  @override
  State<LimeniaReportForm> createState() => _LimeniaReportFormState();
}

class _LimeniaReportFormState extends State<LimeniaReportForm> {
  final _text = TextEditingController();
  String? _category;
  bool _goodFaith = false;
  bool _attempted = false;
  bool _sending = false;

  // The result view: shown once a send has ended, until the user retries.
  bool _done = false;
  ReportResult? _result;
  ReportDraft? _draft;

  @override
  void initState() {
    super.initState();
    _text.addListener(_textChanged);
    _checkCategories();
  }

  @override
  void didUpdateWidget(LimeniaReportForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories) _checkCategories();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _textChanged() => setState(() {});

  void _checkCategories() {
    assert(() {
      final categories = widget.categories;
      if (categories == null) return true;
      if (categories.isEmpty) throw FlutterError('LimeniaReportForm: categories must not be empty.');
      final codes = <String>{};
      for (final category in categories) {
        if (!ReasonCategory.isValid(category.code)) {
          throw FlutterError('LimeniaReportForm: "${category.code}" is not a valid reasonCategory, '
              'which must match ^[a-z0-9_]{2,40}\$.');
        }
        if (!codes.add(category.code)) {
          throw FlutterError('LimeniaReportForm: the category "${category.code}" appears twice.');
        }
      }
      return true;
    }());
  }

  bool get _textTooLong => reportReasonTooLong(_text.text);

  bool get _goodFaithMissing => widget.goodFaith == GoodFaithConfirmation.required && !_goodFaith;

  void _submit() {
    setState(() => _attempted = true);
    final category = _category;
    if (category == null || _textTooLong || _goodFaithMissing) return;
    final text = _text.text;
    _send(
      ReportDraft(
        reasonCategory: category,
        reasonText: text.trim().isEmpty ? null : text,
        goodFaithConfirmed: widget.goodFaith != GoodFaithConfirmation.hidden && _goodFaith,
      ),
    );
  }

  Future<void> _send(ReportDraft draft) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _done = false;
      _draft = draft;
    });
    ReportResult? result;
    try {
      result = await widget.onSubmit(draft);
    } catch (error, stack) {
      reportCallbackError(error, stack, 'while sending a report with LimeniaReportForm');
    }
    if (result != null) widget.onResult?.call(result);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _done = true;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings ?? LimeniaUiStrings.of(context);
    final header = FormHeader(
      title: widget.title ?? strings.reportTitle,
      closeLabel: strings.close,
      onClose: widget.onClose,
    );
    if (_done) {
      final draft = _draft;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 24),
          OutcomePanel(
            outcome: _outcome(_result, strings),
            strings: strings,
            onRetry: draft == null ? null : () => _send(draft),
            onClose: widget.onClose,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 16),
        ..._categoryField(context, strings),
        const SizedBox(height: 16),
        CountedTextField(
          controller: _text,
          label: strings.reportTextLabel,
          hint: strings.reportTextHint,
          limit: ReportLimits.reasonTextLength,
          strings: strings,
          enabled: !_sending,
          errorText: _textTooLong ? strings.textTooLong(ReportLimits.reasonTextLength) : null,
        ),
        if (widget.goodFaith != GoodFaithConfirmation.hidden) ...[
          const SizedBox(height: 8),
          _goodFaithField(context, strings),
        ],
        const SizedBox(height: 24),
        SubmitButton(
          label: strings.reportSubmit,
          sendingLabel: strings.sending,
          sending: _sending,
          onPressed: _submit,
        ),
      ],
    );
  }

  List<Widget> _categoryField(BuildContext context, LimeniaUiStrings strings) {
    final theme = Theme.of(context);
    final categories = widget.categories ?? ReportCategoryOption.defaults(strings);
    final hint = widget.emergencyHint;
    final category = _category;
    return [
      Semantics(
        header: true,
        child: Text(strings.reportCategoryQuestion, style: theme.textTheme.titleSmall),
      ),
      if (_attempted && category == null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(
            liveRegion: true,
            child: Text(
              strings.reportCategoryRequired,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ),
      const SizedBox(height: 4),
      RadioGroup<String>(
        groupValue: category,
        onChanged: (code) {
          if (!_sending) setState(() => _category = code);
        },
        child: Column(
          children: [
            for (final option in categories)
              RadioListTile<String>(
                value: option.code,
                title: Text(option.label),
                subtitle: option.description == null ? null : Text(option.description!),
                enabled: !_sending,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      if (hint != null && category != null && hint.categories.contains(category)) ...[
        const SizedBox(height: 8),
        NoticeBox(
          icon: Icons.health_and_safety_outlined,
          text: hint.text ?? strings.emergencyHint,
          background: theme.colorScheme.tertiaryContainer,
          foreground: theme.colorScheme.onTertiaryContainer,
          liveRegion: true,
        ),
      ],
    ];
  }

  Widget _goodFaithField(BuildContext context, LimeniaUiStrings strings) {
    final theme = Theme.of(context);
    final missing = _attempted && _goodFaithMissing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: _goodFaith,
          onChanged: _sending ? null : (checked) => setState(() => _goodFaith = checked ?? false),
          title: Text(strings.goodFaithLabel),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          isError: missing,
        ),
        if (missing)
          Semantics(
            liveRegion: true,
            child: Text(
              strings.goodFaithRequired,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  static Outcome _outcome(ReportResult? result, LimeniaUiStrings strings) => switch (result) {
        ReportSent(:final reporterWarning) => Outcome(
            kind: OutcomeKind.success,
            title: strings.reportSentTitle,
            message: strings.reportSentMessage,
            notice: reporterWarning == null ? null : strings.reporterWarning,
          ),
        ReportQueued() => Outcome(
            kind: OutcomeKind.queued,
            title: strings.reportQueuedTitle,
            message: strings.reportQueuedMessage,
          ),
        ReportFailed(isReporterSuspended: true, :final suspendedUntil) => Outcome(
            kind: OutcomeKind.failure,
            title: strings.reportFailedTitle,
            message: strings.reporterSuspended(suspendedUntil == null ? null : strings.formatDateTime(suspendedUntil)),
          ),
        ReportExpired() => Outcome(
            kind: OutcomeKind.failure,
            title: strings.reportFailedTitle,
            message: strings.reportExpiredMessage,
            canRetry: true,
          ),
        ReportFailed() || null => Outcome(
            kind: OutcomeKind.failure,
            title: strings.reportFailedTitle,
            message: strings.reportFailedMessage,
            canRetry: true,
          ),
      };
}
