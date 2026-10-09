// The package is written by hand. This test keeps it in line with the API:
// spec/openapi.yaml is a copy of the public OpenAPI description of Limenia
// (https://limenia.eu/openapi/v1.yaml: the /v1 operations and the webhook
// events). Update it with tool/sync_openapi.sh.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late YamlMap schemas;

  setUpAll(() {
    final spec = loadYaml(File('spec/openapi.yaml').readAsStringSync()) as YamlMap;
    schemas = (spec['components'] as YamlMap)['schemas'] as YamlMap;
  });

  YamlMap schema(String name) => schemas[name] as YamlMap;
  List<String> enumOf(String name) => [for (final v in schema(name)['enum'] as YamlList) v as String];
  YamlMap prop(String schemaName, String property) =>
      (schema(schemaName)['properties'] as YamlMap)[property] as YamlMap;

  test('enums', () {
    expect([for (final a in ModerationAction.values) a.wireName], enumOf('ModerationAction'));
    expect([for (final s in SanctionStatus.values) s.name], enumOf('SubjectSanctionStatus'));
    expect([for (final s in ReportSource.values) s.name], enumOf('ReportSource'));
    expect([for (final b in LegalBasis.values) b.name], enumOf('LegalBasis'));
    expect(
      [
        DecisionCreatedEvent.eventType,
        SubjectStatusChangedEvent.eventType,
        AppealResolvedEvent.eventType,
        ReportsResolvedEvent.eventType,
        ReviewDecidedEvent.eventType,
        TestPingEvent.eventType,
      ],
      enumOf('EventType'),
    );
    expect([for (final t in AppellantType.values) t.name], enumOf('AppellantType'));
    expect([for (final s in AppealStatus.values) s.wireName], enumOf('AppealStatus'));
    expect([for (final o in AppealOutcome.values) o.name], enumOf('AppealOutcome'));
    expect([for (final s in ReviewStatus.values) s.wireName], enumOf('ReviewStatus'));
    expect([for (final o in ReviewOutcome.values) o.name], enumOf('ReviewOutcome'));
    expect([for (final s in RestoreScope.values) s.name], enumOf('RestoreScope'));
    expect(prop('WebhookDecision', 'restoreScope')[r'$ref'], '#/components/schemas/RestoreScope');
    expect([
      for (final s in NoticeSource.values) s.wireName
    ], [
      for (final v in prop('StatementOfReasonsStructured', 'noticeSource')['enum'] as YamlList) v as String,
    ]);
    expect([
      for (final a in Automation.values) a.wireName
    ], [
      for (final v in prop('StatementOfReasonsStructured', 'automation')['enum'] as YamlList) v as String,
    ]);
    expect([for (final p in DevicePlatform.values) p.wireName], enumOf('DevicePlatform'));
    expect([for (final f in DeviceFlag.values) f.wireName], enumOf('DeviceFlag'));
    expect([for (final a in DeviceAction.values) a.wireName], enumOf('DeviceAction'));
    expect([for (final e in DeviceCheckEvent.values) e.wireName], enumOf('DeviceCheckEvent'));
    expect([for (final s in DeviceCheckStatus.values) s.wireName], enumOf('DeviceCheckStatus'));
    expect([for (final l in DeviceIntegrityLevel.values) l.wireName], enumOf('DeviceIntegrityLevel'));
    expect([for (final r in DeviceRisk.values) r.wireName], enumOf('DeviceRisk'));
    expect([
      for (final e in DeviceEnvironment.values) e.wireName
    ], [
      for (final v in prop('DeviceCheckRequest', 'environment')['enum'] as YamlList) v as String,
    ]);
  });

  test('trusted flaggers, reporter warnings and suspensions (API 0.16.0)', () {
    // The pattern of a flagger ID is the one of every ID the package checks.
    final pattern = prop('CreateReportRequest', 'trustedFlaggerId')['pattern'] as String;
    expect(pattern, r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$');
    expect(pattern, prop('CreateAppealRequest', 'decisionId')['pattern']);
    for (final id in [
      '01K6T2D0000000000000000000',
      '7ZZZZZZZZZZZZZZZZZZZZZZZZZ',
      '8ZZZZZZZZZZZZZZZZZZZZZZZZZ',
      '01K6T2D000000000000000000',
      '01k6t2d0000000000000000000',
      '01K6T2D000000000000000000U',
      '',
    ]) {
      final valid = validateReport(
        ReportRequest.user(reasonCategory: 'spam', subject: const ReportedUser('u'), trustedFlaggerId: id),
      ).isEmpty;
      expect(valid, RegExp(pattern).hasMatch(id), reason: id);
    }
    expect(prop('CreateReportRequest', 'trustedFlaggerId')['description'], contains('`source: user`'));

    // The warning is optional in the answer, the field is a $ref to ReporterWarning with issuedAt.
    expect(prop('CreatedReport', 'reporterWarning')[r'$ref'], '#/components/schemas/ReporterWarning');
    expect([for (final f in schema('ReporterWarning')['required'] as YamlList) f as String], ['issuedAt']);
    expect(schema('ReporterWarning')['properties'] as YamlMap, hasLength(1));
    expect(prop('ReporterWarning', 'issuedAt')['format'], 'date-time');

    // Problem.suspendedUntil is a timestamp, not required, and documented with reporter_suspended.
    expect(prop('Problem', 'suspendedUntil')['format'], 'date-time');
    expect(schema('Problem')['required'], isNot(contains('suspendedUntil')));
    expect(prop('Problem', 'suspendedUntil')['description'], contains('`${LimeniaException.reporterSuspendedCode}`'));

    // Reports and complaints can be answered with 403 reporter_suspended.
    final spec = loadYaml(File('spec/openapi.yaml').readAsStringSync()) as YamlMap;
    for (final path in ['/v1/reports', '/v1/appeals']) {
      final post = ((spec['paths'] as YamlMap)[path] as YamlMap)['post'] as YamlMap;
      expect(post['description'], matches(RegExp(r'403\s+`reporter_suspended`')), reason: path);
      expect((post['responses'] as YamlMap).containsKey('403'), isTrue, reason: path);
    }

    // noticeSource is required and documented to derive from basedOnNotice before 0.16.0.
    expect(schema('StatementOfReasonsStructured')['required'], contains('noticeSource'));
    expect(prop('StatementOfReasonsStructured', 'noticeSource')['description'], contains('`basedOnNotice`'));

    // automation (API 0.19.0) is required, from before 0.19.0 it is none, and automatedDecision is true only for full.
    expect(schema('StatementOfReasonsStructured')['required'], contains('automation'));
    expect(prop('StatementOfReasonsStructured', 'automation')['description'], contains('before API 0.19.0'));
    expect(prop('StatementOfReasonsStructured', 'automatedDecision')['description'], contains('`full`'));
  });

  test('good faith of the reporter (API 0.22.0)', () {
    final goodFaith = prop('CreateReportRequest', 'goodFaith');
    expect(goodFaith['type'], 'boolean');
    expect(schema('CreateReportRequest')['required'], isNot(contains('goodFaith')));
    expect(goodFaith['description'], contains('Art. 16(2)(d) DSA'));
    expect(goodFaith['description'], contains('`source: user`'));
    expect(goodFaith['description'], contains('`validation_failed`'));
    for (final value in [true, false]) {
      for (final source in ReportSource.values) {
        final request = ReportRequest.user(
          reasonCategory: 'spam',
          subject: const ReportedUser('u'),
          source: source,
          goodFaith: value,
        );
        expect(request.toJson()['goodFaith'], value);
        expect(validateReport(request).isEmpty, source == ReportSource.user, reason: '$source, $value');
      }
    }
  });

  test('limits of a report', () {
    expect(prop('CreateReportRequest', 'reasonText')['maxLength'], ReportLimits.reasonTextLength);
    expect(prop('ExternalUserRef', 'externalUserId')['maxLength'], ReportLimits.externalUserIdLength);
    expect(prop('ReportSubject', 'externalUserId')['maxLength'], ReportLimits.externalUserIdLength);
    expect(prop('ReportSubject', 'displayName')['maxLength'], ReportLimits.displayNameLength);
    expect(prop('ReportContent', 'externalContentId')['maxLength'], ReportLimits.externalContentIdLength);
    expect(prop('ReportContent', 'text')['maxLength'], ReportLimits.textLength);
    expect(prop('ReportContent', 'media')['maxItems'], ReportLimits.mediaCount);
    expect(prop('ReportContent', 'externalUrl')['maxLength'], ReportLimits.urlLength);
    expect(prop('ReportMedia', 'url')['maxLength'], ReportLimits.urlLength);
    expect(prop('ReportContent', 'context')['description'], contains('${ReportLimits.contextBytes ~/ 1024} KB'));
    expect(prop('CreateReportRequest', 'externalReportId')['maxLength'], ReportLimits.externalReportIdLength);
  });

  test('limits of a complaint', () {
    expect(prop('CreateAppealRequest', 'text')['maxLength'], AppealLimits.textLength);
    expect(prop('CreateAppealRequest', 'text')['minLength'], 1);
    expect(prop('CreateAppealRequest', 'externalAppealId')['maxLength'], AppealLimits.externalAppealIdLength);
    expect(prop('Appellant', 'externalUserId')['maxLength'], AppealLimits.externalUserIdLength);
    expect((prop('WebhookReportsResolved', 'items'))['maxItems'], 100);
  });

  test('the decision ID of a complaint is checked with the pattern of the spec', () {
    final pattern = prop('CreateAppealRequest', 'decisionId')['pattern'] as String;
    expect(pattern, r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$');
    for (final id in [
      '01K6G5H1TR8W4QZ3M0XCB7NDEC',
      '7ZZZZZZZZZZZZZZZZZZZZZZZZZ',
      '8ZZZZZZZZZZZZZZZZZZZZZZZZZ', // more than 128 bits
      '01K6G5H1TR8W4QZ3M0XCB7NDE', // 25 characters
      '01K6G5H1TR8W4QZ3M0XCB7NDECX',
      '01k6g5h1tr8w4qz3m0xcb7ndec',
      '01K6G5H1TR8W4QZ3M0XCB7NDEI', // I, L, O and U are not Crockford base 32
      '01K6G5H1TR8W4QZ3M0XCB7NDEU',
      '',
    ]) {
      final valid = validateAppeal(AppealRequest.subject(decisionId: id, externalUserId: 'u', text: 't')).isEmpty;
      expect(valid, RegExp(pattern).hasMatch(id), reason: id);
    }
  });

  test('a review request reuses the subject and content of a report', () {
    expect(prop('CreateReviewRequest', 'subject')[r'$ref'], '#/components/schemas/ReportSubject');
    expect(prop('CreateReviewRequest', 'content')[r'$ref'], '#/components/schemas/ReportContent');
    expect(prop('CreateReviewRequest', 'externalReviewId')['maxLength'], ReviewLimits.externalReviewIdLength);
    expect(prop('CreateReviewRequest', 'externalReviewId')['minLength'], 1);
    expect(prop('CreateReviewRequest', 'type')['pattern'], r'^[a-z0-9_]{2,40}$');
  });

  test('limits of signals (API 0.18.0)', () {
    expect(prop('CreateSignalsRequest', 'signals')['minItems'], 1);
    expect(prop('CreateSignalsRequest', 'signals')['maxItems'], SignalLimits.maxSignals);
    expect(prop('CreateSignalsRequest', 'signals')['items'], {r'$ref': '#/components/schemas/SignalInput'});
    expect(prop('SignalInput', 'type')['pattern'], r'^[a-z0-9_]{2,40}$');
    expect(prop('SignalInput', 'externalUserId')['minLength'], 1);
    expect(prop('SignalInput', 'externalUserId')['maxLength'], SignalLimits.externalUserIdLength);
    expect(prop('SignalInput', 'value')['type'], 'number');
    expect(prop('SignalInput', 'occurredAt')['format'], 'date-time');
    expect(prop('SignalInput', 'occurredAt')['description'], allOf(contains('5 minutes'), contains('24 hours')));
    expect(prop('SignalInput', 'context')['type'], 'object');
    expect(prop('SignalInput', 'context')['description'], contains('${SignalLimits.contextBytes ~/ 1024} KB'));
    expect(prop('CreatedSignals', 'accepted')['type'], 'integer');
  });

  test('POST /v1/signals goes through the transport like the other ingest operations', () {
    final spec = loadYaml(File('spec/openapi.yaml').readAsStringSync()) as YamlMap;
    final post = ((spec['paths'] as YamlMap)['/v1/signals'] as YamlMap)['post'] as YamlMap;
    expect(post['operationId'], 'ingestCreateSignals');
    expect(post['security'], [
      {'apiKey': <Object?>[]},
    ]);
    final responses = post['responses'] as YamlMap;
    expect(responses.keys, containsAll(['202', '400', '401', '402', '403', '409', '429']));
    final created = (((responses['202'] as YamlMap)['content'] as YamlMap)['application/json'] as YamlMap)['schema'];
    expect(created, {r'$ref': '#/components/schemas/CreatedSignals'});
    final body = ((post['requestBody'] as YamlMap)['content'] as YamlMap)['application/json'] as YamlMap;
    expect(body['schema'], {r'$ref': '#/components/schemas/CreateSignalsRequest'});

    // The codes the package documents and handles are those of the spec.
    expect(post['description'], allOf(contains('`signal_type_unknown`'), contains('`feature_not_in_plan`')));
    expect(post['description'], allOf(contains('`subscription_required`'), contains('all or nothing')));
  });

  test('limits of a device check (API 0.20.0)', () {
    expect(prop('DeviceCheckRequest', 'externalUserId')['minLength'], 1);
    expect(prop('DeviceCheckRequest', 'externalUserId')['maxLength'], DeviceCheckLimits.externalUserIdLength);
    expect(prop('DeviceCheckRequest', 'token')['minLength'], 1);
    expect(prop('DeviceCheckRequest', 'token')['maxLength'], DeviceCheckLimits.tokenLength);
    expect(prop('DeviceCheckRequest', 'token')['description'], contains('`test:<device>[:risk]`'));
    expect(prop('DeviceCheckRequest', 'requestHash')['minLength'], 1);
    expect(prop('DeviceCheckRequest', 'requestHash')['maxLength'], DeviceCheckLimits.requestHashLength);
    expect(prop('DeviceCheckRequest', 'environment')['description'], contains('iOS only'));
    // The helper computes the recommended hash of the spec.
    expect(
      prop('DeviceCheckRequest', 'requestHash')['description'],
      contains('`base64url(SHA-256("limenia:" + externalUserId + ":" + nonce))`'),
    );
    expect(prop('DeviceCheckRequest', 'platform')[r'$ref'], '#/components/schemas/DevicePlatform');
    expect(prop('DeviceCheckRequest', 'event')[r'$ref'], '#/components/schemas/DeviceCheckEvent');
    expect(prop('DeviceCheckResult', 'subject')[r'$ref'], '#/components/schemas/SubjectStatus');
    expect(prop('DeviceCheckResult', 'integrity')[r'$ref'], '#/components/schemas/DeviceIntegrity');
    expect(prop('DeviceCheckResult', 'flaggedSince')['pattern'], r'^[0-9]{4}-[0-9]{2}$');
    expect(prop('DeviceIntegrity', 'risks')['items'], {r'$ref': '#/components/schemas/DeviceRisk'});
    expect(schema('DeviceRisk')['description'], contains('Later versions add values'));
  });

  test('POST /v1/devices/check goes through the transport, without an idempotency key', () {
    final spec = loadYaml(File('spec/openapi.yaml').readAsStringSync()) as YamlMap;
    final post = ((spec['paths'] as YamlMap)['/v1/devices/check'] as YamlMap)['post'] as YamlMap;
    expect(post['operationId'], 'ingestCheckDevice');
    expect(post['security'], [
      {'apiKey': <Object?>[]},
    ]);
    expect(post['parameters'], isNull);
    final responses = post['responses'] as YamlMap;
    expect(responses.keys, containsAll(['200', '400', '401', '402', '403', '409', '429']));
    final ok = (((responses['200'] as YamlMap)['content'] as YamlMap)['application/json'] as YamlMap)['schema'];
    expect(ok, {r'$ref': '#/components/schemas/DeviceCheckResult'});
    final body = ((post['requestBody'] as YamlMap)['content'] as YamlMap)['application/json'] as YamlMap;
    expect(body['schema'], {r'$ref': '#/components/schemas/DeviceCheckRequest'});

    // The codes the package documents and names are those of the spec.
    expect(
      post['description'],
      allOf(
        contains('`${LimeniaException.invalidDeviceTokenCode}`'),
        contains('`${LimeniaException.deviceConnectorNotConfiguredCode}`'),
        contains('No `Idempotency-Key`'),
        contains('`status: unevaluated`'),
      ),
    );
  });

  test('every ingest operation of the API has a method in the transport or is a known gap', () {
    // A new operation under /v1 fails here until the package covers it or
    // the list below says why it does not.
    final spec = loadYaml(File('spec/openapi.yaml').readAsStringSync()) as YamlMap;
    final operations = {
      for (final MapEntry(key: path, value: item) in (spec['paths'] as YamlMap).entries)
        if ((path as String).startsWith('/v1/'))
          for (final MapEntry(key: method, value: op) in (item as YamlMap).entries)
            if (method != 'parameters')
              '${(method as String).toUpperCase()} $path': (op as YamlMap)['operationId'] as String,
    };
    const covered = {
      'POST /v1/reports': 'ingestCreateReport',
      'GET /v1/subjects/{externalUserId}/status': 'ingestGetSubjectStatus',
      'POST /v1/appeals': 'ingestCreateAppeal',
      'GET /v1/appeals/{appealId}': 'ingestGetAppeal',
      'POST /v1/reviews': 'ingestCreateReview',
      'GET /v1/reviews/{reviewId}': 'ingestGetReview',
      'POST /v1/signals': 'ingestCreateSignals',
      'POST /v1/devices/check': 'ingestCheckDevice',
    };
    const notForApps = {
      // Backend of the app only: health check, display name and the connector webhook of RevenueCat.
      'GET /v1/ping',
      'PUT /v1/subjects/{externalUserId}',
      'POST /v1/integrations/revenuecat/{tenantId}/{appId}',
    };
    expect({
      for (final e in operations.entries)
        if (!notForApps.contains(e.key)) e.key: e.value
    }, covered);
  });

  test('patterns', () {
    expect(prop('CreateReportRequest', 'reasonCategory')['pattern'], r'^[a-z0-9_]{2,40}$');
    expect(prop('ReportContent', 'contentType')['pattern'], r'^[a-z0-9_]{1,40}$');
  });

  test('required fields the models rely on', () {
    List<String> required(String name) => [for (final f in schema(name)['required'] as YamlList) f as String];
    expect(required('CreateReportRequest'), unorderedEquals(['source', 'reasonCategory']));
    expect(required('CreatedReport'), unorderedEquals(['reportId', 'caseId', 'caseCreated']));
    expect(required('SubjectStatus'), unorderedEquals(['externalUserId', 'status']));
    expect(required('WebhookEvent'), unorderedEquals(['id', 'type', 'createdAt', 'app']));
    expect(
        required('WebhookDecision'), unorderedEquals(['id', 'action', 'policies', 'statementOfReasons', 'decidedAt']));
    expect(required('StatementOfReasons'), unorderedEquals(['locale', 'text', 'structured']));
    expect(required('CreateAppealRequest'), unorderedEquals(['decisionId', 'appellant', 'text']));
    expect(required('Appellant'), unorderedEquals(['type', 'externalUserId']));
    expect(required('CreatedAppeal'), unorderedEquals(['appealId', 'status']));
    expect(required('AppealStatusInfo'), unorderedEquals(['id', 'decisionId', 'appellantType', 'status', 'createdAt']));
    expect(
      required('WebhookAppeal'),
      unorderedEquals(['id', 'decisionId', 'appellantType', 'outcome', 'statementText', 'resolvedAt']),
    );
    expect(
      required('WebhookReportsResolved'),
      unorderedEquals(['decisionId', 'action', 'policies', 'decidedAt', 'appealDeadline', 'items']),
    );
    expect(required('CreateReviewRequest'), unorderedEquals(['type', 'content']));
    expect(required('CreatedReview'), unorderedEquals(['reviewId', 'status', 'dueAt']));
    expect(required('CreateSignalsRequest'), unorderedEquals(['signals']));
    expect(required('SignalInput'), unorderedEquals(['type', 'externalUserId']));
    expect(required('CreatedSignals'), unorderedEquals(['accepted']));
    expect(required('DeviceCheckRequest'), unorderedEquals(['externalUserId', 'platform', 'token']));
    expect(
      required('DeviceCheckResult'),
      unorderedEquals(['checkId', 'platform', 'status', 'deviceFlag', 'deviceAction', 'subject', 'test']),
    );
    expect(required('DeviceIntegrity'), unorderedEquals(['device', 'risks', 'testingResponse']));
    expect(required('ReviewStatusInfo'), unorderedEquals(['id', 'type', 'status', 'submittedAt']));
    expect(required('WebhookReview'), unorderedEquals(['id', 'type', 'outcome', 'decidedAt']));
    expect(
      (((prop('WebhookReview', 'content'))['required']) as YamlList).toList(),
      ['externalContentId'],
    );
  });

  group('every field of the models is declared in the spec', () {
    /// The schema [node] points to, following `$ref`.
    YamlMap resolve(Object? node) {
      var n = node! as YamlMap;
      for (var ref = n[r'$ref']; ref is String; ref = n[r'$ref']) {
        n = schema(ref.split('/').last);
      }
      return n;
    }

    /// Expects every key of [json] to be a property of [node], also in nested
    /// objects and lists. Free-form objects such as `context` are not walked.
    void expectDeclared(Object? json, Object? node, String path) {
      final n = resolve(node);
      if (json is Map) {
        final props = n['properties'] as YamlMap?;
        if (props == null) return;
        for (final MapEntry(:key, :value) in json.entries) {
          expect(props.containsKey(key), isTrue, reason: '$path/$key is not in the spec');
          if (props.containsKey(key)) expectDeclared(value, props[key], '$path/$key');
        }
      } else if (json is List && n['items'] != null) {
        for (final (i, e) in json.indexed) {
          expectDeclared(e, n['items'], '$path/$i');
        }
      }
    }

    /// Expects every field the spec requires in [schemaName] to be in [json].
    void expectRequired(Map<String, Object?> json, String schemaName) {
      final required = schema(schemaName)['required'] as YamlList? ?? YamlList();
      for (final field in required) {
        expect(json.containsKey(field), isTrue, reason: '$schemaName.$field is required but not written');
      }
    }

    final at = DateTime.utc(2026, 10, 3, 12);
    const policy = PolicyRef(code: 'spam', title: 'Spam');
    final sor = StatementOfReasons(
      locale: 'en',
      text: 'Decision',
      structured: SorDetails(
        actionName: 'suspend_user',
        endsAt: at,
        territorialScope: 'app',
        facts: 'Facts',
        basedOnNotice: true,
        automatedDetection: false,
        automatedDecision: false,
        noticeSourceName: 'trusted_flagger',
        automationName: 'partial',
        grounds: const [
          SorGround(basis: LegalBasis.law, policyCode: 'hate', title: 'Hate', lawReference: '§ 130 StGB'),
        ],
        redress: 'Redress',
      ),
    );
    final content = ReportedContent(
      externalContentId: 'c',
      contentType: 'comment',
      text: 'text',
      mediaUrls: const ['https://cdn.example.com/a.jpg'],
      externalUrl: 'https://app.example.com/c',
      createdAt: at,
      context: const {'postId': 'p'},
    );
    const author = ReportedUser('u', displayName: 'User');

    // Each model with every optional field set, and with the fields the spec
    // requires only.
    final cases = <String, (Map<String, Object?>, Map<String, Object?>)>{
      'CreateReportRequest': (
        ReportRequest.content(
          reasonCategory: 'spam',
          reasonText: 'why',
          goodFaith: true,
          reporterId: 'r',
          externalReportId: 'x',
          trustedFlaggerId: '01K6T2D0000000000000000000',
          author: author,
          content: content,
        ).toJson(),
        const ReportRequest(source: ReportSource.user, reasonCategory: 'spam').toJson(),
      ),
      'CreatedReport': (
        ReportReceipt(
          reportId: 'r',
          caseId: 'c',
          caseCreated: true,
          reporterWarning: ReporterWarning(issuedAt: at),
        ).toJson(),
        const ReportReceipt(reportId: 'r', caseId: 'c', caseCreated: false).toJson(),
      ),
      'ReporterWarning': (ReporterWarning(issuedAt: at).toJson(), ReporterWarning(issuedAt: at).toJson()),
      'StatementOfReasonsStructured': (
        sor.structured.toJson(),
        const SorDetails(
          actionName: 'dismiss',
          territorialScope: 'app',
          facts: '',
          basedOnNotice: false,
          automatedDetection: false,
          automatedDecision: false,
          grounds: [],
          redress: '',
        ).toJson(),
      ),
      'SubjectStatus': (
        SubjectStatus(externalUserId: 'u', status: SanctionStatus.suspended, suspendedUntil: at).toJson(),
        const SubjectStatus.active('u').toJson(),
      ),
      'CreateAppealRequest': (
        const AppealRequest.subject(decisionId: 'd', externalUserId: 'u', text: 't', externalAppealId: 'x').toJson(),
        const AppealRequest.reporter(decisionId: 'd', externalUserId: 'u', text: 't').toJson(),
      ),
      'CreatedAppeal': (
        const AppealReceipt(appealId: 'a', status: AppealStatus.open).toJson(),
        const AppealReceipt(appealId: 'a', status: AppealStatus.open).toJson(),
      ),
      'AppealStatusInfo': (
        AppealStatusInfo(
          id: 'a',
          externalAppealId: 'x',
          decisionId: 'd',
          appellantType: AppellantType.subject,
          status: AppealStatus.resolved,
          createdAt: at,
          outcome: AppealOutcome.changed,
          statementText: 'answer',
          resolvedAt: at,
          newDecisionId: 'n',
        ).toJson(),
        AppealStatusInfo(
          id: 'a',
          decisionId: 'd',
          appellantType: AppellantType.reporter,
          status: AppealStatus.open,
          createdAt: at,
        ).toJson(),
      ),
      'CreateReviewRequest': (
        ReviewRequest(type: 'photo', externalReviewId: 'x', author: author, content: content).toJson(),
        const ReviewRequest(type: 'photo', content: ReportedContent(externalContentId: 'c', contentType: 'p')).toJson(),
      ),
      'CreatedReview': (
        ReviewReceipt(reviewId: 'r', status: ReviewStatus.pending, dueAt: at).toJson(),
        ReviewReceipt(reviewId: 'r', status: ReviewStatus.pending, dueAt: at).toJson(),
      ),
      'CreateSignalsRequest': (
        SignalsRequest([
          SignalInput(
              type: 'score_jump', externalUserId: 'u', value: 4200, occurredAt: at, context: const {'level': '7'}),
        ]).toJson(),
        const SignalsRequest([]).toJson(),
      ),
      'SignalInput': (
        SignalInput(type: 'score_jump', externalUserId: 'u', value: 1.5, occurredAt: at, context: const {'k': 'v'})
            .toJson(),
        const SignalInput(type: 'score_jump', externalUserId: 'u').toJson(),
      ),
      'CreatedSignals': (const SignalsReceipt(accepted: 1).toJson(), const SignalsReceipt(accepted: 1).toJson()),
      'DeviceCheckRequest': (
        const DeviceCheckRequest(
          externalUserId: 'u',
          platform: DevicePlatform.ios,
          token: 't',
          requestHash: 'h',
          environment: DeviceEnvironment.development,
          event: DeviceCheckEvent.registration,
        ).toJson(),
        const DeviceCheckRequest(externalUserId: 'u', platform: DevicePlatform.test, token: 'test:a').toJson(),
      ),
      'DeviceCheckResult': (
        DeviceCheckResult(
          checkId: 'c',
          platformName: 'android',
          statusName: 'evaluated',
          deviceFlagName: 'suspended',
          flaggedSince: '2026-09',
          deviceActionName: 'marked_suspended',
          integrity: const DeviceIntegrity(
            deviceName: 'strong',
            appRecognized: true,
            licensed: false,
            riskNames: ['overlay_apps'],
            testingResponse: true,
          ),
          subject: SubjectStatus(externalUserId: 'u', status: SanctionStatus.suspended, suspendedUntil: at),
          test: false,
        ).toJson(),
        const DeviceCheckResult(
          checkId: 'c',
          platformName: 'ios',
          statusName: 'unevaluated',
          deviceFlagName: 'unknown',
          deviceActionName: 'none',
          subject: SubjectStatus.active('u'),
          test: false,
        ).toJson(),
      ),
      'DeviceIntegrity': (
        const DeviceIntegrity(deviceName: 'none', appRecognized: false, licensed: true, riskNames: ['high_activity'])
            .toJson(),
        const DeviceIntegrity(deviceName: 'unevaluated').toJson(),
      ),
      'ReviewStatusInfo': (
        ReviewStatusInfo(
          id: 'r',
          externalReviewId: 'x',
          type: 'photo',
          status: ReviewStatus.decided,
          submittedAt: at,
          outcome: ReviewOutcome.rejected,
          decidedAt: at,
          decisionId: 'd',
        ).toJson(),
        ReviewStatusInfo(id: 'r', type: 'photo', status: ReviewStatus.pending, submittedAt: at).toJson(),
      ),
      'WebhookDecision': (
        ModerationDecision(
          id: 'd',
          actionName: 'suspend_user',
          suspendUntil: at,
          externalContentId: 'c',
          externalUserId: 'u',
          policies: const [policy],
          statementOfReasons: sor,
          decidedAt: at,
          appealId: 'a',
          replacesDecisionId: 'o',
          reviewId: 'r',
          restoreScopeName: 'content',
        ).toJson(),
        ModerationDecision(id: 'd', actionName: 'dismiss', policies: const [], statementOfReasons: sor, decidedAt: at)
            .toJson(),
      ),
      'WebhookAppeal': (
        AppealResolution(
          id: 'a',
          externalAppealId: 'x',
          decisionId: 'd',
          appellantType: AppellantType.subject,
          outcome: AppealOutcome.changed,
          statementText: 'answer',
          resolvedAt: at,
          newDecisionId: 'n',
        ).toJson(),
        AppealResolution(
          id: 'a',
          decisionId: 'd',
          appellantType: AppellantType.reporter,
          outcome: AppealOutcome.upheld,
          statementText: 'answer',
          resolvedAt: at,
        ).toJson(),
      ),
      'WebhookReportsResolved': (
        ReportsResolution(
          decisionId: 'd',
          actionName: 'remove_content',
          policies: const [policy],
          decidedAt: at,
          appealDeadline: at,
          reports: const [ResolvedReport(reportId: 'r', externalReportId: 'x')],
        ).toJson(),
        ReportsResolution(
          decisionId: 'd',
          actionName: 'dismiss',
          policies: const [],
          decidedAt: at,
          appealDeadline: at,
          reports: const [],
        ).toJson(),
      ),
      'WebhookReview': (
        ReviewResolution(
          id: 'r',
          externalReviewId: 'x',
          type: 'photo',
          outcome: ReviewOutcome.rejected,
          decidedAt: at,
          decisionId: 'd',
          externalContentId: 'c',
        ).toJson(),
        ReviewResolution(id: 'r', type: 'photo', outcome: ReviewOutcome.approved, decidedAt: at).toJson(),
      ),
      'FieldError': (
        const FieldError('/type', 'unknown', message: 'no such type').toJson(),
        const FieldError('/type', 'unknown').toJson(),
      ),
    };
    for (final MapEntry(key: name, value: (full, minimal)) in cases.entries) {
      test(name, () {
        expectDeclared(full, schema(name), name);
        expectRequired(minimal, name);
      });
    }

    test('the check notices an undeclared or missing field', () {
      expect(() => expectDeclared({'id': 'a', 'nope': 1}, schema('WebhookApp'), 'app'), throwsA(isA<TestFailure>()));
      expect(
        () => expectDeclared({
          'app': {'id': 'a', 'slugs': 'x'},
        }, schema('WebhookEvent'), 'event'),
        throwsA(isA<TestFailure>()),
      );
      expect(() => expectRequired({'id': 'a'}, 'WebhookApp'), throwsA(isA<TestFailure>()));
    });

    test('the events the backend builds (test/fixtures/events)', () {
      final files =
          Directory('test/fixtures/events').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      expect(files, isNotEmpty);
      for (final file in files) {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expectDeclared(json, schema('WebhookEvent'), file.uri.pathSegments.last);
        expectRequired(json, 'WebhookEvent');
      }
    });
  });

  test('idempotency key', () {
    final spec = loadYaml(File('spec/openapi.yaml').readAsStringSync()) as YamlMap;
    for (final (path, limit) in [
      ('/v1/reports', ReportLimits.idempotencyKeyLength),
      ('/v1/appeals', AppealLimits.idempotencyKeyLength),
      ('/v1/reviews', ReviewLimits.idempotencyKeyLength),
      ('/v1/signals', SignalLimits.idempotencyKeyLength),
    ]) {
      final post = ((spec['paths'] as YamlMap)[path] as YamlMap)['post'] as YamlMap;
      final header =
          (post['parameters'] as YamlList).cast<YamlMap>().singleWhere((p) => p['name'] == 'Idempotency-Key');
      expect(header['required'], isTrue);
      expect((header['schema'] as YamlMap)['maxLength'], limit);
    }
    expect(newIdempotencyKey().length, lessThanOrEqualTo(ReportLimits.idempotencyKeyLength));
  });
}
