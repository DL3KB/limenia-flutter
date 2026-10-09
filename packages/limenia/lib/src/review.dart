import 'decision.dart';
import 'json.dart';
import 'report.dart';

/// Status of a review request (`ReviewStatus`).
enum ReviewStatus {
  /// Received, nobody works on it yet.
  pending('pending'),

  /// Assigned to a moderator.
  inReview('in_review'),

  /// Decided, see [ReviewOutcome].
  decided('decided');

  const ReviewStatus(this.wireName);

  /// Value in the API, e.g. `in_review`.
  final String wireName;

  static ReviewStatus fromWire(String value) => values.firstWhere(
        (s) => s.wireName == value,
        orElse: () => throw FormatException('Limenia: unknown review status', value),
      );
}

/// Result of a review request (`ReviewOutcome`).
enum ReviewOutcome {
  /// Publish the content. No decision in the sense of the DSA, so no
  /// `decision.created` follows.
  approved,

  /// Publish the content with a restriction, e.g. for adults only or blurred.
  /// A decision with [ModerationAction.restrictContent] and its statement of
  /// reasons follows as `decision.created`.
  restricted,

  /// Do not publish the content. A decision with
  /// [ModerationAction.rejectSubmission] and its statement of reasons follows
  /// as `decision.created`. The author can complain against it.
  rejected;

  static ReviewOutcome fromWire(String value) => switch (value) {
        'approved' => approved,
        'restricted' => restricted,
        'rejected' => rejected,
        _ => throw FormatException('Limenia: unknown review outcome', value),
      };
}

/// Content submitted for review before it is published (pre-moderation),
/// in the format of `POST /v1/reviews` (`CreateReviewRequest`).
///
/// [toJson] gives exactly the body of the ingest API. The backend of the app
/// should still set the [author] from its own login (see [withAuthor]) and,
/// where possible, load the content from its own storage: the device can send
/// anything.
final class ReviewRequest {
  const ReviewRequest({required this.type, required this.content, this.author, this.externalReviewId});

  /// Code of a review type the tenant configured for the app in the dashboard,
  /// e.g. `profile_photo`. Limenia rejects an unknown or inactive type with
  /// `review_type_unknown`.
  final String type;

  /// The content to review, in the same format as in a report. Every request
  /// gets its own snapshot, so a revised version can keep its
  /// [ReportedContent.externalContentId]. Match results by the review ID or
  /// [externalReviewId]; to match them by `externalContentId` as well, give
  /// every submitted version its own one, e.g. `photo_881@v2`.
  final ReportedContent content;

  /// Author of the content, sent as `subject`. Always pass it: without it
  /// moderators see no user file and the decision belongs to no user.
  final ReportedUser? author;

  /// Optional ID of the request in the app, at most 128 characters. Limenia
  /// returns it in `review.decided`.
  final String? externalReviewId;

  factory ReviewRequest.fromJson(JsonMap json) {
    final subject = readOptionalObject(json, 'subject');
    return ReviewRequest(
      type: readRequired<String>(json, 'type'),
      content: ReportedContent.fromJson(readObject(json, 'content')),
      author: subject == null ? null : ReportedUser.fromJson(subject),
      externalReviewId: readOptional<String>(json, 'externalReviewId'),
    );
  }

  JsonMap toJson() => {
        'type': type,
        if (externalReviewId != null) 'externalReviewId': externalReviewId,
        if (author != null) 'subject': author!.toJson(),
        'content': content.toJson(),
      };

  /// A copy with another author, e.g. the user a backend has authenticated.
  ReviewRequest withAuthor(ReportedUser? author) =>
      ReviewRequest(type: type, content: content, author: author, externalReviewId: externalReviewId);
}

/// Answer of `POST /v1/reviews` (`CreatedReview`).
final class ReviewReceipt {
  const ReviewReceipt({required this.reviewId, required this.status, required this.dueAt});

  final String reviewId;
  final ReviewStatus status;

  /// Target time for the decision, from the review type.
  final DateTime dueAt;

  factory ReviewReceipt.fromJson(JsonMap json) => ReviewReceipt(
        reviewId: readRequired<String>(json, 'reviewId'),
        status: ReviewStatus.fromWire(readRequired<String>(json, 'status')),
        dueAt: readDate(json, 'dueAt'),
      );

  JsonMap toJson() => {'reviewId': reviewId, 'status': status.wireName, 'dueAt': formatDate(dueAt)};

  @override
  bool operator ==(Object other) =>
      other is ReviewReceipt && other.reviewId == reviewId && other.status == status && other.dueAt == dueAt;

  @override
  int get hashCode => Object.hash(reviewId, status, dueAt);

  @override
  String toString() => 'ReviewReceipt(reviewId: $reviewId, status: ${status.wireName}, dueAt: $dueAt)';
}

/// Status and result of a review request from `GET /v1/reviews/{reviewId}`
/// (`ReviewStatusInfo`), the fallback if `review.decided` was missed.
///
/// It always shows the first result. If a complaint changes the decision on
/// the request later (`appeal.resolved` with `changed`), [outcome] and
/// [decisionId] stay as they were: then the newest `decision.created` with
/// this `reviewId` (and `appealId`, `replacesDecisionId`) counts, e.g.
/// `restore` (publish as submitted) after a rejection.
final class ReviewStatusInfo {
  const ReviewStatusInfo({
    required this.id,
    required this.type,
    required this.status,
    required this.submittedAt,
    this.externalReviewId,
    this.outcome,
    this.decidedAt,
    this.decisionId,
  });

  final String id;
  final String? externalReviewId;

  /// Code of the review type.
  final String type;
  final ReviewStatus status;
  final DateTime submittedAt;

  /// Only for [ReviewStatus.decided].
  final ReviewOutcome? outcome;
  final DateTime? decidedAt;

  /// The decision with the statement of reasons, for
  /// [ReviewOutcome.restricted] and [ReviewOutcome.rejected].
  final String? decisionId;

  factory ReviewStatusInfo.fromJson(JsonMap json) {
    final outcome = readOptional<String>(json, 'outcome');
    return ReviewStatusInfo(
      id: readRequired<String>(json, 'id'),
      externalReviewId: readOptional<String>(json, 'externalReviewId'),
      type: readRequired<String>(json, 'type'),
      status: ReviewStatus.fromWire(readRequired<String>(json, 'status')),
      submittedAt: readDate(json, 'submittedAt'),
      outcome: outcome == null ? null : ReviewOutcome.fromWire(outcome),
      decidedAt: readOptionalDate(json, 'decidedAt'),
      decisionId: readOptional<String>(json, 'decisionId'),
    );
  }

  JsonMap toJson() => {
        'id': id,
        if (externalReviewId != null) 'externalReviewId': externalReviewId,
        'type': type,
        'status': status.wireName,
        'submittedAt': formatDate(submittedAt),
        if (outcome != null) 'outcome': outcome!.name,
        if (decidedAt != null) 'decidedAt': formatDate(decidedAt!),
        if (decisionId != null) 'decisionId': decisionId,
      };
}

/// A decided review request as Limenia sends it in `review.decided`
/// (`WebhookReview`).
///
/// Publish the content only now: [ReviewOutcome.approved] as it is,
/// [ReviewOutcome.restricted] with a restriction, [ReviewOutcome.rejected]
/// not at all. For the last two the decision with the statement of reasons
/// for the author follows as `decision.created` with [decisionId] as its ID.
/// A complaint can change that decision later: no new `review.decided` comes
/// then, but `appeal.resolved` and a new `decision.created` with the same
/// `reviewId`.
final class ReviewResolution {
  const ReviewResolution({
    required this.id,
    required this.type,
    required this.outcome,
    required this.decidedAt,
    this.externalReviewId,
    this.decisionId,
    this.externalContentId,
  });

  /// Limenia ID of the request, as in [ReviewReceipt.reviewId].
  final String id;

  /// The ID the app sent with the request ([ReviewRequest.externalReviewId]).
  final String? externalReviewId;

  /// Code of the review type.
  final String type;
  final ReviewOutcome outcome;
  final DateTime decidedAt;

  /// Set for [ReviewOutcome.restricted] and [ReviewOutcome.rejected]: the ID
  /// of the decision that follows as `decision.created`.
  final String? decisionId;

  /// The content of the request ([ReportedContent.externalContentId]).
  final String? externalContentId;

  factory ReviewResolution.fromJson(JsonMap json) {
    final content = readOptionalObject(json, 'content');
    return ReviewResolution(
      id: readRequired<String>(json, 'id'),
      externalReviewId: readOptional<String>(json, 'externalReviewId'),
      type: readRequired<String>(json, 'type'),
      outcome: ReviewOutcome.fromWire(readRequired<String>(json, 'outcome')),
      decidedAt: readDate(json, 'decidedAt'),
      decisionId: readOptional<String>(json, 'decisionId'),
      externalContentId: content == null ? null : readRequired<String>(content, 'externalContentId'),
    );
  }

  JsonMap toJson() => {
        'id': id,
        if (externalReviewId != null) 'externalReviewId': externalReviewId,
        'type': type,
        'outcome': outcome.name,
        'decidedAt': formatDate(decidedAt),
        if (decisionId != null) 'decisionId': decisionId,
        if (externalContentId != null) 'content': {'externalContentId': externalContentId},
      };
}
