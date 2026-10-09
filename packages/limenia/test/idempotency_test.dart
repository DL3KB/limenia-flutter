import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

void main() {
  test('keys are ULIDs', () {
    expect(newIdempotencyKey(), matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
  });

  test('keys sort by time', () {
    final earlier = newIdempotencyKey(DateTime.utc(2026, 10, 2, 12));
    final later = newIdempotencyKey(DateTime.utc(2026, 10, 2, 12, 0, 0, 1));
    expect(earlier.substring(0, 10).compareTo(later.substring(0, 10)), lessThan(0));
    // Time part of a known ULID: 2016-07-30T23:54:10.259Z.
    expect(
        newIdempotencyKey(DateTime.fromMillisecondsSinceEpoch(1469922850259, isUtc: true)), startsWith('01ARZ3NDEK'));
  });

  test('keys are unique', () {
    final keys = {for (var i = 0; i < 10000; i++) newIdempotencyKey()};
    expect(keys, hasLength(10000));
  });
}
