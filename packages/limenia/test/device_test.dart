import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  const request = DeviceCheckRequest(
    externalUserId: 'u_829',
    platform: DevicePlatform.android,
    token: 'eyJhbGciOi...',
    requestHash: '7RUIU7T50Wst-GLUxEONtIXTfNqNFGTw8LWwVKVAkyw',
    event: DeviceCheckEvent.login,
  );

  final resultJson = <String, Object?>{
    'checkId': '01K6CHECK',
    'platform': 'android',
    'status': 'evaluated',
    'deviceFlag': 'banned',
    'flaggedSince': '2026-09',
    'deviceAction': 'none',
    'integrity': {
      'device': 'device',
      'appRecognized': true,
      'licensed': true,
      'risks': ['controlling_apps'],
      'testingResponse': false,
    },
    'subject': {'externalUserId': 'u_829', 'status': 'active'},
    'test': false,
  };

  group('deviceRequestHash', () {
    // Expected values from Python: base64.urlsafe_b64encode(sha256(...)).rstrip('=').
    test('is base64url(SHA-256("limenia:" + externalUserId + ":" + nonce)) without padding', () {
      expect(deviceRequestHash('u_829', 'n0nce'), '7RUIU7T50Wst-GLUxEONtIXTfNqNFGTw8LWwVKVAkyw');
      expect(deviceRequestHash('', ''), 'cZLHCeoqFzSrJmbgI5A1GukXflrkKeEtf8S_Wg1RYPk');
      expect(deviceRequestHash('ü😀', 'x'), 'kJ-jFZtcrQ3t-cOYqcAt4dzIfRDBKZXr3DK4n2AmiPo'); // UTF-8
    });

    test('fits the request hash of a device check and of Play Integrity', () {
      final hash = deviceRequestHash('u', newDeviceNonce());
      expect(hash, hasLength(43));
      expect(hash, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(hash.length, lessThanOrEqualTo(DeviceCheckLimits.requestHashLength));
    });

    test('depends on user and nonce', () {
      expect(deviceRequestHash('u1', 'n'), isNot(deviceRequestHash('u2', 'n')));
      expect(deviceRequestHash('u', 'n1'), isNot(deviceRequestHash('u', 'n2')));
    });

    test('newDeviceNonce is random base64url', () {
      final nonces = {for (var i = 0; i < 100; i++) newDeviceNonce()};
      expect(nonces, hasLength(100));
      for (final nonce in nonces) {
        expect(nonce, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      }
    });
  });

  group('DeviceCheckRequest', () {
    test('toJson and fromJson', () {
      final json = request.toJson();
      expect(json, {
        'externalUserId': 'u_829',
        'platform': 'android',
        'token': 'eyJhbGciOi...',
        'requestHash': '7RUIU7T50Wst-GLUxEONtIXTfNqNFGTw8LWwVKVAkyw',
        'event': 'login',
      });
      expect(DeviceCheckRequest.fromJson(json).toJson(), json);

      const ios = DeviceCheckRequest(
        externalUserId: 'u',
        platform: DevicePlatform.ios,
        token: 'AgAAA...',
        environment: DeviceEnvironment.development,
      );
      expect(
          ios.toJson(), {'externalUserId': 'u', 'platform': 'ios', 'token': 'AgAAA...', 'environment': 'development'});
      expect(DeviceCheckRequest.fromJson(ios.toJson()).toJson(), ios.toJson());
    });

    test('fromJson rejects unknown values and missing fields', () {
      expect(
        () => DeviceCheckRequest.fromJson({'externalUserId': 'u', 'platform': 'windows', 'token': 't'}),
        throwsFormatException,
      );
      expect(
        () => DeviceCheckRequest.fromJson({'externalUserId': 'u', 'platform': 'ios', 'token': 't', 'environment': 'x'}),
        throwsFormatException,
      );
      expect(
        () => DeviceCheckRequest.fromJson({'externalUserId': 'u', 'platform': 'ios', 'token': 't', 'event': 'x'}),
        throwsFormatException,
      );
      expect(() => DeviceCheckRequest.fromJson({'externalUserId': 'u', 'platform': 'ios'}), throwsFormatException);
    });

    test('withExternalUserId and withRequestHash keep everything else', () {
      final copy = request.withExternalUserId('u_1').withRequestHash('h');
      expect(copy.toJson(), {...request.toJson(), 'externalUserId': 'u_1', 'requestHash': 'h'});
      expect(request.withRequestHash(null).toJson().containsKey('requestHash'), isFalse);
    });

    test('toString never shows the token', () {
      expect(request.toString(), isNot(contains(request.token)));
    });
  });

  group('DeviceCheckResult', () {
    test('fromJson and toJson', () {
      final result = DeviceCheckResult.fromJson(resultJson);
      expect(result.checkId, '01K6CHECK');
      expect(result.platform, DevicePlatform.android);
      expect(result.status, DeviceCheckStatus.evaluated);
      expect(result.evaluated, isTrue);
      expect(result.deviceFlag, DeviceFlag.banned);
      expect(result.deviceFlag.isFlagged, isTrue);
      expect(result.flaggedSince, '2026-09');
      expect(result.deviceAction, DeviceAction.none);
      expect(result.integrity!.device, DeviceIntegrityLevel.device);
      expect(result.integrity!.appRecognized, isTrue);
      expect(result.integrity!.licensed, isTrue);
      expect(result.integrity!.risks, [DeviceRisk.controllingApps]);
      expect(result.integrity!.testingResponse, isFalse);
      expect(result.subject, const SubjectStatus.active('u_829'));
      expect(result.test, isFalse);
      expect(result.toJson(), resultJson);
    });

    test('the minimal answer of iOS, unevaluated', () {
      final json = {
        'checkId': 'c',
        'platform': 'ios',
        'status': 'unevaluated',
        'deviceFlag': 'unknown',
        'deviceAction': 'none',
        'subject': {'externalUserId': 'u', 'status': 'banned'},
        'test': false,
      };
      final result = DeviceCheckResult.fromJson(json);
      expect(result.evaluated, isFalse);
      expect(result.deviceFlag, DeviceFlag.unknown);
      expect(result.deviceFlag.isFlagged, isFalse);
      expect(result.integrity, isNull);
      expect(result.flaggedSince, isNull);
      expect(result.subject.status, SanctionStatus.banned);
      expect(result.toJson(), json);
    });

    test('marking and reset', () {
      for (final (wire, action) in [
        ('marked_banned', DeviceAction.markedBanned),
        ('marked_suspended', DeviceAction.markedSuspended),
        ('reset', DeviceAction.reset),
      ]) {
        expect(DeviceCheckResult.fromJson({...resultJson, 'deviceAction': wire}).deviceAction, action);
      }
    });

    test('unknown values of a later API version do not break reading', () {
      final result = DeviceCheckResult.fromJson({
        ...resultJson,
        'platform': 'harmonyos',
        'status': 'partially_evaluated',
        'deviceFlag': 'watched',
        'deviceAction': 'marked_watched',
        'integrity': {
          'device': 'super_strong',
          'risks': ['controlling_apps', 'new_risk'],
          'testingResponse': true,
        },
      });
      expect(result.platform, isNull);
      expect(result.platformName, 'harmonyos');
      expect(result.status, isNull);
      expect(result.evaluated, isFalse);
      expect(result.deviceFlag, DeviceFlag.unknown);
      expect(result.deviceFlagName, 'watched');
      expect(result.deviceAction, isNull);
      expect(result.deviceActionName, 'marked_watched');
      expect(result.integrity!.device, isNull);
      expect(result.integrity!.deviceName, 'super_strong');
      expect(result.integrity!.appRecognized, isNull);
      expect(result.integrity!.risks, [DeviceRisk.controllingApps]);
      expect(result.integrity!.riskNames, ['controlling_apps', 'new_risk']);
      // The raw values are written back.
      expect(DeviceCheckResult.fromJson(result.toJson()).toJson(), result.toJson());
    });

    test('malformed answers throw a FormatException', () {
      expect(() => DeviceCheckResult.fromJson({...resultJson}..remove('checkId')), throwsFormatException);
      expect(() => DeviceCheckResult.fromJson({...resultJson, 'test': 'no'}), throwsFormatException);
      expect(
        () => DeviceCheckResult.fromJson({
          ...resultJson,
          'integrity': {'device': 'device', 'risks': 'none', 'testingResponse': false},
        }),
        throwsFormatException,
      );
      expect(
        () => DeviceCheckResult.fromJson({
          ...resultJson,
          'integrity': {
            'device': 'device',
            'risks': [1],
            'testingResponse': false,
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('validateDeviceCheck', () {
    List<String> fields(DeviceCheckRequest r) => [for (final e in validateDeviceCheck(r)) '${e.field}:${e.code}'];
    DeviceCheckRequest make({
      String externalUserId = 'u',
      DevicePlatform platform = DevicePlatform.android,
      String token = 't',
      String? requestHash,
      DeviceEnvironment? environment,
    }) =>
        DeviceCheckRequest(
          externalUserId: externalUserId,
          platform: platform,
          token: token,
          requestHash: requestHash,
          environment: environment,
        );

    test('a valid request', () {
      expect(validateDeviceCheck(request), isEmpty);
      expect(fields(make(platform: DevicePlatform.ios, environment: DeviceEnvironment.production)), isEmpty);
    });

    test('user ID with 1 to 128 characters', () {
      expect(fields(make(externalUserId: '')), ['/externalUserId:invalid']);
      expect(fields(make(externalUserId: 'x' * 128)), isEmpty);
      expect(fields(make(externalUserId: '😀' * 128)), isEmpty); // characters, not bytes or UTF-16 units
      expect(fields(make(externalUserId: 'x' * 129)), ['/externalUserId:invalid']);
    });

    test('token with 1 to 8000 characters', () {
      expect(fields(make(token: '')), ['/token:invalid']);
      expect(fields(make(token: 'x' * 8000)), isEmpty);
      expect(fields(make(token: 'x' * 8001)), ['/token:invalid']);
    });

    test('request hash with 1 to 500 characters', () {
      expect(fields(make(requestHash: '')), ['/requestHash:invalid']);
      expect(fields(make(requestHash: 'x' * 500)), isEmpty);
      expect(fields(make(requestHash: 'x' * 501)), ['/requestHash:invalid']);
      // Also allowed on iOS, where Limenia ignores it.
      expect(fields(make(platform: DevicePlatform.ios, requestHash: 'h')), isEmpty);
    });

    test('environment only on iOS', () {
      for (final environment in DeviceEnvironment.values) {
        expect(fields(make(platform: DevicePlatform.ios, environment: environment)), isEmpty);
        expect(fields(make(environment: environment)), ['/environment:invalid']);
        expect(
          fields(make(platform: DevicePlatform.test, token: 'test:a', environment: environment)),
          ['/environment:invalid'],
        );
      }
    });

    test('test tokens match test:<device>[:risk]', () {
      for (final (token, valid) in [
        ('test:a', true),
        ('test:geraet-1', true),
        ('test:geraet-1:risk', true),
        ('test:${'a' * 40}', true),
        ('test:${'a' * 41}', false),
        ('test:', false),
        ('test:Geraet', false),
        ('test:geraet_1', false),
        ('test:geraet-1:other', false),
        ('test:geraet-1:risk:risk', false),
        ('geraet-1', false),
        ('test:geraet-1\n', false),
      ]) {
        expect(fields(make(platform: DevicePlatform.test, token: token)), valid ? isEmpty : ['/token:invalid'],
            reason: token);
      }
      // Other platforms do not check the content of the token.
      expect(fields(make(token: 'test:Geraet')), isEmpty);
    });

    test('collects every error', () {
      expect(fields(make(externalUserId: '', token: '', requestHash: '', environment: DeviceEnvironment.development)), [
        '/externalUserId:invalid',
        '/token:invalid',
        '/requestHash:invalid',
        '/environment:invalid',
      ]);
    });
  });

  group('Limenia.checkDevice', () {
    test('validates, then sends through the transport', () async {
      final transport = FakeTransport()..deviceAnswers.add(DeviceCheckResult.fromJson(resultJson));
      final limenia = Limenia(transport: transport);
      final result = await limenia.checkDevice(request);
      expect(result.checkId, '01K6CHECK');
      expect(transport.deviceCalls, [request]);
    });

    test('an invalid request is not sent', () async {
      final transport = FakeTransport();
      await expectLater(
        Limenia(transport: transport).checkDevice(request.withExternalUserId('')),
        throwsA(isA<DeviceCheckValidationException>()
            .having((e) => e.errors, 'errors', [const FieldError('/externalUserId', 'invalid')])),
      );
      expect(transport.deviceCalls, isEmpty);
    });

    test('errors of the transport are thrown once, never retried', () async {
      for (final error in <Object>[
        LimeniaException.fromResponse(
          status: 400,
          body: {'status': 400, 'code': 'invalid_device_token'},
        ),
        LimeniaException.fromResponse(
          status: 409,
          body: {'status': 409, 'code': 'device_connector_not_configured'},
        ),
        const LimeniaException(503),
        const NetworkException(),
      ]) {
        final transport = FakeTransport()..deviceAnswers.add(error);
        await expectLater(Limenia(transport: transport).checkDevice(request), throwsA(same(error)));
        expect(transport.deviceCalls, hasLength(1));
      }
    });

    test('the error codes of the device connector', () {
      final invalid = LimeniaException.fromResponse(status: 400, body: {'code': 'invalid_device_token'});
      expect(invalid.isInvalidDeviceToken, isTrue);
      expect(invalid.isDeviceConnectorNotConfigured, isFalse);
      expect(invalid.isRetryable, isFalse);
      final off = LimeniaException.fromResponse(status: 409, body: {'code': 'device_connector_not_configured'});
      expect(off.isDeviceConnectorNotConfigured, isTrue);
      expect(off.isInvalidDeviceToken, isFalse);
      expect(off.isRetryable, isFalse);
    });
  });
}
