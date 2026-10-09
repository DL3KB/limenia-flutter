import 'dart:convert';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 12);

  group('LimeniaException.fromResponse', () {
    test('reads a problem object', () {
      final e = LimeniaException.fromResponse(status: 400, body: {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'detail': 'The request contains invalid fields.',
        'code': 'validation_failed',
        'errors': [
          {'field': '/content/media/0/url', 'code': 'invalid'},
          {'broken': true},
        ],
      });
      expect(e.status, 400);
      expect(e.code, 'validation_failed');
      expect(e.title, 'Bad Request');
      expect(e.detail, 'The request contains invalid fields.');
      expect(e.fieldErrors, [const FieldError('/content/media/0/url', 'invalid')]);
      expect(e.isRetryable, isFalse);
      expect(e.toString(), contains('validation_failed'));
    });

    test('reads field errors with other codes of invalid input', () {
      // API 0.13.2: errors also come with codes that name a field, e.g. review_type_unknown.
      final e = LimeniaException.fromResponse(status: 400, body: {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'code': 'review_type_unknown',
        'errors': [
          {'field': '/type', 'code': 'unknown', 'message': 'no active review type of the app has this code'},
        ],
      });
      expect(e.code, 'review_type_unknown');
      expect(e.fieldErrors, [
        const FieldError('/type', 'unknown', message: 'no active review type of the app has this code'),
      ]);
      expect(e.isRetryable, isFalse);
      expect(LimeniaException.fromResponse(status: 409, body: {'code': 'idempotency_key_reused'}).fieldErrors, isEmpty);
    });

    test('reads signal_type_unknown with the position of the signal', () {
      // API 0.18.0: POST /v1/signals names the signal in the path of the field.
      final e = LimeniaException.fromResponse(status: 400, body: {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'code': 'signal_type_unknown',
        'errors': [
          {'field': '/signals/2/type', 'code': 'unknown', 'message': 'no active signal type of the app has this code'},
        ],
      });
      expect(e.code, 'signal_type_unknown');
      expect(e.fieldErrors.single.field, '/signals/2/type');
      expect(e.fieldErrors.single.message, isNotNull);
      expect(e.isRetryable, isFalse);
    });

    test('the plan errors of signals are not retryable, a tenant that is not active yet is', () {
      expect(LimeniaException.fromResponse(status: 402, body: {'code': 'subscription_required'}).isRetryable, isFalse);
      expect(LimeniaException.fromResponse(status: 403, body: {'code': 'feature_not_in_plan'}).isRetryable, isFalse);
      expect(LimeniaException.fromResponse(status: 409, body: {'code': 'idempotency_key_reused'}).isRetryable, isFalse);
      expect(LimeniaException.fromResponse(status: 403, body: {'code': 'tenant_not_active'}).isRetryable, isTrue);
    });

    test('reads a problem as JSON text and ignores other bodies', () {
      expect(LimeniaException.fromResponse(status: 401, body: '{"code":"unauthenticated"}').code, 'unauthenticated');
      expect(LimeniaException.fromResponse(status: 502, body: '<html>Bad Gateway</html>').code, isNull);
      expect(LimeniaException.fromResponse(status: 503, body: [1, 2]).code, isNull);
      expect(LimeniaException.fromResponse(status: 500).code, isNull);
    });

    test('takes Retry-After for 429 and 503 only', () {
      expect(LimeniaException.fromResponse(status: 429, retryAfter: '7').retryAfter, const Duration(seconds: 7));
      expect(LimeniaException.fromResponse(status: 503, retryAfter: ' 3 ').retryAfter, const Duration(seconds: 3));
      expect(LimeniaException.fromResponse(status: 500, retryAfter: '7').retryAfter, isNull);
      expect(LimeniaException.fromResponse(status: 429, retryAfter: 'soon').retryAfter, isNull);
    });
  });

  group('reporter_suspended (API 0.16.0)', () {
    final problem = {
      'type': 'about:blank',
      'title': 'Forbidden',
      'status': 403,
      'detail': 'The notices of this reporter are suspended.',
      'code': 'reporter_suspended',
      'suspendedUntil': '2026-11-01T10:00:00Z',
    };

    test('carries suspendedUntil', () {
      final e = LimeniaException.fromResponse(status: 403, body: problem);
      expect(e.code, 'reporter_suspended');
      expect(e.isReporterSuspended, isTrue);
      expect(e.suspendedUntil, DateTime.utc(2026, 11, 1, 10));
      expect(e.isRetryable, isFalse);
      expect(e.fieldErrors, isEmpty);
    });

    test('reads it from JSON text and from a Map<Object?, Object?>', () {
      expect(LimeniaException.fromResponse(status: 403, body: jsonEncode(problem)).suspendedUntil,
          DateTime.utc(2026, 11, 1, 10));
      final e = LimeniaException.fromResponse(status: 403, body: <Object?, Object?>{...problem});
      expect(e.isReporterSuspended, isTrue);
      expect(e.suspendedUntil, DateTime.utc(2026, 11, 1, 10));
    });

    test('keeps the offset of a timestamp', () {
      final e = LimeniaException.fromResponse(
        status: 403,
        body: {...problem, 'suspendedUntil': '2026-11-01T12:00:00+02:00'},
      );
      expect(e.suspendedUntil!.isAtSameMomentAs(DateTime.utc(2026, 11, 1, 10)), isTrue);
    });

    test('is still a suspension if the backend did not pass suspendedUntil on', () {
      final e = LimeniaException.fromResponse(status: 403, body: {'code': 'reporter_suspended'});
      expect(e.isReporterSuspended, isTrue);
      expect(e.suspendedUntil, isNull);
    });

    test('ignores a malformed suspendedUntil instead of throwing', () {
      for (final value in [
        'tomorrow',
        5,
        null,
        true,
        ['2026-11-01T10:00:00Z']
      ]) {
        final e = LimeniaException.fromResponse(status: 403, body: {...problem, 'suspendedUntil': value});
        expect(e.suspendedUntil, isNull, reason: '$value');
        expect(e.isReporterSuspended, isTrue, reason: '$value');
      }
    });

    test('is never retryable, whatever the status', () {
      for (final status in [403, 408, 429, 500, 503]) {
        expect(LimeniaException(status, code: 'reporter_suspended').isRetryable, isFalse, reason: '$status');
      }
      expect(LimeniaException.reporterSuspendedCode, 'reporter_suspended');
    });

    test('other errors have no suspension', () {
      final e = LimeniaException.fromResponse(status: 403, body: {'code': 'appeal_not_allowed'});
      expect(e.isReporterSuspended, isFalse);
      expect(e.suspendedUntil, isNull);
      expect(const LimeniaException(403, code: 'tenant_not_active').isReporterSuspended, isFalse);
    });
  });

  test('isRetryable', () {
    for (final status in [408, 429, 500, 502, 503, 504]) {
      expect(LimeniaException(status).isRetryable, isTrue, reason: '$status');
    }
    for (final status in [400, 401, 402, 403, 404, 409, 413, 501, 505]) {
      expect(LimeniaException(status).isRetryable, isFalse, reason: '$status');
    }
    // Server and platform errors, also those of a CDN in front of the backend.
    for (final status in [507, 520, 521, 522, 523, 524, 599]) {
      expect(LimeniaException(status).isRetryable, isTrue, reason: '$status');
    }
    expect(const LimeniaException(403, code: 'tenant_not_active').isRetryable, isTrue);
    // The plan of the tenant (API 0.13.0): final until the tenant changes it.
    expect(const LimeniaException(402, code: 'subscription_required').isRetryable, isFalse);
    expect(const LimeniaException(403, code: 'feature_not_in_plan').isRetryable, isFalse);
  });

  test('reads a problem from a Map<Object?, Object?>, as Firebase callables give it', () {
    final e = LimeniaException.fromResponse(status: 403, body: <Object?, Object?>{
      'code': 'tenant_not_active',
      'detail': 'The tenant is not active.',
      'errors': [
        <Object?, Object?>{'field': '/x', 'code': 'invalid'},
        <Object?, Object?>{1: 'not a field error'},
      ],
    });
    expect(e.code, 'tenant_not_active');
    expect(e.detail, 'The tenant is not active.');
    expect(e.isRetryable, isTrue);
    expect(e.fieldErrors, [const FieldError('/x', 'invalid')]);
    expect(LimeniaException.fromResponse(status: 400, body: <Object?, Object?>{1: 'x'}).code, isNull);
  });

  test('takes Retry-After as an HTTP date', () {
    final e = LimeniaException.fromResponse(status: 429, retryAfter: 'Fri, 02 Oct 2026 12:01:00 GMT', now: now);
    expect(e.retryAfter, const Duration(minutes: 1));
  });

  group('parseRetryAfter', () {
    test('seconds', () => expect(parseRetryAfter('120', now), const Duration(minutes: 2)));
    test('HTTP date', () {
      expect(parseRetryAfter('Fri, 02 Oct 2026 12:00:30 GMT', now), const Duration(seconds: 30));
      expect(parseRetryAfter('Fri, 02 Oct 2026 11:00:00 GMT', now), Duration.zero);
    });
    test('malformed', () {
      expect(parseRetryAfter(null, now), isNull);
      expect(parseRetryAfter('-1', now), isNull);
      expect(parseRetryAfter('1.5', now), isNull);
      expect(parseRetryAfter('Fri, 02 Foo 2026 12:00:30 GMT', now), isNull);
      expect(parseRetryAfter('2026-10-02T12:00:30Z', now), isNull);
    });
  });
}
