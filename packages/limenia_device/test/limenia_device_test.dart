import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limenia_device/limenia_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  /// Answers every call on the channel with [answer]: a value, or something
  /// to throw (e.g. a [PlatformException]).
  void mock(Object? Function(MethodCall call) answer) {
    messenger.setMockMethodCallHandler(LimeniaDevice.channel, (call) async {
      calls.add(call);
      final value = answer(call);
      if (value is Exception) throw value;
      return value;
    });
  }

  setUp(() => calls = []);

  tearDown(() {
    messenger.setMockMethodCallHandler(LimeniaDevice.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('requestToken sends request hash and project number', () async {
      mock((_) => 'integrity-token');
      final token = await LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: 123456789012);
      expect(token, const DeviceToken(platform: 'android', token: 'integrity-token'));
      expect(calls.single.method, 'requestToken');
      expect(calls.single.arguments, {'requestHash': 'hash', 'cloudProjectNumber': 123456789012});
    });

    test('the project number is required', () async {
      mock((_) => 'never');
      for (final number in [null, 0, -1]) {
        await expectLater(
          LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: number),
          throwsA(isA<LimeniaDeviceException>().having((e) => e.code, 'code', LimeniaDeviceException.invalidArgument)),
        );
      }
      expect(calls, isEmpty);
    });

    test('the request hash has 1 to 500 characters', () async {
      mock((_) => 'token');
      for (final hash in ['', 'x' * 501]) {
        await expectLater(
          LimeniaDevice.requestToken(requestHash: hash, cloudProjectNumber: 1),
          throwsA(isA<LimeniaDeviceException>().having((e) => e.code, 'code', LimeniaDeviceException.invalidArgument)),
        );
      }
      expect(calls, isEmpty);
      await LimeniaDevice.requestToken(requestHash: 'x' * 500, cloudProjectNumber: 1);
      expect(calls, hasLength(1));
    });

    test('errors of Play Integrity keep their code', () async {
      for (final (code, expected) in [
        ('unsupported', LimeniaDeviceException.unsupported),
        ('invalid_argument', LimeniaDeviceException.invalidArgument),
        ('failed', LimeniaDeviceException.failed),
        ('something_else', LimeniaDeviceException.failed),
      ]) {
        mock((_) => PlatformException(code: code, message: 'Network error', details: -3));
        await expectLater(
          LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: 1),
          throwsA(isA<LimeniaDeviceException>()
              .having((e) => e.code, 'code', expected)
              .having((e) => e.message, 'message', 'Network error')
              .having((e) => e.nativeCode, 'nativeCode', -3)),
        );
      }
    });

    test('no token is a failure', () async {
      for (final answer in [null, '']) {
        mock((_) => answer);
        await expectLater(
          LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: 1),
          throwsA(isA<LimeniaDeviceException>().having((e) => e.code, 'code', LimeniaDeviceException.failed)),
        );
      }
    });

    test('isSupported asks the platform', () async {
      mock((_) => true);
      expect(await LimeniaDevice.isSupported(), isTrue);
      mock((_) => false);
      expect(await LimeniaDevice.isSupported(), isFalse);
      expect(calls.map((c) => c.method), ['isSupported', 'isSupported']);
    });

    test('without the native plugin', () async {
      expect(await LimeniaDevice.isSupported(), isFalse);
      await expectLater(
        LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: 1),
        throwsA(isA<LimeniaDeviceException>().having((e) => e.code, 'code', LimeniaDeviceException.unsupported)),
      );
    });
  });

  group('iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('requestToken needs no project number and ignores the request hash', () async {
      mock((_) => 'QmFzZTY0');
      final token = await LimeniaDevice.requestToken(requestHash: '');
      expect(token, const DeviceToken(platform: 'ios', token: 'QmFzZTY0'));
      expect(calls.single.arguments, {'requestHash': ''});
      await LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: 1);
      expect(calls.last.arguments, {'requestHash': 'hash'});
    });

    test('a simulator is unsupported', () async {
      mock((call) => call.method == 'isSupported'
          ? false
          : PlatformException(code: 'unsupported', message: 'DeviceCheck is not supported on this device'));
      expect(await LimeniaDevice.isSupported(), isFalse);
      await expectLater(
        LimeniaDevice.requestToken(requestHash: 'hash'),
        throwsA(isA<LimeniaDeviceException>()
            .having((e) => e.code, 'code', LimeniaDeviceException.unsupported)
            .having((e) => e.nativeCode, 'nativeCode', isNull)),
      );
    });
  });

  test('other platforms are unsupported without asking', () async {
    mock((_) => true);
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await LimeniaDevice.isSupported(), isFalse);
      await expectLater(
        LimeniaDevice.requestToken(requestHash: 'hash', cloudProjectNumber: 1),
        throwsA(isA<LimeniaDeviceException>().having((e) => e.code, 'code', LimeniaDeviceException.unsupported)),
      );
    }
    expect(calls, isEmpty);
  });

  test('DeviceToken never shows the token', () {
    const token = DeviceToken(platform: 'ios', token: 'secret');
    expect(token.toString(), isNot(contains('secret')));
    expect(token, const DeviceToken(platform: 'ios', token: 'secret'));
    expect(token.hashCode, const DeviceToken(platform: 'ios', token: 'secret').hashCode);
    expect(token, isNot(const DeviceToken(platform: 'android', token: 'secret')));
  });

  test('LimeniaDeviceException.toString', () {
    expect(const LimeniaDeviceException('failed', 'boom', -3).toString(), 'LimeniaDeviceException(failed: boom)');
    expect(const LimeniaDeviceException('unsupported').toString(), 'LimeniaDeviceException(unsupported)');
  });
}
