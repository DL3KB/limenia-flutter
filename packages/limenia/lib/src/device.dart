import 'dart:convert';
import 'dart:math';

import 'json.dart';
import 'sha256.dart';
import 'status.dart';

// Device checks (`POST /v1/devices/check`, API version 0.20.0): the app gets a token on the device (Play Integrity on
// Android, DeviceCheck on iOS, e.g. with the Flutter plugin `limenia_device`)
// and its backend forwards it to Limenia with the user. Limenia reads the
// bits it keeps per device, marks the device of a banned or suspended user
// and answers with a short assessment.

/// Platform of a device check (`DevicePlatform`).
enum DevicePlatform {
  /// Play Integrity with Device Recall.
  android('android'),

  /// Apple DeviceCheck.
  ios('ios'),

  /// Test tokens `test:<device>` of the test mode of the app, for simulators,
  /// emulators and automated tests.
  test('test');

  const DevicePlatform(this.wireName);

  /// Value in the API.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DevicePlatform? tryParse(String value) {
    for (final platform in values) {
      if (platform.wireName == value) return platform;
    }
    return null;
  }
}

/// DeviceCheck environment of an iOS build (`DeviceCheckRequest.environment`).
enum DeviceEnvironment {
  /// App Store, TestFlight and ad hoc builds. The default.
  production('production'),

  /// Debug builds from Xcode, whose tokens Apple only accepts in its
  /// development environment.
  development('development');

  const DeviceEnvironment(this.wireName);

  /// Value in the API.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceEnvironment? tryParse(String value) {
    for (final environment in values) {
      if (environment.wireName == value) return environment;
    }
    return null;
  }
}

/// What led to a device check (`DeviceCheckEvent`). Limenia stores it with
/// the check and passes it on in the context of the system signals.
enum DeviceCheckEvent {
  registration('registration'),
  login('login'),
  report('report'),

  /// The default.
  other('other');

  const DeviceCheckEvent(this.wireName);

  /// Value in the API.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceCheckEvent? tryParse(String value) {
    for (final event in values) {
      if (event.wireName == value) return event;
    }
    return null;
  }
}

/// Whether Limenia could ask Google or Apple (`DeviceCheckStatus`).
enum DeviceCheckStatus {
  evaluated('evaluated'),

  /// Google or Apple could not be asked, the quota of the project is used up
  /// or the provider answered 429 or 5xx. Limenia fails open: the answer is
  /// 200 with [DeviceFlag.unknown], and the app decides itself.
  unevaluated('unevaluated');

  const DeviceCheckStatus(this.wireName);

  /// Value in the API.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceCheckStatus? tryParse(String value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    return null;
  }
}

/// Marking of a device by Limenia's bits (`DeviceFlag`).
///
/// The bits belong to the developer account (Play developer account, Apple
/// team), so a ban in another app of the same account marks the device too.
/// A marked device is a hint, never proof: devices are sold on.
enum DeviceFlag {
  none('none'),

  /// Banned for a time. How long only Limenia knows.
  suspended('suspended'),

  /// Banned permanently.
  banned('banned'),

  /// The bits could not be read: no Play licence, Device Recall not enabled,
  /// or the check is [DeviceCheckStatus.unevaluated].
  unknown('unknown');

  const DeviceFlag(this.wireName);

  /// Value in the API.
  final String wireName;

  /// Whether the device is marked as banned or suspended.
  bool get isFlagged => this == suspended || this == banned;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceFlag? tryParse(String value) {
    for (final flag in values) {
      if (flag.wireName == value) return flag;
    }
    return null;
  }
}

/// What Limenia wrote to the device during the check (`DeviceAction`).
enum DeviceAction {
  none('none'),

  /// Marked as banned, because the user is banned.
  markedBanned('marked_banned'),

  /// Marked as suspended, because the user is suspended.
  markedSuspended('marked_suspended'),

  /// The marking was removed: the restriction of the user Limenia marked the
  /// device for has ended, or a moderator requested a reset.
  reset('reset');

  const DeviceAction(this.wireName);

  /// Value in the API, e.g. `marked_banned`.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceAction? tryParse(String value) {
    for (final action in values) {
      if (action.wireName == value) return action;
    }
    return null;
  }
}

/// Highest device verdict of Play Integrity (`DeviceIntegrityLevel`).
enum DeviceIntegrityLevel {
  /// `MEETS_STRONG_INTEGRITY`.
  strong('strong'),

  /// `MEETS_DEVICE_INTEGRITY`.
  device('device'),

  /// `MEETS_BASIC_INTEGRITY`.
  basic('basic'),

  /// `MEETS_VIRTUAL_INTEGRITY` (an emulator of Google Play).
  virtual('virtual'),

  /// None of the verdicts: the device has no integrity.
  none('none'),

  /// Google did not evaluate the device.
  unevaluated('unevaluated');

  const DeviceIntegrityLevel(this.wireName);

  /// Value in the API.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceIntegrityLevel? tryParse(String value) {
    for (final level in values) {
      if (level.wireName == value) return level;
    }
    return null;
  }
}

/// A risk of Play Integrity (`DeviceRisk`). Later versions of the API add
/// values, see [DeviceIntegrity.riskNames].
enum DeviceRisk {
  /// Play Protect is off (`POSSIBLE_RISK`).
  playProtectOff('play_protect_off'),

  /// Play Protect reports a medium risk.
  playProtectMediumRisk('play_protect_medium_risk'),

  /// Play Protect reports a high risk.
  playProtectHighRisk('play_protect_high_risk'),

  /// Unknown apps that can capture the screen.
  capturingApps('capturing_apps'),

  /// Unknown apps that can control the device.
  controllingApps('controlling_apps'),

  /// Unknown apps that can show overlays.
  overlayApps('overlay_apps'),

  /// Very many token requests from the device (`LEVEL_4`).
  highActivity('high_activity');

  const DeviceRisk(this.wireName);

  /// Value in the API, e.g. `controlling_apps`.
  final String wireName;

  /// The value for [value], or null for a value this version of the package
  /// does not know yet.
  static DeviceRisk? tryParse(String value) {
    for (final risk in values) {
      if (risk.wireName == value) return risk;
    }
    return null;
  }
}

/// The recommended request hash of a device check:
/// `base64url(SHA-256("limenia:" + externalUserId + ":" + nonce))`, without
/// `=` padding (43 characters), as the spec of the device connector
/// recommends.
///
/// The backend of the app picks [nonce] at random for every check (e.g. with
/// [newDeviceNonce]), computes the hash for the user it authenticated and
/// gives it to the app. The app requests the token with it (the `requestHash`
/// of a Play Integrity standard request) and sends the token back. The
/// backend forwards the token with the same hash in
/// [DeviceCheckRequest.requestHash], and Limenia checks that the token was
/// requested with it. That binds the token to the user and to this one
/// check, so a token of another device cannot be passed off. Play Integrity
/// accepts a request hash of up to 500 characters.
///
/// iOS has no such binding: DeviceCheck ignores the hash, and a token is
/// bound only by being single-use.
String deviceRequestHash(String externalUserId, String nonce) =>
    base64Url.encode(sha256(utf8.encode('limenia:$externalUserId:$nonce'))).replaceAll('=', '');

final _random = Random.secure();

/// A random nonce for [deviceRequestHash]: 32 bytes from a secure random
/// generator in base64url without padding (43 characters). Create it in the
/// backend of the app, use it once and keep it only until the check is done.
String newDeviceNonce() => base64Url.encode([for (var i = 0; i < 32; i++) _random.nextInt(256)]).replaceAll('=', '');

/// A device check in the format of `POST /v1/devices/check`
/// (`DeviceCheckRequest`, API version 0.20.0).
///
/// [toJson] gives exactly the body of the ingest API. The backend of the app
/// should still set the user from its own login (see [withExternalUserId])
/// and the request hash it issued (see [withRequestHash]): the device can
/// send anything.
final class DeviceCheckRequest {
  const DeviceCheckRequest({
    required this.externalUserId,
    required this.platform,
    required this.token,
    this.requestHash,
    this.environment,
    this.event,
  });

  /// Stable ID of the user in the app (1 to 128 characters), never an e-mail
  /// address.
  final String externalUserId;

  final DevicePlatform platform;

  /// At most 8000 characters. Android: the integrity token, unchanged and not
  /// yet decoded (a second decode returns cleared verdicts). iOS: the Base64
  /// token of `DCDevice.generateToken`. Test: `test:<device>` or
  /// `test:<device>:risk`, where `<device>` matches `[a-z0-9-]{1,40}`.
  ///
  /// A token is single-use and secret: never store or log it.
  final String token;

  /// Android: the `requestHash` (standard request) or `nonce` (classic
  /// request) the app requested the token with, at most 500 characters.
  /// Limenia checks it if it is set, see [deviceRequestHash].
  final String? requestHash;

  /// iOS only: the DeviceCheck environment of the build. Default:
  /// [DeviceEnvironment.production]; debug builds need
  /// [DeviceEnvironment.development].
  final DeviceEnvironment? environment;

  /// What led to the check. Default: [DeviceCheckEvent.other].
  final DeviceCheckEvent? event;

  /// Reads the body of `POST /v1/devices/check`, e.g. in the backend of the
  /// app. Throws a [FormatException] for a platform, environment or event this
  /// version does not know.
  factory DeviceCheckRequest.fromJson(JsonMap json) {
    T parse<T extends Object>(String key, T? Function(String) tryParse) {
      final value = readRequired<String>(json, key);
      return tryParse(value) ?? (throw FormatException('Limenia: unknown value of "$key"', value));
    }

    T? parseOptional<T extends Object>(String key, T? Function(String) tryParse) =>
        json[key] == null ? null : parse(key, tryParse);

    return DeviceCheckRequest(
      externalUserId: readRequired<String>(json, 'externalUserId'),
      platform: parse('platform', DevicePlatform.tryParse),
      token: readRequired<String>(json, 'token'),
      requestHash: readOptional<String>(json, 'requestHash'),
      environment: parseOptional('environment', DeviceEnvironment.tryParse),
      event: parseOptional('event', DeviceCheckEvent.tryParse),
    );
  }

  JsonMap toJson() => {
        'externalUserId': externalUserId,
        'platform': platform.wireName,
        'token': token,
        if (requestHash != null) 'requestHash': requestHash,
        if (environment != null) 'environment': environment!.wireName,
        if (event != null) 'event': event!.wireName,
      };

  /// A copy for another user, everything else unchanged.
  DeviceCheckRequest withExternalUserId(String externalUserId) => DeviceCheckRequest(
        externalUserId: externalUserId,
        platform: platform,
        token: token,
        requestHash: requestHash,
        environment: environment,
        event: event,
      );

  /// A copy with another request hash, or without one for null.
  DeviceCheckRequest withRequestHash(String? requestHash) => DeviceCheckRequest(
        externalUserId: externalUserId,
        platform: platform,
        token: token,
        requestHash: requestHash,
        environment: environment,
        event: event,
      );

  /// Never shows the token.
  @override
  String toString() => 'DeviceCheckRequest($externalUserId, ${platform.wireName})';
}

/// Summary of the Play Integrity verdicts (`DeviceIntegrity`, Android only).
final class DeviceIntegrity {
  const DeviceIntegrity({
    required this.deviceName,
    this.appRecognized,
    this.licensed,
    this.riskNames = const [],
    this.testingResponse = false,
  });

  /// Wire value of [device] as Limenia sent it.
  final String deviceName;

  /// The highest device verdict, null for a value this version of the
  /// package does not know yet (see [deviceName]).
  DeviceIntegrityLevel? get device => DeviceIntegrityLevel.tryParse(deviceName);

  /// `PLAY_RECOGNIZED`: the app is the one from Google Play. Null if Google
  /// did not evaluate it.
  final bool? appRecognized;

  /// `LICENSED`: the user got the app from Google Play. Null if Google did not
  /// evaluate it.
  final bool? licensed;

  /// Wire values of [risks], also those this version does not know yet.
  final List<String> riskNames;

  /// The risks this version of the package knows. A new value of a later API
  /// version is only in [riskNames].
  List<DeviceRisk> get risks => [
        for (final name in riskNames)
          if (DeviceRisk.tryParse(name) case final risk?) risk,
      ];

  /// A test response configured in the Play Console, not a real verdict.
  final bool testingResponse;

  factory DeviceIntegrity.fromJson(JsonMap json) => DeviceIntegrity(
        deviceName: readRequired<String>(json, 'device'),
        appRecognized: readOptional<bool>(json, 'appRecognized'),
        licensed: readOptional<bool>(json, 'licensed'),
        riskNames: [
          for (final risk in readRequired<List<Object?>>(json, 'risks'))
            if (risk is String) risk else throw const FormatException('Limenia: "risks" contains a non-string'),
        ],
        testingResponse: readRequired<bool>(json, 'testingResponse'),
      );

  JsonMap toJson() => {
        'device': deviceName,
        if (appRecognized != null) 'appRecognized': appRecognized,
        if (licensed != null) 'licensed': licensed,
        'risks': riskNames,
        'testingResponse': testingResponse,
      };

  @override
  String toString() => 'DeviceIntegrity($deviceName, risks: $riskNames)';
}

/// Answer of `POST /v1/devices/check` (`DeviceCheckResult`).
///
/// For enum values this version of the package does not know yet, the raw
/// value is kept (`…Name`) and the typed getter returns null, except for
/// [deviceFlag], which then is [DeviceFlag.unknown].
final class DeviceCheckResult {
  const DeviceCheckResult({
    required this.checkId,
    required this.platformName,
    required this.statusName,
    required this.deviceFlagName,
    this.flaggedSince,
    required this.deviceActionName,
    this.integrity,
    required this.subject,
    required this.test,
  });

  /// ID of the check in Limenia, also in the user file.
  final String checkId;

  /// Wire value of [platform].
  final String platformName;

  DevicePlatform? get platform => DevicePlatform.tryParse(platformName);

  /// Wire value of [status].
  final String statusName;

  DeviceCheckStatus? get status => DeviceCheckStatus.tryParse(statusName);

  /// Whether Google or Apple were asked. If not, Limenia failed open and the
  /// app decides itself.
  bool get evaluated => status == DeviceCheckStatus.evaluated;

  /// Wire value of [deviceFlag].
  final String deviceFlagName;

  /// The marking of the device; [DeviceFlag.unknown] also for a value this
  /// version of the package does not know yet.
  DeviceFlag get deviceFlag => DeviceFlag.tryParse(deviceFlagName) ?? DeviceFlag.unknown;

  /// Month the device was marked (`YYYY-MM`), if known. The providers keep
  /// the date by the month only, so it is a hint.
  final String? flaggedSince;

  /// Wire value of [deviceAction].
  final String deviceActionName;

  /// What Limenia wrote to the device during this check.
  DeviceAction? get deviceAction => DeviceAction.tryParse(deviceActionName);

  /// The Play Integrity verdicts, Android only.
  final DeviceIntegrity? integrity;

  /// Status of the user, as `GET /v1/subjects/{externalUserId}/status` gives
  /// it.
  final SubjectStatus subject;

  /// A check with a test token of the test mode.
  final bool test;

  factory DeviceCheckResult.fromJson(JsonMap json) {
    final integrity = readOptionalObject(json, 'integrity');
    return DeviceCheckResult(
      checkId: readRequired<String>(json, 'checkId'),
      platformName: readRequired<String>(json, 'platform'),
      statusName: readRequired<String>(json, 'status'),
      deviceFlagName: readRequired<String>(json, 'deviceFlag'),
      flaggedSince: readOptional<String>(json, 'flaggedSince'),
      deviceActionName: readRequired<String>(json, 'deviceAction'),
      integrity: integrity == null ? null : DeviceIntegrity.fromJson(integrity),
      subject: SubjectStatus.fromJson(readObject(json, 'subject')),
      test: readRequired<bool>(json, 'test'),
    );
  }

  JsonMap toJson() => {
        'checkId': checkId,
        'platform': platformName,
        'status': statusName,
        'deviceFlag': deviceFlagName,
        if (flaggedSince != null) 'flaggedSince': flaggedSince,
        'deviceAction': deviceActionName,
        if (integrity != null) 'integrity': integrity!.toJson(),
        'subject': subject.toJson(),
        'test': test,
      };

  @override
  String toString() =>
      'DeviceCheckResult($checkId, $platformName, $statusName, flag: $deviceFlagName, action: $deviceActionName)';
}
