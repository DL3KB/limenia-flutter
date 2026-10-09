import 'appeal.dart';
import 'decision.dart';
import 'json.dart';
import 'report_feedback.dart';
import 'review.dart';
import 'status.dart';

/// A webhook event of Limenia (`WebhookEvent`).
///
/// Only the backend of the app receives webhooks and checks their signature.
/// If it passes the verified event on to the app (push message, Firestore,
/// own API), [LimeniaEvent.fromJson] reads it there.
sealed class LimeniaEvent {
  const LimeniaEvent({required this.id, required this.createdAt, required this.appId, required this.appSlug});

  /// Event ID, the same in every delivery attempt. Deduplicate by it.
  final String id;
  final DateTime createdAt;
  final String appId;
  final String appSlug;

  /// Event type, e.g. `decision.created`.
  String get type;

  static LimeniaEvent fromJson(JsonMap json) {
    final id = readRequired<String>(json, 'id');
    final createdAt = readDate(json, 'createdAt');
    final app = readObject(json, 'app');
    final appId = readRequired<String>(app, 'id');
    final appSlug = readRequired<String>(app, 'slug');
    return switch (readRequired<String>(json, 'type')) {
      DecisionCreatedEvent.eventType => DecisionCreatedEvent(
          id: id,
          createdAt: createdAt,
          appId: appId,
          appSlug: appSlug,
          decision: ModerationDecision.fromJson(readObject(json, 'decision')),
        ),
      SubjectStatusChangedEvent.eventType => SubjectStatusChangedEvent(
          id: id,
          createdAt: createdAt,
          appId: appId,
          appSlug: appSlug,
          subject: SubjectStatus.fromJson(readObject(json, 'subject')),
        ),
      AppealResolvedEvent.eventType => AppealResolvedEvent(
          id: id,
          createdAt: createdAt,
          appId: appId,
          appSlug: appSlug,
          appeal: AppealResolution.fromJson(readObject(json, 'appeal')),
        ),
      ReportsResolvedEvent.eventType => ReportsResolvedEvent(
          id: id,
          createdAt: createdAt,
          appId: appId,
          appSlug: appSlug,
          reports: ReportsResolution.fromJson(readObject(json, 'reports')),
        ),
      ReviewDecidedEvent.eventType => ReviewDecidedEvent(
          id: id,
          createdAt: createdAt,
          appId: appId,
          appSlug: appSlug,
          review: ReviewResolution.fromJson(readObject(json, 'review')),
        ),
      TestPingEvent.eventType => TestPingEvent(id: id, createdAt: createdAt, appId: appId, appSlug: appSlug),
      final type => UnknownLimeniaEvent(
          id: id,
          createdAt: createdAt,
          appId: appId,
          appSlug: appSlug,
          type: type,
          json: json,
        ),
    };
  }
}

/// A moderator decided (`decision.created`).
final class DecisionCreatedEvent extends LimeniaEvent {
  const DecisionCreatedEvent({
    required super.id,
    required super.createdAt,
    required super.appId,
    required super.appSlug,
    required this.decision,
  });

  static const eventType = 'decision.created';

  final ModerationDecision decision;

  @override
  String get type => eventType;
}

/// Limenia lifted a suspension that has ended (`subject.status_changed`).
///
/// The hourly job lifts it up to an hour after `suspendedUntil`, with
/// [subject] `active`. From API version 0.13.2 a decision about the user
/// before that, e.g. a warning, lifts it as well, and this event comes right
/// with its `decision.created`. [subject] is then the status after that
/// decision, `warned` after a warning, and [createdAt] equals its
/// `decidedAt`. Order the event by [createdAt] against
/// [ModerationDecision.decidedAt], as `SubjectStatusWatcher` does.
final class SubjectStatusChangedEvent extends LimeniaEvent {
  const SubjectStatusChangedEvent({
    required super.id,
    required super.createdAt,
    required super.appId,
    required super.appSlug,
    required this.subject,
  });

  static const eventType = 'subject.status_changed';

  final SubjectStatus subject;

  @override
  String get type => eventType;
}

/// A moderator decided on a complaint (`appeal.resolved`). Show
/// [AppealResolution.statementText] to the complaining user. For
/// [AppealOutcome.changed] the new decision follows as `decision.created`.
final class AppealResolvedEvent extends LimeniaEvent {
  const AppealResolvedEvent({
    required super.id,
    required super.createdAt,
    required super.appId,
    required super.appSlug,
    required this.appeal,
  });

  static const eventType = 'appeal.resolved';

  final AppealResolution appeal;

  @override
  String get type => eventType;
}

/// A case with reports of users was decided (`reports.resolved`), in addition
/// to `decision.created`. Tell the reporters the result and the deadline for
/// a complaint (Art. 16 (5) DSA).
final class ReportsResolvedEvent extends LimeniaEvent {
  const ReportsResolvedEvent({
    required super.id,
    required super.createdAt,
    required super.appId,
    required super.appSlug,
    required this.reports,
  });

  static const eventType = 'reports.resolved';

  final ReportsResolution reports;

  @override
  String get type => eventType;
}

/// A moderator decided on a review request (`review.decided`). Publish the
/// content only now, depending on [ReviewResolution.outcome]. For
/// [ReviewOutcome.restricted] and [ReviewOutcome.rejected] the decision with
/// the statement of reasons follows as `decision.created`.
final class ReviewDecidedEvent extends LimeniaEvent {
  const ReviewDecidedEvent({
    required super.id,
    required super.createdAt,
    required super.appId,
    required super.appSlug,
    required this.review,
  });

  static const eventType = 'review.decided';

  final ReviewResolution review;

  @override
  String get type => eventType;
}

/// Test event from the dashboard (`test.ping`).
final class TestPingEvent extends LimeniaEvent {
  const TestPingEvent({required super.id, required super.createdAt, required super.appId, required super.appSlug});

  static const eventType = 'test.ping';

  @override
  String get type => eventType;
}

/// An event type this version of the package does not know yet. Acknowledge
/// it and ignore it.
final class UnknownLimeniaEvent extends LimeniaEvent {
  const UnknownLimeniaEvent({
    required super.id,
    required super.createdAt,
    required super.appId,
    required super.appSlug,
    required this.type,
    required this.json,
  });

  @override
  final String type;

  /// The whole event as received.
  final JsonMap json;
}
