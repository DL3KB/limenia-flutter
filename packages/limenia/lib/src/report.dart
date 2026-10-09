import 'json.dart';

/// Who found the problem. It decides whether the statement of reasons says
/// "following a report" or "based on our own review".
enum ReportSource {
  /// A user of the app reported it.
  user,

  /// Detected automatically, by the app itself (or by Limenia for the reports
  /// it creates itself). Leave out the reporter, [ReportRequest.goodFaith]
  /// and [ReportRequest.trustedFlaggerId].
  system;

  static ReportSource fromWire(String value) => switch (value) {
        'user' => user,
        'system' => system,
        _ => throw FormatException('Limenia: unknown report source', value),
      };
}

/// The reported user, for a content its author.
final class ReportedUser {
  const ReportedUser(this.externalUserId, {this.displayName});

  /// Stable ID of the user in the app, never an e-mail address. With the
  /// Firebase connector it must be the Firebase UID.
  final String externalUserId;

  /// Name shown to moderators. If set and not empty after trimming, it
  /// replaces the stored name.
  final String? displayName;

  factory ReportedUser.fromJson(JsonMap json) => ReportedUser(
        readRequired<String>(json, 'externalUserId'),
        displayName: readOptional<String>(json, 'displayName'),
      );

  JsonMap toJson() => {
        'externalUserId': externalUserId,
        if (displayName != null) 'displayName': displayName,
      };
}

/// Snapshot of the reported content. Limenia keeps the snapshot of the first
/// report on an [externalContentId]; later reports do not change it.
final class ReportedContent {
  const ReportedContent({
    required this.externalContentId,
    required this.contentType,
    this.text,
    this.mediaUrls = const [],
    this.externalUrl,
    this.createdAt,
    this.context,
  });

  /// Stable ID of the content in the app. Decisions refer to it. Give an
  /// edited content a new ID (e.g. `comment_5521@v2`) to have it reviewed again.
  final String externalContentId;

  /// Free type such as `comment`, `image`, `profile` or `message`.
  final String contentType;

  final String? text;

  /// https URLs Limenia can download without login (e.g. signed URLs valid for
  /// at least an hour). JPEG, PNG, GIF, WebP, MP4, WebM and MOV up to 20 MB.
  final List<String> mediaUrls;

  /// Link to the content in the app, stored as a reference only.
  final String? externalUrl;

  /// When the content was created in the app.
  final DateTime? createdAt;

  /// Small JSON object for the moderators, at most 4 KB, IDs only.
  final Map<String, Object?>? context;

  factory ReportedContent.fromJson(JsonMap json) => ReportedContent(
        externalContentId: readRequired<String>(json, 'externalContentId'),
        contentType: readRequired<String>(json, 'contentType'),
        text: readOptional<String>(json, 'text'),
        mediaUrls: [for (final m in readObjectList(json, 'media')) readRequired<String>(m, 'url')],
        externalUrl: readOptional<String>(json, 'externalUrl'),
        createdAt: readOptionalDate(json, 'createdAt'),
        context: readOptionalObject(json, 'context'),
      );

  JsonMap toJson() => {
        'externalContentId': externalContentId,
        'contentType': contentType,
        if (text != null) 'text': text,
        if (mediaUrls.isNotEmpty)
          'media': [
            for (final url in mediaUrls) {'url': url}
          ],
        if (externalUrl != null) 'externalUrl': externalUrl,
        if (createdAt != null) 'createdAt': formatDate(createdAt!),
        if (context != null) 'context': context,
      };
}

/// A report in the format of `POST /v1/reports` (`CreateReportRequest`).
///
/// [toJson] gives exactly the body of the ingest API, so a backend can pass
/// it on. It should still set [reporterId] from its own login and, where
/// possible, load the content from its own database: the reporter's device
/// can send anything.
final class ReportRequest {
  const ReportRequest({
    required this.source,
    required this.reasonCategory,
    this.reasonText,
    this.goodFaith,
    this.reporterId,
    this.subject,
    this.content,
    this.externalReportId,
    this.trustedFlaggerId,
  });

  /// A user reports a content. Always pass the [author], otherwise moderators
  /// cannot warn or suspend them.
  const ReportRequest.content({
    required this.reasonCategory,
    required ReportedContent this.content,
    required ReportedUser author,
    this.reporterId,
    this.reasonText,
    this.goodFaith,
    this.source = ReportSource.user,
    this.externalReportId,
    this.trustedFlaggerId,
  }) : subject = author;

  /// A user reports another user, e.g. a profile, without a single content.
  const ReportRequest.user({
    required this.reasonCategory,
    required ReportedUser this.subject,
    this.reporterId,
    this.reasonText,
    this.goodFaith,
    this.source = ReportSource.user,
    this.externalReportId,
    this.trustedFlaggerId,
  }) : content = null;

  final ReportSource source;

  /// Usually the code of a policy of the tenant, see [ReasonCategory].
  final String reasonCategory;

  /// Free text of the reporter.
  final String? reasonText;

  /// Whether the reporting person confirmed that they believe in good faith
  /// that the information and allegations in the report are accurate and
  /// complete (Art. 16(2)(d) DSA), e.g. with the checkbox of the report sheet
  /// in `package:limenia/ui.dart` (`ReportDraft.goodFaithConfirmed`), from
  /// API version 0.22.0. Null leaves the field out, which Limenia counts as not
  /// confirmed, the same as `false`.
  ///
  /// Only with [ReportSource.user]: with [ReportSource.system] any value,
  /// also `false`, is `validation_failed` with the field error `invalid` at
  /// `/goodFaith`. Limenia stores it and shows it to moderators, but does not
  /// treat the report differently. Unlike [reporterId] it is a statement of
  /// the person on the device, so the backend may pass it on as it is.
  final bool? goodFaith;

  /// ID of the reporter in the app. Limenia stores only a hash of it. Leave it
  /// out for [ReportSource.system].
  final String? reporterId;

  final ReportedUser? subject;
  final ReportedContent? content;

  /// Optional ID of the report in the app, at most 128 characters. Limenia
  /// returns it in `reports.resolved`, so the app can tell the reporter how
  /// the report was decided (Art. 16 (5) DSA).
  final String? externalReportId;

  /// ID (ULID) of the trusted flagger of the tenant (Art. 22 DSA) the
  /// reporting person acts for, from API version 0.16.0. Only with
  /// [ReportSource.user]. The app decides who reports for a trusted flagger,
  /// e.g. through its own account of the organisation: set it in your backend
  /// from your own records ([withTrustedFlagger]), never from the device.
  ///
  /// Limenia accepts only a flagger that exists and is active (otherwise
  /// `validation_failed` with the field error `unknown` at
  /// `/trustedFlaggerId`). The case then gets at least the priority `high`,
  /// and the statement of reasons names [NoticeSource.trustedFlagger].
  final String? trustedFlaggerId;

  factory ReportRequest.fromJson(JsonMap json) {
    final reporter = readOptionalObject(json, 'reporter');
    final subject = readOptionalObject(json, 'subject');
    final content = readOptionalObject(json, 'content');
    return ReportRequest(
      source: ReportSource.fromWire(readRequired<String>(json, 'source')),
      reasonCategory: readRequired<String>(json, 'reasonCategory'),
      reasonText: readOptional<String>(json, 'reasonText'),
      goodFaith: readOptional<bool>(json, 'goodFaith'),
      reporterId: reporter == null ? null : readRequired<String>(reporter, 'externalUserId'),
      subject: subject == null ? null : ReportedUser.fromJson(subject),
      content: content == null ? null : ReportedContent.fromJson(content),
      externalReportId: readOptional<String>(json, 'externalReportId'),
      trustedFlaggerId: readOptional<String>(json, 'trustedFlaggerId'),
    );
  }

  JsonMap toJson() => {
        'source': source.name,
        'reasonCategory': reasonCategory,
        if (reasonText != null) 'reasonText': reasonText,
        if (goodFaith != null) 'goodFaith': goodFaith,
        if (reporterId != null) 'reporter': {'externalUserId': reporterId},
        if (subject != null) 'subject': subject!.toJson(),
        if (content != null) 'content': content!.toJson(),
        if (externalReportId != null) 'externalReportId': externalReportId,
        if (trustedFlaggerId != null) 'trustedFlaggerId': trustedFlaggerId,
      };

  /// A copy with another reporter, e.g. the user a backend has authenticated.
  /// All other fields stay, [goodFaith] too. A [trustedFlaggerId] stays as
  /// well: set it with [withTrustedFlagger].
  ReportRequest withReporter(String? reporterId) => ReportRequest(
        source: source,
        reasonCategory: reasonCategory,
        reasonText: reasonText,
        goodFaith: goodFaith,
        reporterId: reporterId,
        subject: subject,
        content: content,
        externalReportId: externalReportId,
        trustedFlaggerId: trustedFlaggerId,
      );

  /// A copy with another trusted flagger, or none (null) for an ordinary
  /// reporter. A backend calls this next to [withReporter] with what it
  /// knows about the authenticated user, so that a device cannot claim to be a
  /// trusted flagger.
  ReportRequest withTrustedFlagger(String? trustedFlaggerId) => ReportRequest(
        source: source,
        reasonCategory: reasonCategory,
        reasonText: reasonText,
        goodFaith: goodFaith,
        reporterId: reporterId,
        subject: subject,
        content: content,
        externalReportId: externalReportId,
        trustedFlaggerId: trustedFlaggerId,
      );
}

/// A moderator warned the reporter for frequently submitting manifestly
/// unfounded notices (Art. 23 DSA), see [ReportReceipt.reporterWarning]
/// (`ReporterWarning`, API version 0.16.0).
final class ReporterWarning {
  const ReporterWarning({required this.issuedAt});

  /// When the moderator issued the warning.
  final DateTime issuedAt;

  factory ReporterWarning.fromJson(JsonMap json) => ReporterWarning(issuedAt: readDate(json, 'issuedAt'));

  JsonMap toJson() => {'issuedAt': formatDate(issuedAt)};

  @override
  bool operator ==(Object other) => other is ReporterWarning && other.issuedAt == issuedAt;

  @override
  int get hashCode => issuedAt.hashCode;

  @override
  String toString() => 'ReporterWarning(issuedAt: $issuedAt)';
}

/// Answer of `POST /v1/reports` (`CreatedReport`).
final class ReportReceipt {
  const ReportReceipt({
    required this.reportId,
    required this.caseId,
    required this.caseCreated,
    this.reporterWarning,
  });

  final String reportId;
  final String caseId;

  /// False if Limenia added the report to an open case.
  final bool caseCreated;

  /// Set while a moderator's warning for misuse of the notice procedure
  /// (Art. 23 DSA) stands against the reporter, from API version 0.16.0: show
  /// the reporter a warning that further manifestly unfounded notices can
  /// lead to a suspension of their notices. The first answer that carries it
  /// counts as delivered. Null otherwise and with Limenia before 0.16.0.
  ///
  /// A repeated request with the same idempotency key gets the original
  /// answer, so the warning may be missing there: show it whenever it is set.
  final ReporterWarning? reporterWarning;

  factory ReportReceipt.fromJson(JsonMap json) {
    final warning = readOptionalObject(json, 'reporterWarning');
    return ReportReceipt(
      reportId: readRequired<String>(json, 'reportId'),
      caseId: readRequired<String>(json, 'caseId'),
      caseCreated: readRequired<bool>(json, 'caseCreated'),
      reporterWarning: warning == null ? null : ReporterWarning.fromJson(warning),
    );
  }

  JsonMap toJson() => {
        'reportId': reportId,
        'caseId': caseId,
        'caseCreated': caseCreated,
        if (reporterWarning != null) 'reporterWarning': reporterWarning!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is ReportReceipt &&
      other.reportId == reportId &&
      other.caseId == caseId &&
      other.caseCreated == caseCreated &&
      other.reporterWarning == reporterWarning;

  @override
  int get hashCode => Object.hash(reportId, caseId, caseCreated, reporterWarning);

  @override
  String toString() =>
      'ReportReceipt(reportId: $reportId, caseId: $caseId, caseCreated: $caseCreated, reporterWarning: $reporterWarning)';
}
