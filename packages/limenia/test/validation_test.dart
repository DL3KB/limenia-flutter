import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

ReportRequest content({
  String id = 'c_1',
  String type = 'comment',
  String? text,
  List<String> media = const [],
  String? externalUrl,
  Map<String, Object?>? context,
}) =>
    ReportRequest.content(
      reasonCategory: 'spam',
      author: const ReportedUser('u_1'),
      content: ReportedContent(
        externalContentId: id,
        contentType: type,
        text: text,
        mediaUrls: media,
        externalUrl: externalUrl,
        context: context,
      ),
    );

List<String> fields(ReportRequest r, {String? key}) =>
    [for (final e in validateReport(r, idempotencyKey: key)) '${e.field} ${e.code}'];

void main() {
  test('a complete report is valid', () {
    expect(fields(content(text: 'hi', media: ['https://cdn.example.com/a.jpg']), key: 'k'), isEmpty);
  });

  test('needs a subject or a content', () {
    expect(fields(const ReportRequest(source: ReportSource.user, reasonCategory: 'spam')), ['/subject required']);
  });

  test('checks reason category and idempotency key', () {
    expect(
        fields(const ReportRequest.user(reasonCategory: 'S', subject: ReportedUser('u'))), ['/reasonCategory invalid']);
    expect(fields(content(), key: ''), ['Idempotency-Key invalid']);
    expect(fields(content(), key: 'k' * 200), isEmpty);
    expect(fields(content(), key: 'k' * 201), ['Idempotency-Key invalid']);
  });

  test('counts characters, not bytes or UTF-16 units', () {
    // 😀 is one character but two UTF-16 code units and four bytes.
    expect(fields(content(text: '😀' * 20000)), isEmpty);
    expect(fields(content(text: '😀' * 20001)), ['/content/text too_long']);
    final reason = ReportRequest.user(reasonCategory: 'spam', subject: const ReportedUser('u'), reasonText: 'é' * 2001);
    expect(fields(reason), ['/reasonText too_long']);
  });

  test('checks reporter and subject', () {
    expect(
      fields(const ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u'), reporterId: '')),
      ['/reporter/externalUserId invalid'],
    );
    expect(
      fields(ReportRequest.user(reasonCategory: 'spam', subject: const ReportedUser('u'), reporterId: 'r' * 129)),
      ['/reporter/externalUserId too_long'],
    );
    expect(fields(const ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser(''))), [
      '/subject/externalUserId invalid',
    ]);
    // The display name is trimmed first, as in the backend.
    expect(
      fields(ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u', displayName: '  ${'n' * 100}  '))),
      isEmpty,
    );
    expect(
      fields(ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u', displayName: 'n' * 101))),
      ['/subject/displayName too_long'],
    );
  });

  test('checks the content', () {
    expect(fields(content(id: '')), ['/content/externalContentId invalid']);
    expect(fields(content(id: 'x' * 257)), ['/content/externalContentId invalid']);
    expect(fields(content(type: 'Comment')), ['/content/contentType invalid']);
    expect(fields(content(externalUrl: 'x' * 2049)), ['/content/externalUrl too_long']);
    final eleven = List.generate(11, (i) => 'https://cdn.example.com/$i.jpg');
    expect(fields(content(media: eleven)), ['/content/media too_many']);
    expect(fields(content(media: ['https://cdn.example.com/a.jpg', 'http://cdn.example.com/b.jpg'])), [
      '/content/media/1/url invalid',
    ]);
  });

  test('counts the characters of media URLs, as the backend does from API 0.13.2', () {
    const prefix = 'https://cdn.example.com/'; // 24 characters
    // 2048 characters: 4072 UTF-16 code units and 8120 bytes with 😀, 4072 bytes with ä.
    for (final c in ['a', 'ä', '😀']) {
      expect(fields(content(media: [prefix + c * 2024])), isEmpty, reason: c);
      expect(fields(content(media: [prefix + c * 2025])), ['/content/media/0/url too_long'], reason: c);
    }
    // Too long comes first, as in the backend: the URL is not checked further.
    expect(fields(content(media: ['http://cdn.example.com/${'a' * 2026}'])), ['/content/media/0/url too_long']);
    expect(
      fields(content(media: ['https://cdn.example.com/a.jpg', prefix + 'a' * 2025, 'https://10.0.0.1/a.jpg'])),
      ['/content/media/1/url too_long', '/content/media/2/url invalid'],
    );
  });

  test('measures the context as the backend does', () {
    // {"k":"..."} is 8 bytes plus the value.
    expect(fields(content(context: {'k': 'a' * 4088})), isEmpty);
    expect(fields(content(context: {'k': 'a' * 4089})), ['/content/context too_large']);
    // Go escapes <, > and & with six bytes each.
    expect(fields(content(context: {'k': '<' * 681})), isEmpty);
    expect(fields(content(context: {'k': '<' * 682})), ['/content/context too_large']);
    expect(fields(content(context: {'k': Object()})), ['/content/context too_large']);
  });

  test('checks externalReportId', () {
    ReportRequest withId(String id) =>
        ReportRequest.user(reasonCategory: 'spam', subject: const ReportedUser('u'), externalReportId: id);
    expect(fields(withId('r' * 128)), isEmpty);
    expect(fields(withId('')), ['/externalReportId invalid']);
    expect(fields(withId('r' * 129)), ['/externalReportId invalid']);
  });

  group('trustedFlaggerId (API 0.16.0)', () {
    const flagger = '01K6T2D0000000000000000000';

    ReportRequest report({String? id = flagger, ReportSource source = ReportSource.user}) => ReportRequest.user(
          reasonCategory: 'spam',
          subject: const ReportedUser('u_1'),
          reporterId: 'u_2',
          source: source,
          trustedFlaggerId: id,
        );

    test('a ULID with a report of a user is valid', () {
      expect(fields(report()), isEmpty);
      expect(fields(report(id: null)), isEmpty);
      expect(fields(report(id: '7ZZZZZZZZZZZZZZZZZZZZZZZZZ')), isEmpty);
    });

    test('is only allowed with source user', () {
      expect(fields(report(source: ReportSource.system)), ['/trustedFlaggerId invalid']);
      expect(fields(report(id: null, source: ReportSource.system)), isEmpty);
    });

    test('must be a ULID', () {
      for (final id in [
        '',
        'flagger_1',
        '01K6T2D000000000000000000', // 25 characters
        '01K6T2D00000000000000000000',
        '01k6t2d0000000000000000000',
        '8ZZZZZZZZZZZZZZZZZZZZZZZZZ', // more than 128 bits
        '01K6T2D000000000000000000U', // U is not Crockford base 32
        ' 01K6T2D0000000000000000000',
      ]) {
        expect(fields(report(id: id)), ['/trustedFlaggerId invalid'], reason: '"$id"');
      }
    });

    test('is one error even if both rules are broken, in the order of the schema', () {
      expect(fields(report(id: 'nope', source: ReportSource.system)), ['/trustedFlaggerId invalid']);
      const both = ReportRequest(
        source: ReportSource.user,
        reasonCategory: 'S',
        externalReportId: '',
        trustedFlaggerId: 'nope',
      );
      expect(fields(both),
          ['/reasonCategory invalid', '/externalReportId invalid', '/trustedFlaggerId invalid', '/subject required']);
    });
  });

  group('goodFaith (API 0.22.0)', () {
    ReportRequest report({bool? goodFaith, ReportSource source = ReportSource.user}) => ReportRequest.user(
          reasonCategory: 'spam',
          subject: const ReportedUser('u_1'),
          reporterId: source == ReportSource.user ? 'u_2' : null,
          source: source,
          goodFaith: goodFaith,
        );

    test('any value is valid with a report of a user', () {
      expect(fields(report(goodFaith: true)), isEmpty);
      expect(fields(report(goodFaith: false)), isEmpty);
      expect(fields(report()), isEmpty);
    });

    test('is only allowed with source user, false included', () {
      expect(fields(report(goodFaith: true, source: ReportSource.system)), ['/goodFaith invalid']);
      expect(fields(report(goodFaith: false, source: ReportSource.system)), ['/goodFaith invalid']);
      expect(fields(report(source: ReportSource.system)), isEmpty);
    });

    test('comes after trustedFlaggerId and before subject, as in the backend', () {
      final report = ReportRequest(
        source: ReportSource.system,
        reasonCategory: 'X',
        reasonText: 'r' * (ReportLimits.reasonTextLength + 1),
        goodFaith: true,
        reporterId: '',
        trustedFlaggerId: '01K6T2D0000000000000000000',
      );
      expect(fields(report), [
        '/reasonCategory invalid',
        '/reasonText too_long',
        '/reporter/externalUserId invalid',
        '/trustedFlaggerId invalid',
        '/goodFaith invalid',
        '/subject required',
      ]);
    });
  });

  test('reports several errors in the order of the backend', () {
    const report = ReportRequest(source: ReportSource.user, reasonCategory: 'X', reporterId: '', externalReportId: '');
    expect(fields(report, key: ''), [
      'Idempotency-Key invalid',
      '/reasonCategory invalid',
      '/reporter/externalUserId invalid',
      '/externalReportId invalid',
      '/subject required',
    ]);
  });

  test('trims like Go: U+FEFF is not white space there', () {
    final bom = String.fromCharCode(0xfeff);
    ReportRequest named(String name) =>
        ReportRequest.user(reasonCategory: 'spam', subject: ReportedUser('u', displayName: name));
    expect(fields(named('${'n' * 100}\u3000 ')), isEmpty);
    expect(fields(named('${'n' * 100}$bom')), ['/subject/displayName too_long']);
  });

  test('takes the Idempotency-Key as the HTTP server sees it', () {
    expect(fields(content(), key: ' \t'), ['Idempotency-Key invalid']);
    expect(fields(content(), key: '  ${'k' * 200}\t'), isEmpty);
    expect(fields(content(), key: ' ${'k' * 201} '), ['Idempotency-Key invalid']);
  });

  test('counts whole-number doubles in the context as Go writes them', () {
    // {"k":"...","n":1} is 14 bytes plus the string.
    expect(fields(content(context: {'k': 'a' * 4081, 'n': 1.0})), isEmpty);
    expect(fields(content(context: {'k': 'a' * 4081, 'n': 1.5})), ['/content/context too_large']);
    expect(
      fields(content(context: {
        'k': 'a' * 4066, // exactly 4096 bytes in Go, 4102 with ".0"
        'l': [2.0, 3.0],
        'm': {'n': 4.0},
      })),
      isEmpty,
    );
    expect(fields(content(context: {'n': double.nan})), ['/content/context too_large']);
  });

  group('validateAppeal', () {
    const decisionId = '01K6G5H1TR8W4QZ3M0XCB7NDEC';
    List<String> appealFields(
      String text, {
      String decision = decisionId,
      String user = 'u_1',
      String? externalAppealId,
      String? key,
    }) =>
        [
          for (final e in validateAppeal(
            AppealRequest.subject(
                decisionId: decision, externalUserId: user, text: text, externalAppealId: externalAppealId),
            idempotencyKey: key,
          ))
            '${e.field} ${e.code}',
        ];

    test('a complete complaint is valid', () {
      expect(appealFields('Please check again.', externalAppealId: 'a_1', key: 'k'), isEmpty);
    });

    test('checks decision, user, key and externalAppealId', () {
      expect(appealFields('x', decision: 'dec_1'), ['/decisionId invalid']);
      expect(appealFields('x', decision: decisionId.toLowerCase()), ['/decisionId invalid']);
      // The first character of a ULID is at most 7.
      expect(appealFields('x', decision: '7ZZZZZZZZZZZZZZZZZZZZZZZZZ'), isEmpty);
      expect(appealFields('x', decision: '8${decisionId.substring(1)}'), ['/decisionId invalid']);
      expect(appealFields('x', user: ''), ['/appellant/externalUserId invalid']);
      expect(appealFields('x', user: 'u' * 129), ['/appellant/externalUserId invalid']);
      expect(appealFields('x', key: ''), ['Idempotency-Key invalid']);
      expect(appealFields('x', key: 'k' * 201), ['Idempotency-Key invalid']);
      expect(appealFields('x', externalAppealId: ''), ['/externalAppealId invalid']);
      expect(appealFields('x', externalAppealId: 'a' * 129), ['/externalAppealId invalid']);
    });

    test('needs a text of at most 5000 characters', () {
      expect(appealFields(''), ['/text required']);
      expect(appealFields('  \n '), ['/text required']);
      // Go keeps U+FEFF, so Limenia accepts such a text.
      expect(appealFields(String.fromCharCode(0xfeff)), isEmpty);
      expect(appealFields('😀' * 5000), isEmpty);
      expect(appealFields('😀' * 5001), ['/text too_long']);
    });
  });

  group('validateReview', () {
    List<String> reviewFields(
      ReportedContent content, {
      String type = 'profile_photo',
      ReportedUser? author = const ReportedUser('u_1'),
      String? externalReviewId,
      String? key,
    }) =>
        [
          for (final e in validateReview(
            ReviewRequest(type: type, content: content, author: author, externalReviewId: externalReviewId),
            idempotencyKey: key,
          ))
            '${e.field} ${e.code}',
        ];

    const photo = ReportedContent(
      externalContentId: 'photo_881',
      contentType: 'image',
      mediaUrls: ['https://cdn.example.com/photo_881.jpg'],
    );

    test('a complete request is valid, the author is optional', () {
      expect(reviewFields(photo, externalReviewId: 'upload_881', key: 'k'), isEmpty);
      expect(reviewFields(photo, author: null), isEmpty);
    });

    test('checks the type code', () {
      expect(reviewFields(photo, type: 'ab'), isEmpty);
      expect(reviewFields(photo, type: 'a' * 40), isEmpty);
      for (final type in ['', 'a', 'a' * 41, 'Profile_photo', 'profile-photo', 'profile_photo ']) {
        expect(reviewFields(photo, type: type), ['/type invalid'], reason: type);
      }
    });

    test('checks externalReviewId and the idempotency key', () {
      expect(reviewFields(photo, externalReviewId: '😀' * 128), isEmpty);
      expect(reviewFields(photo, externalReviewId: ''), ['/externalReviewId invalid']);
      expect(reviewFields(photo, externalReviewId: 'r' * 129), ['/externalReviewId invalid']);
      expect(reviewFields(photo, key: ''), ['Idempotency-Key invalid']);
      expect(reviewFields(photo, key: 'k' * 200), isEmpty);
      expect(reviewFields(photo, key: 'k' * 201), ['Idempotency-Key invalid']);
    });

    test('checks author and content with the limits of a report', () {
      expect(reviewFields(photo, author: const ReportedUser('')), ['/subject/externalUserId invalid']);
      expect(
        reviewFields(photo, author: ReportedUser('u', displayName: 'n' * 101)),
        ['/subject/displayName too_long'],
      );
      expect(reviewFields(const ReportedContent(externalContentId: '', contentType: 'image')), [
        '/content/externalContentId invalid',
      ]);
      expect(reviewFields(const ReportedContent(externalContentId: 'p', contentType: 'Image')), [
        '/content/contentType invalid',
      ]);
      expect(reviewFields(ReportedContent(externalContentId: 'p', contentType: 'bio', text: '😀' * 20001)), [
        '/content/text too_long',
      ]);
      expect(
        reviewFields(const ReportedContent(
            externalContentId: 'p', contentType: 'image', mediaUrls: ['https://192.168.1.10/photo.jpg'])),
        ['/content/media/0/url invalid'],
      );
      expect(
        reviewFields(ReportedContent(externalContentId: 'p', contentType: 'image', context: {'k': 'a' * 4089})),
        ['/content/context too_large'],
      );
    });

    test('reports all errors in the order of the request', () {
      expect(
        reviewFields(
          const ReportedContent(externalContentId: '', contentType: 'image'),
          type: 'X',
          author: const ReportedUser(''),
          externalReviewId: '',
          key: '',
        ),
        [
          'Idempotency-Key invalid',
          '/type invalid',
          '/externalReviewId invalid',
          '/subject/externalUserId invalid',
          '/content/externalContentId invalid',
        ],
      );
    });
  });

  group('validateSignals', () {
    List<String> signalFields(List<SignalInput> signals, {String? key}) =>
        [for (final e in validateSignals(SignalsRequest(signals), idempotencyKey: key)) '${e.field} ${e.code}'];

    const score = SignalInput(type: 'score_jump', externalUserId: 'u_1');
    SignalInput withType(String type) => SignalInput(type: type, externalUserId: 'u_1');
    SignalInput withUser(String id) => SignalInput(type: 'score_jump', externalUserId: id);

    test('a complete request is valid', () {
      expect(
        signalFields([
          SignalInput(
            type: 'score_jump',
            externalUserId: 'u_123',
            value: 4200,
            occurredAt: DateTime.utc(2026, 10, 5, 10, 15),
            context: const {'level': '7'},
          ),
          score,
        ], key: 'signals-1'),
        isEmpty,
      );
    });

    test('needs 1 to 100 signals', () {
      expect(signalFields(const []), ['/signals required']);
      expect(signalFields(List.filled(1, score)), isEmpty);
      expect(signalFields(List.filled(100, score)), isEmpty);
      expect(signalFields(List.filled(101, score)), ['/signals too_many']);
      expect(SignalLimits.maxSignals, 100);
    });

    test('checks the type code', () {
      expect(signalFields([withType('ab'), withType('a' * 40), withType('score_2')]), isEmpty);
      for (final type in ['', 'a', 'a' * 41, 'Score_jump', 'score-jump', 'score_jump ', 'score jump', 'schön']) {
        expect(signalFields([score, withType(type)]), ['/signals/1/type invalid'], reason: type);
      }
    });

    test('checks the user and counts characters, not bytes or UTF-16 units', () {
      expect(signalFields([withUser('u'), withUser('😀' * 128)]), isEmpty);
      expect(signalFields([withUser('')]), ['/signals/0/externalUserId invalid']);
      expect(signalFields([score, withUser('😀' * 129)]), ['/signals/1/externalUserId invalid']);
      expect(signalFields([withUser('u' * 128), withUser('u' * 129)]), ['/signals/1/externalUserId invalid']);
    });

    test('accepts any finite number as the value, but not NaN or infinity', () {
      SignalInput valued(num v) => SignalInput(type: 'score_jump', externalUserId: 'u_1', value: v);
      expect(signalFields([valued(0), valued(-3), valued(1.5), valued(1e300), valued(9007199254740992)]), isEmpty);
      expect(signalFields([valued(double.nan)]), ['/signals/0/value invalid']);
      expect(signalFields([score, valued(double.infinity), valued(double.negativeInfinity)]), [
        '/signals/1/value invalid',
        '/signals/2/value invalid',
      ]);
    });

    test('leaves occurredAt to Limenia, whose clock counts', () {
      SignalInput at(DateTime t) => SignalInput(type: 'score_jump', externalUserId: 'u_1', occurredAt: t);
      expect(signalFields([at(DateTime.utc(2000)), at(DateTime.utc(2999))]), isEmpty);
    });

    test('measures the context as the backend does', () {
      SignalInput ctx(Map<String, Object?> c) => SignalInput(type: 'score_jump', externalUserId: 'u_1', context: c);
      // {"k":"..."} has 8 bytes of structure.
      expect(
          signalFields([
            ctx({'k': 'a' * 4088})
          ]),
          isEmpty);
      expect(
          signalFields([
            score,
            ctx({'k': 'a' * 4089})
          ]),
          ['/signals/1/context too_large']);
      expect(signalFields([ctx(const {})]), isEmpty);
      // Go escapes < > & as \u003c, six bytes for one.
      expect(
          signalFields([
            ctx({'k': '<' * 681})
          ]),
          isEmpty);
      expect(
          signalFields([
            ctx({'k': '&' * 682})
          ]),
          ['/signals/0/context too_large']);
      // Whole-number doubles are written without ".0".
      expect(
          signalFields([
            ctx({'k': 'a' * 4081, 'n': 1.0})
          ]),
          isEmpty);
      expect(
          signalFields([
            ctx({'k': 'a' * 4081, 'n': 1.5})
          ]),
          ['/signals/0/context too_large']);
      expect(
          signalFields([
            ctx({'k': Object()})
          ]),
          ['/signals/0/context too_large']);
      expect(
          signalFields([
            ctx({'n': double.nan})
          ]),
          ['/signals/0/context too_large']);
      // The limit counts per signal, not for the request.
      expect(
          signalFields([
            ctx({'k': 'a' * 4088}),
            ctx({'k': 'a' * 4088})
          ]),
          isEmpty);
    });

    test('checks the idempotency key', () {
      expect(signalFields([score], key: ''), ['Idempotency-Key invalid']);
      expect(signalFields([score], key: 'k' * 200), isEmpty);
      expect(signalFields([score], key: 'k' * 201), ['Idempotency-Key invalid']);
      expect(signalFields([score]), isEmpty);
    });

    test('reports every error of every signal, in the order of the schema', () {
      expect(
        signalFields([
          const SignalInput(type: 'X', externalUserId: '', value: double.nan),
          score,
          SignalInput(type: 'y', externalUserId: 'u', context: {'k': 'a' * 5000}),
        ], key: ''),
        [
          'Idempotency-Key invalid',
          '/signals/0/type invalid',
          '/signals/0/externalUserId invalid',
          '/signals/0/value invalid',
          '/signals/2/type invalid',
          '/signals/2/context too_large',
        ],
      );
    });
  });

  group('isAllowedMediaUrl', () {
    String shown(String url) => url.runes.length > 60 ? '${String.fromCharCodes(url.runes.take(60))}…' : url;
    for (final url in [
      'https://cdn.example.com/a.jpg',
      'https://firebasestorage.googleapis.com/v0/b/x/o/a.jpg?alt=media&token=t',
      'https://CDN.Example.COM./a.jpg',
      'https://8.8.8.8/a.jpg',
      'https://[2a00:1450:4001:80b::200e]/a.jpg',
      'https://cdn.example.com/${'😀' * 2024}', // 2048 characters, 8120 bytes
    ]) {
      test('allows ${shown(url)}', () => expect(isAllowedMediaUrl(url), isTrue));
    }
    for (final url in [
      '',
      'http://cdn.example.com/a.jpg',
      'https://user:pw@cdn.example.com/a.jpg',
      'https:///a.jpg',
      'https://localhost/a.jpg',
      'https://intranet/a.jpg',
      'https://printer.local/a.jpg',
      'https://app.localhost/a.jpg',
      'https://metadata.google.internal/a.jpg',
      'https://10.0.0.1/a.jpg',
      'https://172.16.5.4/a.jpg',
      'https://192.168.1.1/a.jpg',
      'https://127.0.0.1/a.jpg',
      'https://169.254.169.254/a.jpg',
      'https://100.64.0.1/a.jpg',
      'https://255.255.255.255/a.jpg',
      'https://[::1]/a.jpg',
      'https://[fd00::1]/a.jpg',
      'https://[fe80::1]/a.jpg',
      'https://[::ffff:10.0.0.1]/a.jpg',
      'https://[64:ff9b::a00:1]/a.jpg',
      'https://[2002:a00:1::]/a.jpg',
      'https://cdn.example.com/${'a' * 2048}',
      'https://cdn.example.com/${'😀' * 2025}', // 2049 characters
    ]) {
      test('rejects ${shown(url)}', () => expect(isAllowedMediaUrl(url), isFalse));
    }
  });
}
