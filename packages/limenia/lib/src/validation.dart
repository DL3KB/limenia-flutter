import 'dart:convert';

import 'appeal.dart';
import 'categories.dart';
import 'device.dart';
import 'errors.dart';
import 'report.dart';
import 'review.dart';
import 'signal.dart';

/// Limits of a report, as in `api/openapi.yaml` and the ingest validation of
/// the Limenia backend. Lengths count characters (Unicode code points).
abstract final class ReportLimits {
  static const reasonTextLength = 2000;
  static const externalUserIdLength = 128;
  static const externalContentIdLength = 256;
  static const displayNameLength = 100;
  static const textLength = 20000;
  static const mediaCount = 10;

  /// Of a media URL and of the external URL, in characters. Limenia counts
  /// the characters of media URLs from API version 0.13.2; before, it
  /// counted their bytes (UTF-8).
  static const urlLength = 2048;

  /// Size of the serialized context in bytes.
  static const contextBytes = 4096;
  static const idempotencyKeyLength = 200;
  static const externalReportIdLength = 128;
}

/// Limits of a complaint (`CreateAppealRequest`). Lengths count characters
/// (Unicode code points).
abstract final class AppealLimits {
  static const textLength = 5000;
  static const externalUserIdLength = 128;
  static const externalAppealIdLength = 128;
  static const idempotencyKeyLength = 200;
}

/// Limits of a review request (`CreateReviewRequest`). Author and content
/// have the limits of a report ([ReportLimits]). Lengths count characters
/// (Unicode code points).
abstract final class ReviewLimits {
  static const externalReviewIdLength = 128;
  static const idempotencyKeyLength = 200;
}

/// Limits of a signals request (`CreateSignalsRequest`, `SignalInput`). Lengths
/// count characters (Unicode code points).
abstract final class SignalLimits {
  /// Signals per request: 1 to [maxSignals].
  static const maxSignals = 100;
  static const externalUserIdLength = 128;

  /// Size of the serialized context in bytes, as for a report
  /// ([ReportLimits.contextBytes]).
  static const contextBytes = 4096;
  static const idempotencyKeyLength = 200;
}

/// Limits of a device check (`DeviceCheckRequest`, API version 0.20.0).
/// Lengths count characters (Unicode code points).
abstract final class DeviceCheckLimits {
  static const externalUserIdLength = 128;

  /// Of the token of the device.
  static const tokenLength = 8000;

  /// Of the request hash. Play Integrity accepts up to 500 characters too.
  static const requestHashLength = 500;
}

/// Length in characters (Unicode code points), as the backend counts it.
int _chars(String s) => s.runes.length;

/// [s] without leading and trailing white space as Go's `strings.TrimSpace`
/// sees it: Dart's `trim` also removes U+FEFF, Go does not.
String _goTrim(String s) {
  bool space(int c) =>
      (c >= 0x09 && c <= 0x0d) ||
      c == 0x20 ||
      c == 0x85 ||
      c == 0xa0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200a) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202f ||
      c == 0x205f ||
      c == 0x3000;
  var start = 0, end = s.length;
  while (start < end && space(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && space(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

/// Whether [key] is a valid `Idempotency-Key` header. The HTTP server of the
/// backend removes spaces and tabs around a header value first.
bool _validIdempotencyKey(String key, int maxLength) {
  bool blank(int c) => c == 0x20 || c == 0x09;
  var start = 0, end = key.length;
  while (start < end && blank(key.codeUnitAt(start))) {
    start++;
  }
  while (end > start && blank(key.codeUnitAt(end - 1))) {
    end--;
  }
  return end > start && _chars(key.substring(start, end)) <= maxLength;
}

/// A Limenia ID (ULID) as the backend accepts it: 26 characters of Crockford
/// base 32 in capitals, the first one at most `7`.
final _ulidPattern = RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$');

final _reviewTypePattern = RegExp(r'^[a-z0-9_]{2,40}$');

final _signalTypePattern = RegExp(r'^[a-z0-9_]{2,40}$');

final _contentTypePattern = RegExp(r'^[a-z0-9_]{1,40}$');

/// A token of the test mode of the device connector: `test:<device>`,
/// optionally with `:risk` for a device without integrity.
final _testDeviceTokenPattern = RegExp(r'^test:[a-z0-9-]{1,40}(:risk)?$');

/// Checks [report] against the limits of Limenia, in the same order and with
/// the same field codes as the backend. An empty list means valid.
///
/// A `trustedFlaggerId` (API 0.16.0) must be a ULID and needs
/// [ReportSource.user], otherwise `/trustedFlaggerId` is `invalid`.
/// `goodFaith` (API 0.22.0) needs [ReportSource.user] as well: with
/// [ReportSource.system] any value, also `false`, makes `/goodFaith`
/// `invalid`.
///
/// The backend stays authoritative: this check spares a round trip and
/// returns the errors before anything is queued.
List<FieldError> validateReport(ReportRequest report, {String? idempotencyKey}) {
  final errors = <FieldError>[];
  void add(String field, String code) => errors.add(FieldError(field, code));

  if (idempotencyKey != null && !_validIdempotencyKey(idempotencyKey, ReportLimits.idempotencyKeyLength)) {
    add('Idempotency-Key', 'invalid');
  }
  if (!ReasonCategory.isValid(report.reasonCategory)) add('/reasonCategory', 'invalid');
  if (_chars(report.reasonText ?? '') > ReportLimits.reasonTextLength) add('/reasonText', 'too_long');
  final reporterId = report.reporterId;
  if (reporterId != null && reporterId.isEmpty) add('/reporter/externalUserId', 'invalid');
  if (_chars(reporterId ?? '') > ReportLimits.externalUserIdLength) add('/reporter/externalUserId', 'too_long');
  if (report.externalReportId case final id?) {
    if (id.isEmpty || _chars(id) > ReportLimits.externalReportIdLength) add('/externalReportId', 'invalid');
  }
  // API 0.16.0: only for a report of a user, and a ULID. Whether the flagger
  // exists and is active (`unknown`) only Limenia can check.
  if (report.trustedFlaggerId case final id?) {
    if (report.source != ReportSource.user || !_ulidPattern.hasMatch(id)) add('/trustedFlaggerId', 'invalid');
  }
  // API 0.22.0: only a person confirms in good faith, so only for a report of
  // a user. The value does not matter: false is rejected as well.
  if (report.goodFaith != null && report.source != ReportSource.user) add('/goodFaith', 'invalid');
  if (report.subject == null && report.content == null) add('/subject', 'required');

  if (report.subject case final subject?) _checkSubject(subject, add);
  if (report.content case final content?) _checkContent(content, add);
  return errors;
}

/// Checks the review request [review] against the limits of Limenia, with
/// the field codes of the backend. Author and content have the limits of a
/// report. An empty list means valid.
///
/// Whether the review type exists and is active only Limenia can check
/// (`review_type_unknown`).
List<FieldError> validateReview(ReviewRequest review, {String? idempotencyKey}) {
  final errors = <FieldError>[];
  void add(String field, String code) => errors.add(FieldError(field, code));

  if (idempotencyKey != null && !_validIdempotencyKey(idempotencyKey, ReviewLimits.idempotencyKeyLength)) {
    add('Idempotency-Key', 'invalid');
  }
  if (!_reviewTypePattern.hasMatch(review.type)) add('/type', 'invalid');
  if (review.externalReviewId case final id?) {
    if (id.isEmpty || _chars(id) > ReviewLimits.externalReviewIdLength) add('/externalReviewId', 'invalid');
  }
  if (review.author case final author?) _checkSubject(author, add);
  _checkContent(review.content, add);
  return errors;
}

/// Checks the signals [request] against the limits of Limenia, with the field
/// codes the package uses for reports and review requests. An empty list means
/// valid. The fields name the signal by its position, e.g.
/// `/signals/2/externalUserId`.
///
/// Limenia checks the request as a whole, and so does this: one invalid signal
/// makes the request invalid. Only Limenia can check whether a type exists and
/// is active (`signal_type_unknown`) and whether `occurredAt` is at most 5
/// minutes ahead and 24 hours back, because only its clock counts, not the one
/// of the device.
List<FieldError> validateSignals(SignalsRequest request, {String? idempotencyKey}) {
  final errors = <FieldError>[];
  void add(String field, String code) => errors.add(FieldError(field, code));

  if (idempotencyKey != null && !_validIdempotencyKey(idempotencyKey, SignalLimits.idempotencyKeyLength)) {
    add('Idempotency-Key', 'invalid');
  }
  final signals = request.signals;
  if (signals.isEmpty) add('/signals', 'required');
  if (signals.length > SignalLimits.maxSignals) add('/signals', 'too_many');
  for (final (i, signal) in signals.indexed) {
    if (!_signalTypePattern.hasMatch(signal.type)) add('/signals/$i/type', 'invalid');
    if (signal.externalUserId.isEmpty || _chars(signal.externalUserId) > SignalLimits.externalUserIdLength) {
      add('/signals/$i/externalUserId', 'invalid');
    }
    // JSON has no NaN and no infinity: such a value cannot be sent at all.
    if (signal.value case final value? when !value.isFinite) add('/signals/$i/value', 'invalid');
    if (signal.context case final context?) {
      final size = _goJsonSize(context);
      if (size == null || size > SignalLimits.contextBytes) add('/signals/$i/context', 'too_large');
    }
  }
  return errors;
}

/// Checks the device check [request] against the limits of Limenia, with the
/// field codes the package uses for the other requests. An empty list means
/// valid.
///
/// The user ID has 1 to 128 characters (`/externalUserId`), the token 1 to
/// 8000 (`/token`), a request hash 1 to 500 (`/requestHash`). A test token
/// (platform `test`) matches `test:<device>` with `<device>` of
/// `[a-z0-9-]{1,40}` and an optional `:risk` (`/token`). `environment` is for
/// iOS only (`/environment`). All of them have the code `invalid`.
///
/// Only Limenia can check whether the connector of the platform is active
/// (`device_connector_not_configured`) and whether Google or Apple accept the
/// token (`invalid_device_token`).
List<FieldError> validateDeviceCheck(DeviceCheckRequest request) {
  final errors = <FieldError>[];
  void add(String field, String code) => errors.add(FieldError(field, code));

  final userId = request.externalUserId;
  if (userId.isEmpty || _chars(userId) > DeviceCheckLimits.externalUserIdLength) add('/externalUserId', 'invalid');
  final token = request.token;
  if (token.isEmpty || _chars(token) > DeviceCheckLimits.tokenLength) {
    add('/token', 'invalid');
  } else if (request.platform == DevicePlatform.test && !_testDeviceTokenPattern.hasMatch(token)) {
    add('/token', 'invalid');
  }
  if (request.requestHash case final hash?) {
    if (hash.isEmpty || _chars(hash) > DeviceCheckLimits.requestHashLength) add('/requestHash', 'invalid');
  }
  if (request.environment != null && request.platform != DevicePlatform.ios) add('/environment', 'invalid');
  return errors;
}

/// The checks of `subject` (`ReportSubject`), the same in reports and
/// review requests.
void _checkSubject(ReportedUser subject, void Function(String field, String code) add) {
  if (subject.externalUserId.isEmpty || _chars(subject.externalUserId) > ReportLimits.externalUserIdLength) {
    add('/subject/externalUserId', 'invalid');
  }
  if (_chars(_goTrim(subject.displayName ?? '')) > ReportLimits.displayNameLength) {
    add('/subject/displayName', 'too_long');
  }
}

/// The checks of `content` (`ReportContent`), the same in reports and
/// review requests.
void _checkContent(ReportedContent content, void Function(String field, String code) add) {
  if (content.externalContentId.isEmpty || _chars(content.externalContentId) > ReportLimits.externalContentIdLength) {
    add('/content/externalContentId', 'invalid');
  }
  if (!_contentTypePattern.hasMatch(content.contentType)) add('/content/contentType', 'invalid');
  if (_chars(content.text ?? '') > ReportLimits.textLength) add('/content/text', 'too_long');
  if (content.mediaUrls.length > ReportLimits.mediaCount) add('/content/media', 'too_many');
  for (final (i, url) in content.mediaUrls.indexed) {
    if (_chars(url) > ReportLimits.urlLength) {
      add('/content/media/$i/url', 'too_long');
    } else if (!isAllowedMediaUrl(url)) {
      add('/content/media/$i/url', 'invalid');
    }
  }
  if (_chars(content.externalUrl ?? '') > ReportLimits.urlLength) add('/content/externalUrl', 'too_long');
  if (content.context case final context?) {
    final size = _goJsonSize(context);
    if (size == null || size > ReportLimits.contextBytes) add('/content/context', 'too_large');
  }
}

/// Checks [appeal] against the limits of Limenia, like [validateReport]. An
/// empty list means valid.
///
/// Whether the complaint is allowed (who may complain, the six-month window,
/// one open complaint per decision and person) only Limenia can check.
List<FieldError> validateAppeal(AppealRequest appeal, {String? idempotencyKey}) {
  final errors = <FieldError>[];
  void add(String field, String code) => errors.add(FieldError(field, code));

  if (idempotencyKey != null && !_validIdempotencyKey(idempotencyKey, AppealLimits.idempotencyKeyLength)) {
    add('Idempotency-Key', 'invalid');
  }
  if (!_ulidPattern.hasMatch(appeal.decisionId)) add('/decisionId', 'invalid');
  final userId = appeal.externalUserId;
  if (userId.isEmpty || _chars(userId) > AppealLimits.externalUserIdLength) add('/appellant/externalUserId', 'invalid');
  if (_goTrim(appeal.text).isEmpty) {
    add('/text', 'required');
  } else if (_chars(appeal.text) > AppealLimits.textLength) {
    add('/text', 'too_long');
  }
  if (appeal.externalAppealId case final id?) {
    if (id.isEmpty || _chars(id) > AppealLimits.externalAppealIdLength) add('/externalAppealId', 'invalid');
  }
  return errors;
}

/// Size of [value] as Go's encoding/json writes it, which the backend uses
/// for the limit: it escapes `<`, `>` and `&` as `\u003c` (6 bytes instead of
/// 1) and U+2028 and U+2029 (6 bytes instead of 3), and it writes a whole
/// number that it decoded as a double without `.0`. Null if [value] cannot
/// be encoded as JSON.
int? _goJsonSize(Object value) {
  final String encoded;
  try {
    encoded = jsonEncode(_wholeDoublesAsInts(value));
  } on JsonUnsupportedObjectError {
    return null;
  }
  var size = utf8.encode(encoded).length;
  for (final rune in encoded.runes) {
    if (rune == 0x3c || rune == 0x3e || rune == 0x26) size += 5;
    if (rune == 0x2028 || rune == 0x2029) size += 3;
  }
  return size;
}

/// [value] with every whole-number double below 1e21 as an int, the way Go
/// writes the float64 it decodes such a number into (`1.0` becomes `1`).
Object? _wholeDoublesAsInts(Object? value) => switch (value) {
      final double d when d.isFinite && d == d.truncateToDouble() && d.abs() < 1e21 => d.toInt(),
      final Map<Object?, Object?> m => {for (final e in m.entries) e.key: _wholeDoublesAsInts(e.value)},
      final List<Object?> l => [for (final e in l) _wholeDoublesAsInts(e)],
      _ => value,
    };

/// Whether Limenia accepts [raw] as a media URL: at most 2048 characters
/// (Unicode code points, [ReportLimits.urlLength]), and what
/// the URL check of the backend accepts: https without user info, a public IP address
/// or a host name with a dot that is not `localhost`, `*.local` or
/// `*.internal`. In a report or review request a longer URL gets the field
/// code `too_long`, any other rejected one `invalid`. Limenia also checks the
/// address it actually connects to, so a URL can still fail there.
bool isAllowedMediaUrl(String raw) {
  // The backend also caps a URL at 8192 bytes, which no URL of 2048 characters
  // exceeds: UTF-8 takes at most 4 bytes per character.
  if (raw.isEmpty || _chars(raw) > ReportLimits.urlLength) return false;
  if (!_goParses(raw)) return false;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
  var host = uri.host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.isEmpty) return false;
  final ip = _parseIp(host);
  if (ip != null) return _isPublic(ip);
  return host.contains('.') &&
      host != 'localhost' &&
      !host.endsWith('.localhost') &&
      !host.endsWith('.local') &&
      !host.endsWith('.internal');
}

/// Whether Go's `url.Parse` accepts the https URL [raw] with a host and
/// without user info, which the backend requires. It rejects control characters
/// before the fragment, user info (also an empty one), characters a host may
/// not contain, `%` escapes of ASCII bytes in the host, a port that is not a
/// number, and `%` without two hex digits in path or fragment. The query is
/// not checked, as in Go.
bool _goParses(String raw) {
  final hash = raw.indexOf('#');
  final url = hash < 0 ? raw : raw.substring(0, hash);
  if (url.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return false;
  if (hash >= 0 && !_validEscapes(raw.substring(hash + 1))) return false;
  if (!url.toLowerCase().startsWith('https://')) return false;
  var rest = url.substring('https:'.length);
  final query = rest.indexOf('?');
  if (query >= 0) rest = rest.substring(0, query);
  var authority = rest.substring(2);
  var path = '';
  final slash = authority.indexOf('/');
  if (slash >= 0) {
    path = authority.substring(slash);
    authority = authority.substring(0, slash);
  }
  return !authority.contains('@') && _validHost(authority) && _validEscapes(path);
}

/// Whether every `%` in [s] starts an escape with two hex digits.
bool _validEscapes(String s) {
  for (var i = s.indexOf('%'); i >= 0; i = s.indexOf('%', i + 1)) {
    if (i + 2 >= s.length || !_isHex(s.codeUnitAt(i + 1)) || !_isHex(s.codeUnitAt(i + 2))) return false;
  }
  return true;
}

bool _isHex(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

bool _isAlnum(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

/// ASCII characters other than letters and digits that Go allows in a host,
/// including the port and the brackets of an IPv6 address.
const _hostMarks = '-._~!\$&\'()*+,;=:[]<>"';

/// Whether Go's `parseHost` accepts [host], which may end with a port.
bool _validHost(String host) {
  bool validPort(String colonPort) => colonPort.isEmpty || RegExp(r'^:[0-9]*$').hasMatch(colonPort);
  if (host.startsWith('[')) {
    final end = host.lastIndexOf(']');
    if (end < 0 || !validPort(host.substring(end + 1))) return false;
  } else {
    final colon = host.lastIndexOf(':');
    if (colon >= 0 && !validPort(host.substring(colon))) return false;
  }
  for (var i = 0; i < host.length; i++) {
    final c = host.codeUnitAt(i);
    if (c == 0x25) {
      // Only non-ASCII bytes may be escaped in a host, and %25 in a zone.
      if (i + 2 >= host.length || !_isHex(host.codeUnitAt(i + 1)) || !_isHex(host.codeUnitAt(i + 2))) return false;
      if (int.parse(host[i + 1], radix: 16) < 8 && host.substring(i, i + 3) != '%25') return false;
      i += 2;
    } else if (c < 0x80 && !_isAlnum(c) && !_hostMarks.contains(String.fromCharCode(c))) {
      return false;
    }
  }
  return true;
}

/// The address as 16 bytes (IPv4 mapped into IPv6), or null for a host name.
List<int>? _parseIp(String host) {
  if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
    try {
      return [..._v4Mapped, ...Uri.parseIPv4Address(host)];
    } on FormatException {
      return null;
    }
  }
  if (host.contains(':')) {
    if (host.contains('%')) return const []; // zone IDs are never public
    try {
      return Uri.parseIPv6Address(host);
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// Prefix of IPv4-mapped IPv6 addresses (`::ffff:0:0/96`).
const _v4Mapped = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff];

/// Special-purpose ranges the backend rejects, IPv4 ones as IPv4-mapped IPv6.
final _nonPublic = <(List<int>, int)>[
  for (final (v4, bits) in const [
    ([0, 0, 0, 0], 8),
    ([10, 0, 0, 0], 8),
    ([100, 64, 0, 0], 10),
    ([127, 0, 0, 0], 8),
    ([169, 254, 0, 0], 16),
    ([172, 16, 0, 0], 12),
    ([192, 0, 0, 0], 24),
    ([192, 0, 2, 0], 24),
    ([192, 168, 0, 0], 16),
    ([198, 18, 0, 0], 15),
    ([198, 51, 100, 0], 24),
    ([203, 0, 113, 0], 24),
    ([224, 0, 0, 0], 4),
    ([240, 0, 0, 0], 4),
  ])
    ([..._v4Mapped, ...v4], 96 + bits),
  for (final (v6, bits) in const [
    ('::', 128),
    ('::1', 128),
    ('::', 96),
    ('64:ff9b::', 96),
    ('64:ff9b:1::', 48),
    ('100::', 64),
    ('2001::', 32),
    ('2001:db8::', 32),
    ('2002::', 16),
    ('fc00::', 7),
    ('fe80::', 10),
    ('ff00::', 8),
  ])
    (Uri.parseIPv6Address(v6), bits),
];

bool _isPublic(List<int> ip) {
  if (ip.length != 16) return false;
  for (final (prefix, bits) in _nonPublic) {
    if (_inPrefix(ip, prefix, bits)) return false;
  }
  // Go's IsGlobalUnicast on the unmapped address: the IPv4 broadcast address
  // is not, all other cases are in the ranges above.
  return !(_inPrefix(ip, [..._v4Mapped, 0, 0, 0, 0], 96) && ip.skip(12).every((b) => b == 0xff));
}

bool _inPrefix(List<int> ip, List<int> prefix, int bits) {
  for (var i = 0; i < 16 && bits > 0; i++, bits -= 8) {
    final mask = bits >= 8 ? 0xff : (0xff << (8 - bits)) & 0xff;
    if ((ip[i] & mask) != (prefix[i] & mask)) return false;
  }
  return true;
}
