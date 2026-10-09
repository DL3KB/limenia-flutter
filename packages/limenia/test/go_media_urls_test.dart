// Pins the check of media URLs to the Limenia backend. From API version
// 0.13.2 the ingest API rejects a media URL with more than 2048 characters
// (Unicode code points) as `too_long`, and then one that the URL check of the
// backend rejects as `invalid`; that check itself only caps a URL at 8192
// bytes. Its verdicts in test/fixtures/media_urls.json were generated from
// the code of the backend. The check in the package may
// be more lenient than the backend, never stricter, or it would block reports
// Limenia accepts; for these URLs it matches exactly.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

/// The errors of [validateReport] for a report with the media URL [url].
List<String> mediaErrors(String url) => [
      for (final e in validateReport(ReportRequest.content(
        reasonCategory: 'spam',
        author: const ReportedUser('u'),
        content: ReportedContent(externalContentId: 'c', contentType: 'image', mediaUrls: [url]),
      )))
        '${e.field} ${e.code}',
    ];

void main() {
  final entries = [
    for (final e in jsonDecode(File('test/fixtures/media_urls.json').readAsStringSync()) as List<Object?>)
      e! as Map<String, Object?>,
  ];
  int chars(Map<String, Object?> e) => (e['url']! as String).runes.length;

  test('the fixture has Go verdicts', () {
    expect(entries.length, greaterThan(100));
    expect(entries.where((e) => e['allowed'] is! bool), isEmpty, reason: 'regenerate the fixture from the backend');
    expect(entries.where((e) => e['allowed'] == true), isNotEmpty);
    expect(entries.where((e) => e['allowed'] == false), isNotEmpty);
    // The backend's URL check accepts URLs longer than the API allows, up to 8192 bytes.
    expect(entries.where((e) => e['allowed'] == true && chars(e) > ReportLimits.urlLength), isNotEmpty);
    // A URL of 2048 characters, but more UTF-16 code units and bytes, that
    // the backend's URL check accepts.
    expect(
      entries.where((e) {
        final url = e['url']! as String;
        return e['allowed'] == true &&
            chars(e) == ReportLimits.urlLength &&
            url.length > ReportLimits.urlLength &&
            utf8.encode(url).length > ReportLimits.urlLength;
      }),
      isNotEmpty,
    );
  });

  for (final e in entries) {
    final url = e['url']! as String;
    final length = url.runes.length;
    final code = length > ReportLimits.urlLength
        ? 'too_long'
        : e['allowed'] == true
            ? null
            : 'invalid';
    final shown = jsonEncode(length > 70 ? '${String.fromCharCodes(url.runes.take(60))}… ($length characters)' : url);
    test('$shown is ${code ?? 'accepted'} as in Go', () {
      expect(isAllowedMediaUrl(url), code == null);
      expect(mediaErrors(url), [if (code != null) '/content/media/0/url $code']);
    });
  }
}
