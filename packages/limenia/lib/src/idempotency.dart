import 'dart:math';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final _random = Random.secure();

/// A new idempotency key: a ULID (26 characters, sortable by time).
///
/// Create it once per report and keep it with the report. Every repetition
/// of the same report must send the same key, and no other report may use it.
String newIdempotencyKey([DateTime? now]) {
  final buffer = StringBuffer();
  var time = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final timeChars = List.filled(10, '0');
  for (var i = 9; i >= 0; i--) {
    timeChars[i] = _crockford[time % 32];
    time ~/= 32;
  }
  buffer.writeAll(timeChars);
  for (var i = 0; i < 16; i++) {
    buffer.write(_crockford[_random.nextInt(32)]);
  }
  return buffer.toString();
}
