import 'package:flutter/material.dart';
import 'package:limenia/limenia.dart';

import 'common.dart';
import 'strings.dart';

/// What a complaint is about, shown at the top of the complaint form: a
/// short summary of the decision and the end of the window for a complaint.
///
/// Every field is optional; the form shows what is there.
@immutable
final class AppealTopic {
  /// Creates a topic from single values, e.g. only a [title].
  const AppealTopic({this.title, this.action, this.policyTitles = const [], this.decidedAt, this.appealDeadline});

  /// The topic of a decision the affected user complains about, from
  /// `decision.created` ([AppealRequest.subject]).
  factory AppealTopic.fromDecision(ModerationDecision decision, {String? title}) => AppealTopic(
        title: title,
        action: decision.action,
        policyTitles: [for (final policy in decision.policies) policy.title],
        decidedAt: decision.decidedAt,
      );

  /// The topic of a decision a reporter complains about, from
  /// `reports.resolved` ([AppealRequest.reporter]), with its
  /// [ReportsResolution.appealDeadline].
  factory AppealTopic.fromReportsResolution(ReportsResolution resolution, {String? title}) => AppealTopic(
        title: title,
        action: resolution.action,
        policyTitles: [for (final policy in resolution.policies) policy.title],
        decidedAt: resolution.decidedAt,
        appealDeadline: resolution.appealDeadline,
      );

  /// A plain title from the app, e.g. "Your comment of October 1".
  final String? title;

  /// The measure of the decision, shown with [LimeniaUiStrings.actionLabels].
  /// Null if unknown.
  final ModerationAction? action;

  /// Titles of the policies the decision is based on, in the language of the
  /// tenant.
  final List<String> policyTitles;

  /// When the decision was taken.
  final DateTime? decidedAt;

  /// The end of the window for a complaint, if Limenia sent it
  /// (`reports.resolved`). Otherwise [deadline] computes it from [decidedAt].
  final DateTime? appealDeadline;

  /// Until when a complaint is possible: [appealDeadline], or six calendar
  /// months after [decidedAt] ([appealDeadlineFor]), or null if neither is
  /// known.
  DateTime? get deadline {
    final decidedAt = this.decidedAt;
    return appealDeadline ?? (decidedAt == null ? null : appealDeadlineFor(decidedAt));
  }

  bool get _isEmpty => title == null && action == null && policyTitles.isEmpty && decidedAt == null;
}

/// Shows the complaint form ([LimeniaAppealForm]) in a modal bottom sheet.
///
/// The sheet calls [onSubmit] with the text of the user and shows its result.
/// It completes with the last result when it closes, or null if the user
/// closed it before a result arrived. The other arguments are those of
/// [LimeniaAppealForm].
///
/// ```dart
/// await showLimeniaAppealSheet(
///   context,
///   topic: AppealTopic.fromDecision(decision),
///   onSubmit: (text) => limenia.appeal(
///     AppealRequest.subject(decisionId: decision.id, externalUserId: userId, text: text),
///   ),
/// );
/// ```
Future<AppealResult?> showLimeniaAppealSheet(
  BuildContext context, {
  required Future<AppealResult> Function(String text) onSubmit,
  AppealTopic? topic,
  String? title,
  LimeniaUiStrings? strings,
}) async {
  AppealResult? last;
  await showLimeniaSheet(
    context,
    (sheetContext) => LimeniaAppealForm(
      onSubmit: onSubmit,
      topic: topic,
      title: title,
      strings: strings,
      onResult: (result) => last = result,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
  return last;
}

/// A form for a complaint against a decision (Art. 20 DSA), for the affected
/// user and for reporters alike. It shows what the complaint is about, that
/// it is possible for six months, free of charge and reviewed by a person,
/// and takes the reasons of the user. It never sends anything itself: it
/// calls [onSubmit] and shows the [AppealResult] it returns.
///
/// [showLimeniaAppealSheet] shows it in a bottom sheet. To embed it in a page,
/// put it in a scroll view: it is as tall as its content.
///
/// The text is checked with `validateAppeal` of package:limenia: required and
/// at most [AppealLimits.textLength] characters (Unicode code points), never
/// stricter than Limenia. Whether the complaint is admissible only Limenia
/// knows; the form shows its answer (`appeal_window_closed`,
/// `appeal_already_open`, `appeal_not_allowed`, `reporter_suspended`).
class LimeniaAppealForm extends StatefulWidget {
  /// Creates the form.
  const LimeniaAppealForm({
    super.key,
    required this.onSubmit,
    this.topic,
    this.title,
    this.strings,
    this.onResult,
    this.onClose,
  });

  /// Sends the complaint with the text as entered, usually with
  /// `Limenia.appeal`, and returns its result. If it throws, the form shows a
  /// failure with "Try again" and reports the error to
  /// [FlutterError.reportError].
  final Future<AppealResult> Function(String text) onSubmit;

  /// What the complaint is about. Null shows no summary.
  final AppealTopic? topic;

  /// Title of the form, [LimeniaUiStrings.appealTitle] by default.
  final String? title;

  /// Texts of the form. Null for [LimeniaUiStrings.of].
  final LimeniaUiStrings? strings;

  /// Called with every result of [onSubmit].
  final ValueChanged<AppealResult>? onResult;

  /// Called by the close button. Without it there is none, and the result
  /// stays on screen.
  final VoidCallback? onClose;

  @override
  State<LimeniaAppealForm> createState() => _LimeniaAppealFormState();
}

class _LimeniaAppealFormState extends State<LimeniaAppealForm> {
  final _text = TextEditingController();
  bool _attempted = false;
  bool _sending = false;

  bool _done = false;
  AppealResult? _result;
  String? _sentText;

  @override
  void initState() {
    super.initState();
    _text.addListener(_textChanged);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _textChanged() => setState(() {});

  void _submit() {
    setState(() => _attempted = true);
    if (appealTextError(_text.text) != null) return;
    _send(_text.text);
  }

  Future<void> _send(String text) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _done = false;
      _sentText = text;
    });
    AppealResult? result;
    try {
      result = await widget.onSubmit(text);
    } catch (error, stack) {
      reportCallbackError(error, stack, 'while sending a complaint with LimeniaAppealForm');
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
    final theme = Theme.of(context);
    final header = FormHeader(
      title: widget.title ?? strings.appealTitle,
      closeLabel: strings.close,
      onClose: widget.onClose,
    );
    if (_done) {
      final text = _sentText;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 24),
          OutcomePanel(
            outcome: _outcome(_result, strings),
            strings: strings,
            onRetry: text == null ? null : () => _send(text),
            onClose: widget.onClose,
          ),
        ],
      );
    }
    final topic = widget.topic;
    final deadline = topic?.deadline;
    final error = appealTextError(_text.text);
    final errorText = switch (error) {
      'too_long' => strings.textTooLong(AppealLimits.textLength),
      'required' when _attempted => strings.appealTextRequired,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 16),
        if (topic != null && !topic._isEmpty) ...[
          _TopicCard(topic: topic, strings: strings),
          const SizedBox(height: 16),
        ],
        Text(strings.appealInfo, style: theme.textTheme.bodyMedium),
        if (deadline != null) ...[
          const SizedBox(height: 8),
          Text(
            strings.appealDeadline(strings.formatDate(deadline)),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 16),
        CountedTextField(
          controller: _text,
          label: strings.appealTextLabel,
          hint: strings.appealTextHint,
          limit: AppealLimits.textLength,
          strings: strings,
          enabled: !_sending,
          errorText: errorText,
          minLines: 5,
          maxLines: 12,
        ),
        const SizedBox(height: 24),
        SubmitButton(
          label: strings.appealSubmit,
          sendingLabel: strings.sending,
          sending: _sending,
          onPressed: _submit,
        ),
      ],
    );
  }

  static Outcome _outcome(AppealResult? result, LimeniaUiStrings strings) {
    Outcome refused(String message) =>
        Outcome(kind: OutcomeKind.failure, title: strings.appealFailedTitle, message: message);
    return switch (result) {
      AppealSent() => Outcome(
          kind: OutcomeKind.success,
          title: strings.appealSentTitle,
          message: strings.appealSentMessage,
        ),
      AppealQueued() => Outcome(
          kind: OutcomeKind.queued,
          title: strings.appealQueuedTitle,
          message: strings.appealQueuedMessage,
        ),
      AppealFailed(isReporterSuspended: true, :final suspendedUntil) => refused(
          strings.appealReporterSuspended(suspendedUntil == null ? null : strings.formatDateTime(suspendedUntil)),
        ),
      AppealFailed(code: 'appeal_window_closed') => refused(strings.appealWindowClosed),
      AppealFailed(code: 'appeal_already_open') => refused(strings.appealAlreadyOpen),
      AppealFailed(code: 'appeal_not_allowed') => refused(strings.appealNotAllowed),
      AppealExpired() => Outcome(
          kind: OutcomeKind.failure,
          title: strings.appealFailedTitle,
          message: strings.appealExpiredMessage,
          canRetry: true,
        ),
      AppealFailed() || null => Outcome(
          kind: OutcomeKind.failure,
          title: strings.appealFailedTitle,
          message: strings.appealFailedMessage,
          canRetry: true,
        ),
    };
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.strings});

  final AppealTopic topic;
  final LimeniaUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = topic.title;
    final action = topic.action;
    final actionLabel = action == null ? null : strings.actionLabels[action];
    final decidedAt = topic.decidedAt;
    final secondary = theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.appealTopicLabel,
                  style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              if (title != null) Text(title, style: theme.textTheme.titleSmall),
              if (actionLabel != null) Text(actionLabel, style: theme.textTheme.bodyLarge),
              if (topic.policyTitles.isNotEmpty) Text(topic.policyTitles.join(', '), style: secondary),
              if (decidedAt != null) Text(strings.appealDecidedOn(strings.formatDate(decidedAt)), style: secondary),
            ],
          ),
        ),
      ),
    );
  }
}
