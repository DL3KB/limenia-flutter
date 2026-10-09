/// Device tokens for the device connector of Limenia: Play Integrity on
/// Android, DeviceCheck on iOS.
///
/// The app gets a token here and sends it to its own backend, which forwards
/// it to `POST /v1/devices/check` of Limenia with the API key. The app never
/// talks to Limenia directly. See README.md.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A fresh token of the device, for one device check.
@immutable
final class DeviceToken {
  const DeviceToken({required this.platform, required this.token});

  /// `android` or `ios`, the `platform` of the device check.
  final String platform;

  /// Android: the integrity token of a Play Integrity standard request, to
  /// be sent unchanged. iOS: the DeviceCheck token in Base64.
  ///
  /// Single-use and secret: send it to your backend at once and never store
  /// or log it.
  final String token;

  @override
  bool operator ==(Object other) => other is DeviceToken && other.platform == platform && other.token == token;

  @override
  int get hashCode => Object.hash(platform, token);

  /// Never shows the token.
  @override
  String toString() => 'DeviceToken($platform)';
}

/// The device could not give a token.
final class LimeniaDeviceException implements Exception {
  const LimeniaDeviceException(this.code, [this.message, this.nativeCode]);

  /// The platform cannot give tokens: not Android or iOS, a device without
  /// Google Play (Android) or a simulator (iOS). Use the test tokens of the
  /// test mode (`test:<device>`) there.
  static const unsupported = 'unsupported';

  /// The arguments do not fit: no or an invalid `cloudProjectNumber`, or a
  /// request hash that is empty or longer than 500 characters (Android).
  static const invalidArgument = 'invalid_argument';

  /// Play Integrity or DeviceCheck failed, e.g. without network. See
  /// [nativeCode].
  static const failed = 'failed';

  /// [unsupported], [invalidArgument] or [failed].
  final String code;

  final String? message;

  /// Android: the error code of Play Integrity (`StandardIntegrityErrorCode`),
  /// e.g. -3 `NETWORK_ERROR`, -8 `TOO_MANY_REQUESTS`, -12
  /// `GOOGLE_SERVER_UNAVAILABLE` or -18 `CLIENT_TRANSIENT_ERROR`, which Google
  /// recommends to retry with exponential backoff. iOS: the code of the
  /// `DCError`. Null if the error did not come from the platform.
  final int? nativeCode;

  @override
  String toString() => 'LimeniaDeviceException($code${message == null ? '' : ': $message'})';
}

/// Gets tokens of the device for the device connector of Limenia.
abstract final class LimeniaDevice {
  /// The method channel to the native code, for tests.
  @visibleForTesting
  static const channel = MethodChannel('eu.limenia/limenia_device');

  /// Play Integrity accepts a request hash of at most 500 characters.
  static const maxRequestHashLength = 500;

  /// Whether the device can give tokens: on Android whether the Google Play
  /// Store is installed, on iOS `DCDevice.current.isSupported` (false in the
  /// simulator). False on every other platform.
  ///
  /// A request can still fail, e.g. with outdated Play services.
  static Future<bool> isSupported() async {
    if (_platform == null) return false;
    try {
      return await channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// A fresh token of the device.
  ///
  /// [requestHash] binds the token to the user and to this check (Android).
  /// Get it from your backend, which computes it for a random nonce with
  /// `deviceRequestHash` of the Dart package `limenia` (or the same formula,
  /// `base64url(SHA-256("limenia:" + externalUserId + ":" + nonce))`) and
  /// later forwards it with the token as `requestHash`. iOS ignores it:
  /// DeviceCheck has no such binding, a token is bound only by being
  /// single-use, and your backend takes the user from its login.
  ///
  /// [cloudProjectNumber] is the number of the Google Cloud project linked to
  /// the app in the Play Console (Android, required; ignored on iOS). The
  /// plugin prepares Play Integrity once per project number and keeps it for
  /// the next requests; if Google invalidates it, it prepares again once.
  ///
  /// Throws a [LimeniaDeviceException].
  static Future<DeviceToken> requestToken({required String requestHash, int? cloudProjectNumber}) async {
    final platform = _platform;
    if (platform == null) {
      throw const LimeniaDeviceException(
        LimeniaDeviceException.unsupported,
        'Device tokens are only available on Android and iOS',
      );
    }
    if (platform == 'android') {
      if (cloudProjectNumber == null || cloudProjectNumber <= 0) {
        throw const LimeniaDeviceException(
          LimeniaDeviceException.invalidArgument,
          'cloudProjectNumber is required on Android',
        );
      }
      if (requestHash.isEmpty || requestHash.length > maxRequestHashLength) {
        throw const LimeniaDeviceException(
          LimeniaDeviceException.invalidArgument,
          'requestHash must have 1 to $maxRequestHashLength characters',
        );
      }
    }
    final String? token;
    try {
      token = await channel.invokeMethod<String>('requestToken', {
        'requestHash': requestHash,
        if (platform == 'android') 'cloudProjectNumber': cloudProjectNumber,
      });
    } on PlatformException catch (e) {
      throw LimeniaDeviceException(
        switch (e.code) {
          LimeniaDeviceException.unsupported => LimeniaDeviceException.unsupported,
          LimeniaDeviceException.invalidArgument => LimeniaDeviceException.invalidArgument,
          _ => LimeniaDeviceException.failed,
        },
        e.message,
        e.details is int ? e.details as int : null,
      );
    } on MissingPluginException {
      throw const LimeniaDeviceException(LimeniaDeviceException.unsupported, 'The plugin is not registered');
    }
    if (token == null || token.isEmpty) {
      throw const LimeniaDeviceException(LimeniaDeviceException.failed, 'The platform returned no token');
    }
    return DeviceToken(platform: platform, token: token);
  }

  /// `android` or `ios`, null on every other platform.
  static String? get _platform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }
}
