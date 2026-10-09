import 'package:flutter/material.dart';
import 'package:limenia/limenia.dart';

import 'common.dart';
import 'strings.dart';

/// How [LimeniaStatementOfReasonsView] shows a statement of reasons.
enum SorLayout {
  /// The ready-made text of Limenia ([StatementOfReasons.text]) in the
  /// language of the tenant, as plain text. The default.
  text,

  /// Sections built from [StatementOfReasons.structured] with labels in the
  /// language of the app. The facts, the titles of the policies and the
  /// redress text stay in the language of the tenant. Falls back to [text]
  /// for an action this version of package:limenia does not know.
  structured,
}

/// Shows the statement of reasons of a decision (Art. 17 DSA) to the
/// affected user, e.g. from `decision.created`
/// ([ModerationDecision.statementOfReasons]).
///
/// Everything is shown as plain, selectable text, never as Markdown or HTML:
/// the statement contains the free text of the moderator.
///
/// In the [SorLayout.structured] layout the view always says whether
/// automated means were used ([SorDetails.automation], Art. 17(3)(c) DSA), and
/// highlights it when they were.
///
/// It is as tall as its content: put it in a scroll view.
class LimeniaStatementOfReasonsView extends StatelessWidget {
  /// Creates the view of [statement].
  const LimeniaStatementOfReasonsView({
    super.key,
    required this.statement,
    this.layout = SorLayout.text,
    this.onAppeal,
    this.strings,
  });

  /// The statement of reasons.
  final StatementOfReasons statement;

  /// The ready-made text or the structured sections.
  final SorLayout layout;

  /// Shows a button "Submit a complaint" below the statement that calls it,
  /// e.g. to open [showLimeniaAppealSheet]. Null for no button.
  final VoidCallback? onAppeal;

  /// Texts of labels and button. Null for [LimeniaUiStrings.of].
  final LimeniaUiStrings? strings;

  @override
  Widget build(BuildContext context) {
    final strings = this.strings ?? LimeniaUiStrings.of(context);
    final theme = Theme.of(context);
    final details = statement.structured;
    final action = details.action;
    final onAppeal = this.onAppeal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (layout == SorLayout.structured && action != null)
          SelectionArea(child: _Structured(details: details, action: action, strings: strings))
        else
          SelectableText(statement.text, style: theme.textTheme.bodyMedium),
        if (onAppeal != null) ...[
          const SizedBox(height: 24),
          FilledButton.tonal(onPressed: onAppeal, child: Text(strings.submitComplaint)),
        ],
      ],
    );
  }
}

class _Structured extends StatelessWidget {
  const _Structured({required this.details, required this.action, required this.strings});

  final SorDetails details;
  final ModerationAction action;
  final LimeniaUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = theme.textTheme.bodyMedium;
    final secondary = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final endsAt = details.endsAt;
    final restricts = action != ModerationAction.dismiss && action != ModerationAction.restore;
    final facts = details.facts.trim();
    final redress = details.redress.trim();
    final automation = details.automation;

    final sections = <Widget>[
      LabeledSection(
        label: strings.sorMeasure,
        child: Text(strings.actionLabels[action] ?? details.actionName, style: theme.textTheme.titleMedium),
      ),
      if (endsAt != null)
        LabeledSection(label: strings.sorEndsAt, child: Text(strings.formatDateTime(endsAt), style: body)),
      if (restricts)
        LabeledSection(
          label: strings.sorScope,
          child: Text(details.territorialScope == 'app' ? strings.sorScopeApp : details.territorialScope, style: body),
        ),
      if (facts.isNotEmpty) LabeledSection(label: strings.sorFacts, child: Text(facts, style: body)),
      LabeledSection(
        label: strings.sorNoticeSource,
        child: Text(
          switch (details.noticeSource) {
            NoticeSource.notice => strings.sorNoticeSourceNotice,
            NoticeSource.trustedFlagger => strings.sorNoticeSourceTrustedFlagger,
            NoticeSource.ownInitiative => strings.sorNoticeSourceOwnInitiative,
          },
          style: body,
        ),
      ),
      LabeledSection(
        label: strings.sorAutomation,
        child: _automation(automation, details.automatedDetection, colors, body),
      ),
      if (details.grounds.isNotEmpty)
        LabeledSection(
          label: strings.sorGrounds,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, ground) in details.grounds.indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(ground.title, style: body?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        switch (ground.basis) {
                          LegalBasis.terms => strings.sorGroundTerms,
                          LegalBasis.law => strings.sorGroundLaw(ground.lawReference),
                        },
                        style: secondary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (redress.isNotEmpty) LabeledSection(label: strings.sorRedress, child: Text(redress, style: body)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, section) in sections.indexed)
          Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 16), child: section),
      ],
    );
  }

  /// The sentences about automated means, as in the ready-made text of
  /// Limenia. Highlighted when automated means were used.
  Widget _automation(Automation automation, bool automatedDetection, ColorScheme colors, TextStyle? body) {
    final text = switch (automation) {
      Automation.partial => [
          if (automatedDetection) strings.sorAutomatedDetection,
          strings.sorAutomationPartial,
        ].join(' '),
      Automation.full => strings.sorAutomationFull,
      Automation.none => automatedDetection ? strings.sorAutomatedDetection : strings.sorAutomationNone,
    };
    if (!automation.usesAutomatedMeans) return Text(text, style: body);
    return NoticeBox(
      icon: Icons.smart_toy_outlined,
      text: text,
      background: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
    );
  }
}
