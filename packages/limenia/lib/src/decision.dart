import 'json.dart';

/// Measure of a decision (`ModerationAction`). Every decision has exactly one.
enum ModerationAction {
  /// No violation. Content and account stay as they are.
  dismiss('dismiss'),

  /// Remove or permanently hide the content.
  removeContent('remove_content'),

  /// Restrict the visibility of the content, e.g. take it out of feeds.
  restrictContent('restrict_content'),

  /// Warn the user without restricting the account.
  warnUser('warn_user'),

  /// Suspend the account until `suspendUntil`.
  suspendUser('suspend_user'),

  /// Ban the account permanently.
  banUser('ban_user'),

  /// Lift an earlier restriction, of the content or of the account as
  /// [ModerationDecision.restoreScope] says.
  ///
  /// [RestoreScope.content]: restore the content, e.g. after a complaint
  /// against [removeContent] or [restrictContent]. In a decision about a
  /// review request ([ModerationDecision.reviewId], after a complaint) the
  /// submitted content may be published as submitted. The status of the user
  /// stays as it is. [RestoreScope.account]: the user is active again.
  restore('restore'),

  /// Refuse to publish content submitted for review (`review.decided` with
  /// `rejected`), in the statement of reasons "refusal to publish
  /// the content". Do not publish the content. The author can complain
  /// against it.
  rejectSubmission('reject_submission');

  const ModerationAction(this.wireName);

  /// Value in the API, e.g. `remove_content`.
  final String wireName;

  /// The action for [value], or null for an action this version of the
  /// package does not know yet.
  static ModerationAction? tryParse(String value) {
    for (final action in values) {
      if (action.wireName == value) return action;
    }
    return null;
  }

  /// Whether the action changes the status of the user in Limenia.
  ///
  /// This looks at the action alone. A decision with
  /// [ModerationDecision.reviewId] never changes the status, whatever its
  /// action ([restore] included), and neither does a [restore] of the content
  /// ([RestoreScope.content]): for a decision, ask
  /// [ModerationDecision.changesUserStatus].
  bool get changesUserStatus => switch (this) {
        warnUser || suspendUser || banUser || restore => true,
        dismiss || removeContent || restrictContent || rejectSubmission => false,
      };

  /// Whether the action is about the content.
  bool get targetsContent => this == removeContent || this == restrictContent || this == rejectSubmission;

  /// Whether the affected user must see the statement of reasons: for every
  /// action except [dismiss] (Art. 17 DSA). For [restore] it tells them that
  /// a restriction was lifted.
  bool get informsAffectedUser => this != dismiss;
}

/// What a decision [ModerationAction.restore] lifts (`RestoreScope`, API
/// version 0.13.2), see [ModerationDecision.restoreScope].
enum RestoreScope {
  /// The restriction of the content: after a complaint against
  /// [ModerationAction.removeContent] or [ModerationAction.restrictContent],
  /// and for every restore about a review request
  /// ([ModerationDecision.reviewId]). Restore the content
  /// ([ModerationDecision.externalContentId]) or publish it as submitted. The
  /// status and the account of the user stay as they are, a suspension or a
  /// ban too.
  content,

  /// The restriction of the account: the user is active again. For a restore
  /// from the user file or on a case, and after a complaint against
  /// [ModerationAction.warnUser], [ModerationAction.suspendUser] or
  /// [ModerationAction.banUser].
  account;

  /// The scope for [value], or null for a scope this version of the package
  /// does not know yet.
  static RestoreScope? tryParse(String value) => values.asNameMap()[value];
}

/// What led to a decision (`StatementOfReasonsStructured.noticeSource`, API
/// version 0.16.0), see [SorDetails.noticeSource].
enum NoticeSource {
  /// Reports of users (`source: user`) led to the decision.
  notice('notice'),

  /// At least one report of the case comes from a trusted flagger (Art. 22
  /// DSA). The text of the statement says so, without naming the flagger.
  trustedFlagger('trusted_flagger'),

  /// Limenia or the tenant acted on its own: a case with reports of the app
  /// itself (`source: system`) only, an action in the user file, or a review
  /// request.
  ownInitiative('own_initiative');

  const NoticeSource(this.wireName);

  /// Value in the API, e.g. `trusted_flagger`.
  final String wireName;

  /// The source for [value], or null for a value this version of the package
  /// does not know yet.
  static NoticeSource? tryParse(String value) {
    for (final source in values) {
      if (source.wireName == value) return source;
    }
    return null;
  }

  /// What a decision without `noticeSource` (from before API version 0.16.0)
  /// means: a report of a user ([basedOnNotice]) or the own initiative.
  static NoticeSource fromBasedOnNotice({required bool basedOnNotice}) => basedOnNotice ? notice : ownInitiative;
}

/// Use of automated means for a decision
/// (`StatementOfReasonsStructured.automation`, API version 0.19.0),
/// see [SorDetails.automation].
enum Automation {
  /// A human decided without a suggestion of the AI pre-screening. Every
  /// decision from before API version 0.19.0 is `none`.
  none('none'),

  /// A moderator took and confirmed a suggestion of the AI pre-screening (stage
  /// A). A human still decided.
  partial('partial'),

  /// An automatic decision without a moderator (stage B). The only value with
  /// [SorDetails.automatedDecision] `true`.
  full('full');

  const Automation(this.wireName);

  /// Value in the API, e.g. `partial`.
  final String wireName;

  /// Whether automated means were used for the decision ([partial] or
  /// [full]). Art. 17(3)(c) DSA requires the statement of reasons to say so.
  bool get usesAutomatedMeans => this != none;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static Automation? tryParse(String value) {
    for (final automation in values) {
      if (automation.wireName == value) return automation;
    }
    return null;
  }
}

/// Legal basis of a ground in the statement of reasons.
enum LegalBasis {
  /// Violation of the terms of the app.
  terms,

  /// Illegal content.
  law;

  static LegalBasis fromWire(String value) => switch (value) {
        'terms' => terms,
        'law' => law,
        _ => throw FormatException('Limenia: unknown legal basis', value),
      };
}

/// Policy a decision is based on.
final class PolicyRef {
  const PolicyRef({required this.code, required this.title});

  final String code;
  final String title;

  factory PolicyRef.fromJson(JsonMap json) =>
      PolicyRef(code: readRequired<String>(json, 'code'), title: readRequired<String>(json, 'title'));

  JsonMap toJson() => {'code': code, 'title': title};
}

/// One ground of the statement of reasons.
final class SorGround {
  const SorGround({required this.basis, required this.policyCode, required this.title, this.lawReference});

  final LegalBasis basis;
  final String policyCode;
  final String title;

  /// Only for [LegalBasis.law].
  final String? lawReference;

  factory SorGround.fromJson(JsonMap json) => SorGround(
        basis: LegalBasis.fromWire(readRequired<String>(json, 'basis')),
        policyCode: readRequired<String>(json, 'policyCode'),
        title: readRequired<String>(json, 'title'),
        lawReference: readOptional<String>(json, 'lawReference'),
      );

  JsonMap toJson() => {
        'basis': basis.name,
        'policyCode': policyCode,
        'title': title,
        if (lawReference != null) 'lawReference': lawReference,
      };
}

/// Structured statement of reasons, for an own layout or other languages.
final class SorDetails {
  const SorDetails({
    required this.actionName,
    required this.territorialScope,
    required this.facts,
    required this.basedOnNotice,
    required this.automatedDetection,
    required this.automatedDecision,
    required this.grounds,
    required this.redress,
    this.endsAt,
    this.noticeSourceName,
    this.automationName,
  });

  /// Wire value of the action, see [action].
  final String actionName;

  /// End of a temporary restriction.
  final DateTime? endsAt;

  /// Scope of the restriction, `app` for the whole app.
  final String territorialScope;

  /// Facts as written by the moderator.
  final String facts;

  /// The decision follows a report of a user. See [noticeSource] for the
  /// finer distinction since API version 0.16.0.
  final bool basedOnNotice;

  /// Wire value of [noticeSource] as Limenia sent it (`notice`,
  /// `trusted_flagger`, `own_initiative` or a value this version does not
  /// know yet). Null for a decision from before API version 0.16.0.
  final String? noticeSourceName;

  /// What led to the decision (API version 0.16.0): a report of a user, of a
  /// trusted flagger, or the own initiative. Never null: a decision from
  /// before API version 0.16.0 has no `noticeSource` and derives it from
  /// [basedOnNotice] (`true` is [NoticeSource.notice], `false` is
  /// [NoticeSource.ownInitiative]), the same as for a value this package
  /// version does not know. Look at [noticeSourceName] to tell them apart.
  NoticeSource get noticeSource =>
      NoticeSource.tryParse(noticeSourceName ?? '') ?? NoticeSource.fromBasedOnNotice(basedOnNotice: basedOnNotice);

  /// Whether the case has at least one report with `source: system`, detected
  /// automatically by the app itself or by Limenia (API version 0.16.0). The
  /// statement then says that the occasion was detected automatically and a
  /// human decided. [automatedDecision] is separate and false as long as a
  /// human decides.
  final bool automatedDetection;

  /// Whether the decision was made automatically, without a moderator. True
  /// only for [Automation.full] (API version 0.19.0); it stays false for
  /// [Automation.partial], where a moderator took and confirmed a suggestion.
  /// See [automation].
  final bool automatedDecision;

  /// Wire value of [automation] as Limenia sent it (`none`, `partial`, `full`
  /// or a value this version does not know yet). Null for a decision from
  /// before API version 0.19.0.
  final String? automationName;

  /// Use of automated means for the decision (API version 0.19.0): none, a
  /// moderator confirmed an AI suggestion ([Automation.partial]) or an
  /// automatic decision ([Automation.full]). Never null: a decision from
  /// before API version 0.19.0 has no `automation` and is [Automation.none],
  /// the same as for a value this package version does not know. Look at
  /// [automationName] to tell them apart.
  ///
  /// With [Automation.usesAutomatedMeans] show the affected user that
  /// automated means were used (Art. 17(3)(c) DSA). [automatedDecision] is
  /// not enough for that, because it is `false` for [Automation.partial].
  Automation get automation => Automation.tryParse(automationName ?? '') ?? Automation.none;

  final List<SorGround> grounds;

  /// Means of redress, text of the tenant.
  final String redress;

  ModerationAction? get action => ModerationAction.tryParse(actionName);

  factory SorDetails.fromJson(JsonMap json) => SorDetails(
        actionName: readRequired<String>(json, 'action'),
        endsAt: readOptionalDate(json, 'endsAt'),
        territorialScope: readRequired<String>(json, 'territorialScope'),
        facts: readRequired<String>(json, 'facts'),
        basedOnNotice: readRequired<bool>(json, 'basedOnNotice'),
        noticeSourceName: readOptional<String>(json, 'noticeSource'),
        automatedDetection: readRequired<bool>(json, 'automatedDetection'),
        automatedDecision: readRequired<bool>(json, 'automatedDecision'),
        automationName: readOptional<String>(json, 'automation'),
        grounds: [for (final g in readObjectList(json, 'grounds')) SorGround.fromJson(g)],
        redress: readRequired<String>(json, 'redress'),
      );

  JsonMap toJson() => {
        'action': actionName,
        if (endsAt != null) 'endsAt': formatDate(endsAt!),
        'territorialScope': territorialScope,
        'facts': facts,
        'basedOnNotice': basedOnNotice,
        'noticeSource': noticeSourceName ?? noticeSource.wireName,
        'automatedDetection': automatedDetection,
        'automatedDecision': automatedDecision,
        'automation': automationName ?? automation.wireName,
        'grounds': [for (final g in grounds) g.toJson()],
        'redress': redress,
      };
}

/// Statement of reasons (Art. 17 DSA) the app shows the affected user.
final class StatementOfReasons {
  const StatementOfReasons({required this.locale, required this.text, required this.structured});

  /// Language of [text], the language of the tenant (`de` or `en`).
  final String locale;

  /// Ready-made text with line breaks as `\n`. Show it as plain text, never
  /// as HTML or Markdown: it contains the free text of the moderator.
  final String text;

  final SorDetails structured;

  factory StatementOfReasons.fromJson(JsonMap json) => StatementOfReasons(
        locale: readRequired<String>(json, 'locale'),
        text: readRequired<String>(json, 'text'),
        structured: SorDetails.fromJson(readObject(json, 'structured')),
      );

  JsonMap toJson() => {'locale': locale, 'text': text, 'structured': structured.toJson()};
}

/// A decision as Limenia sends it in `decision.created` (`WebhookDecision`).
///
/// Apps usually get it from their backend, which receives the webhook. Use
/// [ModerationDecision.fromJson] on the `decision` object of the event.
final class ModerationDecision {
  const ModerationDecision({
    required this.id,
    required this.actionName,
    required this.policies,
    required this.statementOfReasons,
    required this.decidedAt,
    this.suspendUntil,
    this.externalContentId,
    this.externalUserId,
    this.appealId,
    this.replacesDecisionId,
    this.reviewId,
    this.restoreScopeName,
  });

  final String id;

  /// Wire value of the action, see [action].
  final String actionName;

  /// End of a suspension, only for [ModerationAction.suspendUser].
  final DateTime? suspendUntil;

  /// The content of the case, if it has one. Present independent of the action.
  final String? externalContentId;

  /// The user of the case, if it has one. Present independent of the action.
  final String? externalUserId;

  /// Limenia ID of the appeal this decision results from, null for a first decision.
  final String? appealId;

  /// ID of the earlier decision this one replaces after an appeal, otherwise null.
  final String? replacesDecisionId;

  /// Limenia ID of the review request this decision is about,
  /// otherwise null. Set for the restriction or rejection of the request
  /// (`review.decided` follows) and for a new decision on it after a complaint
  /// (then together with [appealId] and [replacesDecisionId]).
  ///
  /// Such a decision never changes the status of the author, see
  /// [changesUserStatus].
  final String? reviewId;

  /// Wire value of `restoreScope`, see [restoreScope]. Null if the event has
  /// none: Limenia sets it only for [ModerationAction.restore], from API
  /// version 0.13.2.
  final String? restoreScopeName;

  /// Can be empty for [ModerationAction.dismiss] and [ModerationAction.restore].
  final List<PolicyRef> policies;

  final StatementOfReasons statementOfReasons;

  /// Use it to ignore older decisions that arrive late.
  final DateTime decidedAt;

  /// The action, or null for an action this version of the package does not
  /// know yet. Acknowledge such decisions and log them.
  ModerationAction? get action => ModerationAction.tryParse(actionName);

  /// What a [ModerationAction.restore] lifts (API version 0.13.2):
  ///
  /// * [RestoreScope.content]: the restriction of the content, e.g. after a
  ///   complaint against [ModerationAction.removeContent] or
  ///   [ModerationAction.restrictContent], and for every restore about a
  ///   review request ([reviewId]). Restore the content
  ///   ([externalContentId]). The status and the account of the user stay as
  ///   they are, a suspension or a ban too.
  /// * [RestoreScope.account]: the restriction of the account. The user is
  ///   active again.
  ///
  /// Null for other actions and for a restore from Limenia before API version
  /// 0.13.2, which lifted the restriction of the account, or of the content
  /// with [reviewId]. Also null for a scope this version of the package does
  /// not know yet: [restoreScopeName] has it, acknowledge such a decision and
  /// log it.
  RestoreScope? get restoreScope {
    final name = restoreScopeName;
    return name == null ? null : RestoreScope.tryParse(name);
  }

  /// Whether the decision changes the status of the user in Limenia. This is
  /// the one apps should use, not [ModerationAction.changesUserStatus], which
  /// looks at the action alone:
  ///
  /// * A decision about a review request ([reviewId]) never changes the
  ///   status or the account of the author, not even
  ///   [ModerationAction.restore], which then only lets the submitted content
  ///   be published as submitted.
  /// * A [ModerationAction.restore] changes it only if it lifts the
  ///   restriction of the account: [RestoreScope.account], or no
  ///   [restoreScope] at all from Limenia before API version 0.13.2. A
  ///   restore of the content ([RestoreScope.content]) keeps the status, a
  ///   suspension or a ban too.
  ///
  /// False for an action or a restore scope this version of the package does
  /// not know.
  bool get changesUserStatus {
    if (reviewId != null) return false;
    return switch (action) {
      ModerationAction.restore => restoreScopeName == null || restoreScope == RestoreScope.account,
      final other? => other.changesUserStatus,
      null => false,
    };
  }

  factory ModerationDecision.fromJson(JsonMap json) {
    final content = readOptionalObject(json, 'content');
    final subject = readOptionalObject(json, 'subject');
    return ModerationDecision(
      id: readRequired<String>(json, 'id'),
      actionName: readRequired<String>(json, 'action'),
      suspendUntil: readOptionalDate(json, 'suspendUntil'),
      externalContentId: content == null ? null : readRequired<String>(content, 'externalContentId'),
      externalUserId: subject == null ? null : readRequired<String>(subject, 'externalUserId'),
      policies: [for (final p in readObjectList(json, 'policies')) PolicyRef.fromJson(p)],
      statementOfReasons: StatementOfReasons.fromJson(readObject(json, 'statementOfReasons')),
      decidedAt: readDate(json, 'decidedAt'),
      appealId: readOptional<String>(json, 'appealId'),
      replacesDecisionId: readOptional<String>(json, 'replacesDecisionId'),
      reviewId: readOptional<String>(json, 'reviewId'),
      restoreScopeName: readOptional<String>(json, 'restoreScope'),
    );
  }

  JsonMap toJson() => {
        'id': id,
        'action': actionName,
        if (suspendUntil != null) 'suspendUntil': formatDate(suspendUntil!),
        if (externalContentId != null) 'content': {'externalContentId': externalContentId},
        if (externalUserId != null) 'subject': {'externalUserId': externalUserId},
        'policies': [for (final p in policies) p.toJson()],
        'statementOfReasons': statementOfReasons.toJson(),
        'decidedAt': formatDate(decidedAt),
        if (appealId != null) 'appealId': appealId,
        if (replacesDecisionId != null) 'replacesDecisionId': replacesDecisionId,
        if (reviewId != null) 'reviewId': reviewId,
        if (restoreScopeName != null) 'restoreScope': restoreScopeName,
      };
}
