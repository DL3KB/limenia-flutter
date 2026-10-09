import 'dart:convert';

import 'json.dart';

/// Invalid field of a request (`FieldError`).
final class FieldError {
  const FieldError(this.field, this.code, {this.message});

  /// JSON pointer such as `/content/text`, or the header name `Idempotency-Key`.
  final String field;

  /// `required`, `invalid`, `too_long`, `too_many` or `too_large`, and
  /// `unknown` for the field `/type` of a review request whose type does not
  /// exist or is inactive (with the code `review_type_unknown`). For signals
  /// the field is `/signals/{i}/type` (with the code `signal_type_unknown`),
  /// where `{i}` is the position of the signal in the request.
  final String code;
  final String? message;

  factory FieldError.fromJson(JsonMap json) => FieldError(
        readRequired<String>(json, 'field'),
        readRequired<String>(json, 'code'),
        message: readOptional<String>(json, 'message'),
      );

  JsonMap toJson() => {'field': field, 'code': code, if (message != null) 'message': message};

  @override
  bool operator ==(Object other) =>
      other is FieldError && other.field == field && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(field, code, message);

  @override
  String toString() => '$field: $code';
}

/// Error answer of Limenia (problem details, RFC 9457), as passed on by the
/// backend of the app.
///
/// A [LimeniaTransport] throws it for every error answer, best built with
/// [LimeniaException.fromResponse] from status, body and `Retry-After`.
final class LimeniaException implements Exception {
  const LimeniaException(
    this.status, {
    this.code,
    this.title,
    this.detail,
    this.retryAfter,
    this.fieldErrors = const [],
    this.suspendedUntil,
  });

  /// Builds the exception from an HTTP answer. [body] can be the decoded
  /// problem object (any map with string keys, e.g. the `details` of a
  /// `FirebaseFunctionsException`), its JSON text or anything else (then it
  /// is ignored). [retryAfter] is the raw header: seconds or an HTTP date. It
  /// counts only for 429 and 503, as in the TypeScript client.
  factory LimeniaException.fromResponse({
    required int status,
    Object? body,
    String? retryAfter,
    DateTime? now,
  }) {
    final problem = _problem(body);
    String? text(String key) => problem?[key] is String ? problem![key] as String : null;
    final errors = problem?['errors'];
    return LimeniaException(
      status,
      code: text('code'),
      title: text('title'),
      detail: text('detail'),
      retryAfter: _retryAfterStatuses.contains(status) ? parseRetryAfter(retryAfter, now ?? DateTime.now()) : null,
      fieldErrors: [
        if (errors is List)
          for (final e in errors)
            if (_stringKeys(e) case final m? when m['field'] is String && m['code'] is String) FieldError.fromJson(m),
      ],
      // Read as leniently as the rest of the problem: a malformed date is null.
      suspendedUntil: switch (problem?['suspendedUntil']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
    );
  }

  /// The `code` of an answer that refuses a report or a complaint because the
  /// processing of the reporter's notices is suspended (Art. 23 DSA).
  static const reporterSuspendedCode = 'reporter_suspended';

  /// The `code` of an answer to a device check whose token Google or Apple
  /// rejected, or whose package, request hash or age do not fit (400, API
  /// version 0.20.0).
  static const invalidDeviceTokenCode = 'invalid_device_token';

  /// The `code` of an answer to a device check for a platform that is not
  /// active for the app, or of a test token without the test mode (409, API
  /// version 0.20.0).
  static const deviceConnectorNotConfiguredCode = 'device_connector_not_configured';

  /// HTTP status.
  final int status;

  /// Machine-readable code, e.g. `validation_failed`, `rate_limited`,
  /// `tenant_not_active` or `idempotency_key_reused`. For complaints also
  /// `appeal_not_allowed` (403), `appeal_window_closed` and
  /// `appeal_already_open` (409), and `not_found` (404) for an unknown decision.
  /// For review requests also `review_type_unknown` (unknown or inactive type)
  /// and, from API version 0.13.0, the plan of the tenant:
  /// `subscription_required` (402, the subscription has expired) and
  /// `feature_not_in_plan` (403, the plan does not include review requests).
  /// Reports, complaints and status queries are never blocked by the plan.
  /// From API version 0.16.0 reports and complaints of a reporter whose
  /// notices are suspended get `reporter_suspended` (403, see
  /// [isReporterSuspended] and [suspendedUntil]).
  /// From API version 0.18.0 signals get `signal_type_unknown` (400, a type is
  /// unknown or inactive; the position is in [fieldErrors], `/signals/{i}/type`)
  /// and the plan errors `subscription_required` (402) and `feature_not_in_plan`
  /// (403, the plan does not include signals).
  /// From API version 0.20.0 device checks get `invalid_device_token` (400,
  /// see [isInvalidDeviceToken]), `device_connector_not_configured` (409, see
  /// [isDeviceConnectorNotConfigured]) and the plan errors
  /// `subscription_required` (402) and `feature_not_in_plan` (403, the plan
  /// does not include the device connector).
  final String? code;
  final String? title;
  final String? detail;

  /// Wait at least this long before the next attempt (429 and 503).
  final Duration? retryAfter;

  /// The invalid fields (`errors` of the problem): with `validation_failed`,
  /// and with the more specific codes of invalid input that name a field,
  /// e.g. `review_type_unknown` (`/type` with `unknown`) or
  /// `signal_type_unknown` (`/signals/{i}/type`). Empty otherwise.
  final List<FieldError> fieldErrors;

  /// With `reporter_suspended` (API version 0.16.0), the end of the suspension
  /// of the reporter's notices (`Problem.suspendedUntil`). Null otherwise, and
  /// if the backend of the app did not pass the field on.
  final DateTime? suspendedUntil;

  /// Whether the answer is `reporter_suspended`: a moderator suspended the
  /// processing of the reporter's notices (Art. 23 DSA), so Limenia refuses
  /// their reports (`POST /v1/reports`) and their complaints as a reporter
  /// (`POST /v1/appeals`, never those of the affected user) with 403 and stores
  /// nothing. Final until the suspension ends: [LimeniaReporter] drops such a
  /// request instead of keeping it in its queue, see [suspendedUntil].
  bool get isReporterSuspended => code == reporterSuspendedCode;

  /// Whether a device check failed because Google or Apple rejected the
  /// token, or package, request hash or age (at most 15 minutes) do not fit.
  /// Request a fresh token; sending the same one again cannot succeed.
  bool get isInvalidDeviceToken => code == invalidDeviceTokenCode;

  /// Whether a device check failed because the platform is not active for the
  /// app (connector off, incomplete or not verified), or a test token was sent
  /// without the test mode. A setting in the dashboard of Limenia, not an
  /// error of the device.
  bool get isDeviceConnectorNotConfigured => code == deviceConnectorNotConfiguredCode;

  /// Whether the same request may succeed when it is sent again: timeouts
  /// (408), the rate limit (429), server and platform errors (5xx except 501
  /// and 505, also those of a CDN in front of your backend) and a tenant that
  /// is not active yet (403 `tenant_not_active`). All other errors need a
  /// changed request, `reporter_suspended` ([isReporterSuspended]) among them
  /// whatever its status. [LimeniaReporter] also keeps a request after a 401,
  /// see [LimeniaTransport].
  bool get isRetryable =>
      !isReporterSuspended &&
      (status == 408 ||
          status == 429 ||
          (status >= 500 && status <= 599 && status != 501 && status != 505) ||
          code == 'tenant_not_active');

  static const _retryAfterStatuses = {429, 503};

  static JsonMap? _problem(Object? body) {
    var value = body;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    return _stringKeys(value);
  }

  /// [value] as a JSON object if it is a map with string keys. Platform
  /// channels and `dartify` give `Map<Object?, Object?>`.
  static JsonMap? _stringKeys(Object? value) => switch (value) {
        final Map<String, Object?> m => m,
        final Map<Object?, Object?> m when m.keys.every((k) => k is String) => {
            for (final e in m.entries) e.key! as String: e.value,
          },
        _ => null,
      };

  @override
  String toString() {
    final buffer = StringBuffer('LimeniaException($status');
    if (code != null) buffer.write(', $code');
    if (detail != null) buffer.write(': $detail');
    if (fieldErrors.isNotEmpty) buffer.write(' ${fieldErrors.join(', ')}');
    buffer.write(')');
    return buffer.toString();
  }
}

/// The report breaks a limit of Limenia and was not sent.
final class ReportValidationException implements Exception {
  const ReportValidationException(this.errors);

  final List<FieldError> errors;

  @override
  String toString() => 'ReportValidationException(${errors.join(', ')})';
}

/// The complaint breaks a limit of Limenia and was not sent.
final class AppealValidationException implements Exception {
  const AppealValidationException(this.errors);

  final List<FieldError> errors;

  @override
  String toString() => 'AppealValidationException(${errors.join(', ')})';
}

/// The review request breaks a limit of Limenia and was not sent.
final class ReviewValidationException implements Exception {
  const ReviewValidationException(this.errors);

  final List<FieldError> errors;

  @override
  String toString() => 'ReviewValidationException(${errors.join(', ')})';
}

/// The signals break a limit of Limenia and were not sent.
final class SignalsValidationException implements Exception {
  const SignalsValidationException(this.errors);

  final List<FieldError> errors;

  @override
  String toString() => 'SignalsValidationException(${errors.join(', ')})';
}

/// The device check breaks a limit of Limenia and was not sent.
final class DeviceCheckValidationException implements Exception {
  const DeviceCheckValidationException(this.errors);

  final List<FieldError> errors;

  @override
  String toString() => 'DeviceCheckValidationException(${errors.join(', ')})';
}

final _httpDate = RegExp(r'^[A-Z][a-z]{2}, (\d{2}) ([A-Z][a-z]{2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$');
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Parses `Retry-After` (RFC 9110): a delay in seconds or an HTTP date in the
/// preferred format, e.g. `Sun, 06 Nov 1994 08:49:37 GMT`. A date in the past
/// gives zero. Returns null for a missing or malformed value.
Duration? parseRetryAfter(String? value, DateTime now) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return Duration(seconds: int.parse(trimmed));
  final m = _httpDate.firstMatch(trimmed);
  final month = m == null ? -1 : _months.indexOf(m[2]!);
  if (m == null || month < 0) return null;
  final date =
      DateTime.utc(int.parse(m[3]!), month + 1, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  final wait = date.difference(now);
  return wait.isNegative ? Duration.zero : Duration(seconds: (wait.inMilliseconds / 1000).ceil());
}
