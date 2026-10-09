import 'json.dart';

/// Who complains against a decision (`AppellantType`).
enum AppellantType {
  /// The affected user, against a decision that restricts them or their
  /// content: remove or restrict the content, warn, suspend or ban, or the
  /// refusal to publish content submitted for review (`reject_submission`).
  subject,

  /// A user who reported the case, against any decision on it, above all
  /// against a dismissal.
  reporter;

  static AppellantType fromWire(String value) => switch (value) {
        'subject' => subject,
        'reporter' => reporter,
        _ => throw FormatException('Limenia: unknown appellant type', value),
      };
}

/// Status of a complaint (`AppealStatus`).
enum AppealStatus {
  /// Received, nobody works on it yet.
  open('open'),

  /// Assigned to a moderator.
  inReview('in_review'),

  /// Decided, see [AppealOutcome].
  resolved('resolved');

  const AppealStatus(this.wireName);

  /// Value in the API, e.g. `in_review`.
  final String wireName;

  static AppealStatus fromWire(String value) => values.firstWhere(
        (s) => s.wireName == value,
        orElse: () => throw FormatException('Limenia: unknown appeal status', value),
      );
}

/// Result of a complaint (`AppealOutcome`).
enum AppealOutcome {
  /// The decision stays.
  upheld,

  /// A new decision replaces the old one. It arrives as `decision.created`.
  changed;

  static AppealOutcome fromWire(String value) => switch (value) {
        'upheld' => upheld,
        'changed' => changed,
        _ => throw FormatException('Limenia: unknown appeal outcome', value),
      };
}

/// A complaint against a decision (Art. 20 DSA) in the format of
/// `POST /v1/appeals` (`CreateAppealRequest`).
///
/// [toJson] gives exactly the body of the ingest API. The backend of the app
/// should still set [externalUserId] from its own login, see
/// [withAppellantUser]: the device can send anything.
final class AppealRequest {
  const AppealRequest({
    required this.decisionId,
    required this.appellantType,
    required this.externalUserId,
    required this.text,
    this.externalAppealId,
  });

  /// The affected user complains against a restricting decision.
  const AppealRequest.subject({
    required this.decisionId,
    required this.externalUserId,
    required this.text,
    this.externalAppealId,
  }) : appellantType = AppellantType.subject;

  /// A reporting user complains against the decision on the case they
  /// reported, e.g. a dismissal from `reports.resolved`.
  const AppealRequest.reporter({
    required this.decisionId,
    required this.externalUserId,
    required this.text,
    this.externalAppealId,
  }) : appellantType = AppellantType.reporter;

  /// Limenia ID of the decision, from `decision.created` or `reports.resolved`.
  final String decisionId;

  final AppellantType appellantType;

  /// ID of the complaining user in the app. For [AppellantType.subject] the
  /// affected user, for [AppellantType.reporter] the ID the report was sent
  /// with. Limenia stores only a hash of a reporter's ID.
  final String externalUserId;

  /// Reasons of the user, plain text.
  final String text;

  /// Optional ID of the complaint in the app, returned in `appeal.resolved`.
  final String? externalAppealId;

  factory AppealRequest.fromJson(JsonMap json) {
    final appellant = readObject(json, 'appellant');
    return AppealRequest(
      decisionId: readRequired<String>(json, 'decisionId'),
      appellantType: AppellantType.fromWire(readRequired<String>(appellant, 'type')),
      externalUserId: readRequired<String>(appellant, 'externalUserId'),
      text: readRequired<String>(json, 'text'),
      externalAppealId: readOptional<String>(json, 'externalAppealId'),
    );
  }

  JsonMap toJson() => {
        'decisionId': decisionId,
        'appellant': {'type': appellantType.name, 'externalUserId': externalUserId},
        'text': text,
        if (externalAppealId != null) 'externalAppealId': externalAppealId,
      };

  /// A copy with another complaining user, e.g. the user a backend has
  /// authenticated.
  AppealRequest withAppellantUser(String externalUserId) => AppealRequest(
        decisionId: decisionId,
        appellantType: appellantType,
        externalUserId: externalUserId,
        text: text,
        externalAppealId: externalAppealId,
      );
}

/// Answer of `POST /v1/appeals` (`CreatedAppeal`).
final class AppealReceipt {
  const AppealReceipt({required this.appealId, required this.status});

  final String appealId;
  final AppealStatus status;

  factory AppealReceipt.fromJson(JsonMap json) => AppealReceipt(
        appealId: readRequired<String>(json, 'appealId'),
        status: AppealStatus.fromWire(readRequired<String>(json, 'status')),
      );

  JsonMap toJson() => {'appealId': appealId, 'status': status.wireName};

  @override
  bool operator ==(Object other) => other is AppealReceipt && other.appealId == appealId && other.status == status;

  @override
  int get hashCode => Object.hash(appealId, status);

  @override
  String toString() => 'AppealReceipt(appealId: $appealId, status: ${status.wireName})';
}

/// Status and result of a complaint from `GET /v1/appeals/{appealId}`
/// (`AppealStatusInfo`), the fallback if `appeal.resolved` was missed.
final class AppealStatusInfo {
  const AppealStatusInfo({
    required this.id,
    required this.decisionId,
    required this.appellantType,
    required this.status,
    required this.createdAt,
    this.externalAppealId,
    this.outcome,
    this.statementText,
    this.resolvedAt,
    this.newDecisionId,
  });

  final String id;
  final String? externalAppealId;
  final String decisionId;
  final AppellantType appellantType;
  final AppealStatus status;
  final DateTime createdAt;

  /// Only for [AppealStatus.resolved].
  final AppealOutcome? outcome;

  /// Answer to the complaining user, only for [AppealStatus.resolved]. Show it
  /// as plain text, see [AppealResolution.statementText].
  final String? statementText;
  final DateTime? resolvedAt;

  /// The decision that replaces the old one, for [AppealOutcome.changed].
  final String? newDecisionId;

  factory AppealStatusInfo.fromJson(JsonMap json) {
    final outcome = readOptional<String>(json, 'outcome');
    return AppealStatusInfo(
      id: readRequired<String>(json, 'id'),
      externalAppealId: readOptional<String>(json, 'externalAppealId'),
      decisionId: readRequired<String>(json, 'decisionId'),
      appellantType: AppellantType.fromWire(readRequired<String>(json, 'appellantType')),
      status: AppealStatus.fromWire(readRequired<String>(json, 'status')),
      createdAt: readDate(json, 'createdAt'),
      outcome: outcome == null ? null : AppealOutcome.fromWire(outcome),
      statementText: readOptional<String>(json, 'statementText'),
      resolvedAt: readOptionalDate(json, 'resolvedAt'),
      newDecisionId: readOptional<String>(json, 'newDecisionId'),
    );
  }

  JsonMap toJson() => {
        'id': id,
        if (externalAppealId != null) 'externalAppealId': externalAppealId,
        'decisionId': decisionId,
        'appellantType': appellantType.name,
        'status': status.wireName,
        'createdAt': formatDate(createdAt),
        if (outcome != null) 'outcome': outcome!.name,
        if (statementText != null) 'statementText': statementText,
        if (resolvedAt != null) 'resolvedAt': formatDate(resolvedAt!),
        if (newDecisionId != null) 'newDecisionId': newDecisionId,
      };
}

/// A resolved complaint as Limenia sends it in `appeal.resolved`
/// (`WebhookAppeal`).
final class AppealResolution {
  const AppealResolution({
    required this.id,
    required this.decisionId,
    required this.appellantType,
    required this.outcome,
    required this.statementText,
    required this.resolvedAt,
    this.externalAppealId,
    this.newDecisionId,
  });

  final String id;
  final String? externalAppealId;

  /// The decision the complaint was about.
  final String decisionId;
  final AppellantType appellantType;
  final AppealOutcome outcome;

  /// Ready-made answer to the complaining user in the language of the tenant,
  /// with the reasons and the hint on out-of-court dispute settlement
  /// (Art. 21 DSA). Show it as plain text, never as HTML or Markdown: it
  /// contains the free text of the moderator.
  final String statementText;
  final DateTime resolvedAt;

  /// Set for [AppealOutcome.changed]. The new decision follows as
  /// `decision.created`.
  final String? newDecisionId;

  factory AppealResolution.fromJson(JsonMap json) => AppealResolution(
        id: readRequired<String>(json, 'id'),
        externalAppealId: readOptional<String>(json, 'externalAppealId'),
        decisionId: readRequired<String>(json, 'decisionId'),
        appellantType: AppellantType.fromWire(readRequired<String>(json, 'appellantType')),
        outcome: AppealOutcome.fromWire(readRequired<String>(json, 'outcome')),
        statementText: readRequired<String>(json, 'statementText'),
        resolvedAt: readDate(json, 'resolvedAt'),
        newDecisionId: readOptional<String>(json, 'newDecisionId'),
      );

  JsonMap toJson() => {
        'id': id,
        if (externalAppealId != null) 'externalAppealId': externalAppealId,
        'decisionId': decisionId,
        'appellantType': appellantType.name,
        'outcome': outcome.name,
        'statementText': statementText,
        'resolvedAt': formatDate(resolvedAt),
        if (newDecisionId != null) 'newDecisionId': newDecisionId,
      };
}
