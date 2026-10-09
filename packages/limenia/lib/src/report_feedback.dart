import 'decision.dart';
import 'json.dart';

/// A report of a user on a decided case, from `reports.resolved`.
final class ResolvedReport {
  const ResolvedReport({required this.reportId, this.externalReportId});

  /// Limenia ID of the report, as in [ReportReceipt.reportId].
  final String reportId;

  /// The ID the app sent with the report (`ReportRequest.externalReportId`).
  final String? externalReportId;

  factory ResolvedReport.fromJson(JsonMap json) => ResolvedReport(
        reportId: readRequired<String>(json, 'reportId'),
        externalReportId: readOptional<String>(json, 'externalReportId'),
      );

  JsonMap toJson() => {'reportId': reportId, if (externalReportId != null) 'externalReportId': externalReportId};
}

/// The decision on a case for the users who reported it (Art. 16 (5) DSA),
/// as Limenia sends it in `reports.resolved` (`WebhookReportsResolved`).
///
/// Only reports of users (`source: user`) are listed, at most 100 per event:
/// a case with more reports comes in several events with the same
/// [decisionId], at most 100 events, so Limenia answers at most 10,000
/// reporters of a decision. If a complaint changes the decision later, no
/// new `reports.resolved` comes: the new decision arrives as
/// `decision.created` with `appealId` and `replacesDecisionId`.
final class ReportsResolution {
  const ReportsResolution({
    required this.decisionId,
    required this.actionName,
    required this.policies,
    required this.decidedAt,
    required this.appealDeadline,
    required this.reports,
  });

  final String decisionId;

  /// Wire value of the action, see [action].
  final String actionName;

  final List<PolicyRef> policies;
  final DateTime decidedAt;

  /// Until then the reporters can complain with `AppealRequest.reporter`.
  final DateTime appealDeadline;

  /// The reports to answer. Match them to your users by
  /// [ResolvedReport.externalReportId] or [ResolvedReport.reportId].
  final List<ResolvedReport> reports;

  /// The action, or null for an action this version of the package does not
  /// know yet.
  ModerationAction? get action => ModerationAction.tryParse(actionName);

  factory ReportsResolution.fromJson(JsonMap json) => ReportsResolution(
        decisionId: readRequired<String>(json, 'decisionId'),
        actionName: readRequired<String>(json, 'action'),
        policies: [for (final p in readObjectList(json, 'policies')) PolicyRef.fromJson(p)],
        decidedAt: readDate(json, 'decidedAt'),
        appealDeadline: readDate(json, 'appealDeadline'),
        reports: [for (final r in readObjectList(json, 'items')) ResolvedReport.fromJson(r)],
      );

  JsonMap toJson() => {
        'decisionId': decisionId,
        'action': actionName,
        'policies': [for (final p in policies) p.toJson()],
        'decidedAt': formatDate(decidedAt),
        'appealDeadline': formatDate(appealDeadline),
        'items': [for (final r in reports) r.toJson()],
      };
}
