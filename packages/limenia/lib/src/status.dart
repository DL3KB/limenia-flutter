import 'decision.dart';
import 'json.dart';

/// Sanction status of a user in Limenia (`SubjectSanctionStatus`).
enum SanctionStatus {
  active,
  warned,
  suspended,
  banned;

  static SanctionStatus fromWire(String value) => switch (value) {
        'active' => active,
        'warned' => warned,
        'suspended' => suspended,
        'banned' => banned,
        _ => throw FormatException('Limenia: unknown sanction status', value),
      };
}

/// Status of a user (`SubjectStatus`), from `GET /v1/subjects/{id}/status` or
/// the event `subject.status_changed`.
final class SubjectStatus {
  const SubjectStatus({required this.externalUserId, required this.status, this.suspendedUntil});

  /// A user Limenia does not know, or one without sanctions.
  const SubjectStatus.active(this.externalUserId)
      : status = SanctionStatus.active,
        suspendedUntil = null;

  final String externalUserId;
  final SanctionStatus status;

  /// End of the suspension, only for [SanctionStatus.suspended].
  final DateTime? suspendedUntil;

  /// The status at [now]: a suspension that has ended counts as active, as
  /// in Limenia's status endpoint. Limenia lifts it only up to an hour later,
  /// or with the next decision about the user (`subject.status_changed`), so
  /// the app must enforce the end itself.
  SubjectStatus effectiveAt(DateTime now) {
    final until = suspendedUntil;
    if (status == SanctionStatus.suspended && until != null && !until.isAfter(now)) {
      return SubjectStatus.active(externalUserId);
    }
    return this;
  }

  /// Whether the account may not be used at [now].
  bool isRestrictedAt(DateTime now) => switch (effectiveAt(now).status) {
        SanctionStatus.suspended || SanctionStatus.banned => true,
        SanctionStatus.active || SanctionStatus.warned => false,
      };

  /// The status after [decision], with the same rules as Limenia: a warning
  /// only changes an active user, a suspension or ban replaces the status,
  /// and a restore of the account makes the user active. A suspension that
  /// has ended by the time of the decision ([ModerationDecision.decidedAt])
  /// counts as lifted, so a warning then makes the user warned. Other actions
  /// keep the status, and so does every decision that does not change it
  /// ([ModerationDecision.changesUserStatus]): one about a review request
  /// ([ModerationDecision.reviewId]) and a restore of the content
  /// ([RestoreScope.content]).
  SubjectStatus afterDecision(ModerationDecision decision) {
    if (!decision.changesUserStatus) return this;
    return switch (decision.action) {
      ModerationAction.warnUser when effectiveAt(decision.decidedAt).status == SanctionStatus.active =>
        SubjectStatus(externalUserId: externalUserId, status: SanctionStatus.warned),
      ModerationAction.suspendUser => SubjectStatus(
          externalUserId: externalUserId,
          status: SanctionStatus.suspended,
          suspendedUntil: decision.suspendUntil,
        ),
      ModerationAction.banUser => SubjectStatus(externalUserId: externalUserId, status: SanctionStatus.banned),
      ModerationAction.restore => SubjectStatus.active(externalUserId),
      _ => this,
    };
  }

  factory SubjectStatus.fromJson(JsonMap json) => SubjectStatus(
        externalUserId: readRequired<String>(json, 'externalUserId'),
        status: SanctionStatus.fromWire(readRequired<String>(json, 'status')),
        suspendedUntil: readOptionalDate(json, 'suspendedUntil'),
      );

  JsonMap toJson() => {
        'externalUserId': externalUserId,
        'status': status.name,
        if (suspendedUntil != null) 'suspendedUntil': formatDate(suspendedUntil!),
      };

  @override
  bool operator ==(Object other) =>
      other is SubjectStatus &&
      other.externalUserId == externalUserId &&
      other.status == status &&
      other.suspendedUntil == suspendedUntil;

  @override
  int get hashCode => Object.hash(externalUserId, status, suspendedUntil);

  @override
  String toString() =>
      'SubjectStatus($externalUserId, ${status.name}${suspendedUntil == null ? '' : ' until $suspendedUntil'})';
}
