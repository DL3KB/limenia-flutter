// Building blocks shared by the widgets of this package. Not exported.
import 'package:flutter/material.dart';
import 'package:limenia/limenia.dart';

import 'strings.dart';

/// A valid decision ID for [appealTextError], which checks the text only.
const _anyDecisionId = '00000000000000000000000000';

/// Whether [reasonText] is longer than Limenia accepts for the reason of a
/// report. Asks `validateReport` of package:limenia, so the form is never
/// stricter (or laxer) than the package and the backend.
bool reportReasonTooLong(String reasonText) {
  final errors = validateReport(
    ReportRequest.user(
      reasonCategory: ReasonCategory.other,
      subject: const ReportedUser('_'),
      reasonText: reasonText,
    ),
  );
  return errors.any((e) => e.field == '/reasonText');
}

/// The error code (`required` or `too_long`) of [text] as the text of a
/// complaint, or null if Limenia accepts it. Asks `validateAppeal` of
/// package:limenia.
String? appealTextError(String text) {
  final errors = validateAppeal(AppealRequest.subject(decisionId: _anyDecisionId, externalUserId: '_', text: text));
  for (final error in errors) {
    if (error.field == '/text') return error.code;
  }
  return null;
}

/// Length of [text] as Limenia counts it: in Unicode code points.
int limeniaLength(String text) => text.runes.length;

/// How a send ended, for [OutcomePanel].
enum OutcomeKind {
  /// Limenia has it.
  success,

  /// Waiting for a connection.
  queued,

  /// Not sent.
  failure,
}

/// What [OutcomePanel] shows after a report or complaint was sent.
@immutable
final class Outcome {
  /// Creates an outcome.
  const Outcome({
    required this.kind,
    required this.title,
    required this.message,
    this.notice,
    this.canRetry = false,
  });

  /// Success, queued or failure.
  final OutcomeKind kind;

  /// Short title.
  final String title;

  /// What happened and what comes next.
  final String message;

  /// An extra notice in a highlighted box, e.g. the warning for a reporter.
  final String? notice;

  /// Whether sending the same input again may succeed.
  final bool canRetry;
}

/// The result of a report or complaint, read by screen readers when it
/// appears (live region).
class OutcomePanel extends StatelessWidget {
  /// Creates the panel for [outcome].
  const OutcomePanel({super.key, required this.outcome, required this.strings, this.onRetry, this.onClose});

  /// What to show.
  final Outcome outcome;

  /// Texts of the buttons.
  final LimeniaUiStrings strings;

  /// Sends again, shown only with [Outcome.canRetry].
  final VoidCallback? onRetry;

  /// Closes the panel, e.g. the sheet around it.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, color) = switch (outcome.kind) {
      OutcomeKind.success => (Icons.check_circle_outline, colors.primary),
      OutcomeKind.queued => (Icons.schedule_send_outlined, colors.primary),
      OutcomeKind.failure => (Icons.error_outline, colors.error),
    };
    final retry = outcome.canRetry ? onRetry : null;
    final notice = outcome.notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(outcome.title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(outcome.message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
          ),
        ),
        if (notice != null) ...[
          const SizedBox(height: 16),
          NoticeBox(
            icon: Icons.warning_amber_outlined,
            text: notice,
            background: colors.tertiaryContainer,
            foreground: colors.onTertiaryContainer,
          ),
        ],
        const SizedBox(height: 24),
        if (retry != null) FilledButton(onPressed: retry, child: Text(strings.tryAgain)),
        if (retry != null && onClose != null) const SizedBox(height: 8),
        if (onClose != null)
          retry == null
              ? FilledButton(onPressed: onClose, child: Text(strings.close))
              : TextButton(onPressed: onClose, child: Text(strings.close)),
      ],
    );
  }
}

/// A highlighted box with an icon and a text, e.g. the emergency hint.
class NoticeBox extends StatelessWidget {
  /// Creates a box in the given colors of the theme.
  const NoticeBox({
    super.key,
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.liveRegion = false,
  });

  /// Icon at the start, decorative.
  final IconData icon;

  /// The text.
  final String text;

  /// Color of the box, from the color scheme.
  final Color background;

  /// Color of icon and text, the matching "on" color.
  final Color foreground;

  /// Whether screen readers read the box when it appears.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: liveRegion,
        child: DecoratedBox(
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground)),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Title row of a form, with a close button if [onClose] is set.
class FormHeader extends StatelessWidget {
  /// Creates the header.
  const FormHeader({super.key, required this.title, required this.closeLabel, this.onClose});

  /// Title, a heading for screen readers.
  final String title;

  /// Tooltip and label of the close button.
  final String closeLabel;

  /// Closes the form; without it there is no close button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final onClose = this.onClose;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 8),
          IconButton(onPressed: onClose, tooltip: closeLabel, icon: const Icon(Icons.close)),
        ],
      ],
    );
  }
}

/// A multi-line text field with a counter in characters as Limenia counts
/// them, without a hard limit: a longer text shows an error instead of being
/// cut off.
class CountedTextField extends StatelessWidget {
  /// Creates the field.
  const CountedTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.limit,
    required this.strings,
    this.errorText,
    this.enabled = true,
    this.minLines = 3,
    this.maxLines = 8,
  });

  /// Holds the text.
  final TextEditingController controller;

  /// Label of the field.
  final String label;

  /// Hint inside the empty field.
  final String hint;

  /// Most characters Limenia accepts, for the counter.
  final int limit;

  /// Texts of counter and errors.
  final LimeniaUiStrings strings;

  /// Error below the field, null for none.
  final String? errorText;

  /// Whether the user can edit the text.
  final bool enabled;

  /// Height of the empty field in lines.
  final int minLines;

  /// Height in lines up to which the field grows.
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          counterText: strings.characterCount(limeniaLength(controller.text), limit),
          errorText: errorText,
          errorMaxLines: 4,
        ),
      );
}

/// The submit button of a form, with a progress indicator while [sending].
class SubmitButton extends StatelessWidget {
  /// Creates the button.
  const SubmitButton(
      {super.key, required this.label, required this.sendingLabel, required this.sending, this.onPressed});

  /// Label when idle.
  final String label;

  /// Label while sending.
  final String sendingLabel;

  /// Whether a send is running; the button is disabled then.
  final bool sending;

  /// Sends the form.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: sending ? null : onPressed,
        child: sending
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: ExcludeSemantics(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(sendingLabel)),
                ],
              )
            : Text(label),
      );
}

/// A label above a value, as in the statement of reasons.
class LabeledSection extends StatelessWidget {
  /// Creates a section.
  const LabeledSection({super.key, required this.label, required this.child});

  /// The label, a heading for screen readers.
  final String label;

  /// The value.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Shows [content] in a modal bottom sheet that scrolls, follows the
/// keyboard and keeps the [LimeniaUiStringsScope] of [context].
Future<void> showLimeniaSheet(BuildContext context, WidgetBuilder content) {
  final scope = context.getInheritedWidgetOfExactType<LimeniaUiStringsScope>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      Widget sheet = Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Builder(builder: content),
        ),
      );
      if (scope != null) sheet = LimeniaUiStringsScope(strings: scope.strings, child: sheet);
      return sheet;
    },
  );
}

/// Reports an error of a callback of the app, so that it shows in the log
/// and in crash reporting, while the widget shows a failure.
void reportCallbackError(Object error, StackTrace stack, String context) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'limenia',
      context: ErrorDescription(context),
    ),
  );
}
