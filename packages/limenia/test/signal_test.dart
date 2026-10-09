import 'dart:convert';

import 'package:limenia/limenia.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

JsonMap decode(String json) => jsonDecode(json) as JsonMap;

void main() {
  group('SignalsRequest', () {
    test('toJson gives the body of POST /v1/signals', () {
      final request = SignalsRequest([
        SignalInput(
          type: 'score_jump',
          externalUserId: 'u_123',
          value: 4200,
          occurredAt: DateTime.utc(2026, 10, 5, 10, 15),
          context: const {'level': '7'},
        ),
        const SignalInput(type: 'login_burst', externalUserId: 'u_124', value: 0.5),
      ]);
      expect(request.toJson(), {
        'signals': [
          {
            'type': 'score_jump',
            'externalUserId': 'u_123',
            'value': 4200,
            'occurredAt': '2026-10-05T10:15:00.000Z',
            'context': {'level': '7'},
          },
          {'type': 'login_burst', 'externalUserId': 'u_124', 'value': 0.5},
        ],
      });
    });

    test('leaves out empty optional fields and survives a JSON round trip', () {
      const request = SignalsRequest([SignalInput(type: 'logout_spike', externalUserId: 'u_1')]);
      expect(request.toJson(), {
        'signals': [
          {'type': 'logout_spike', 'externalUserId': 'u_1'},
        ],
      });
      final again = SignalsRequest.fromJson(decode(jsonEncode(request.toJson())));
      expect(again.signals.single.value, isNull);
      expect(again.signals.single.occurredAt, isNull);
      expect(again.signals.single.context, isNull);
      expect(again.toJson(), request.toJson());
    });

    test('a full request survives a JSON round trip, a whole number stays a number', () {
      final request = SignalsRequest.fromJson(decode('''
        {"signals":[{"type":"score_jump","externalUserId":"u_123","value":4200,
        "occurredAt":"2026-10-05T10:15:00Z","context":{"level":"7","tags":["a","b"]}},
        {"type":"score_jump","externalUserId":"u_124","value":-1.25}]}'''));
      expect(request.signals.first.value, 4200);
      expect(request.signals.first.occurredAt, DateTime.utc(2026, 10, 5, 10, 15));
      expect(request.signals.first.context, {
        'level': '7',
        'tags': ['a', 'b'],
      });
      expect(request.signals.last.value, -1.25);
      expect(SignalsRequest.fromJson(decode(jsonEncode(request.toJson()))).toJson(), request.toJson());
    });

    test('withExternalUserId sets the user of every signal and nothing else', () {
      final request = SignalsRequest([
        SignalInput(
          type: 'score_jump',
          externalUserId: 'evil',
          value: 7,
          occurredAt: DateTime.utc(2026, 10, 5),
          context: const {'k': 'v'},
        ),
        const SignalInput(type: 'login_burst', externalUserId: 'someone-else'),
      ]);
      final json = request.withExternalUserId('u_2').toJson();
      expect([for (final s in json['signals']! as List<Object?>) (s! as JsonMap)['externalUserId']], ['u_2', 'u_2']);
      final first = (json['signals']! as List<Object?>).first! as JsonMap;
      expect(first['type'], 'score_jump');
      expect(first['value'], 7);
      expect(first['occurredAt'], '2026-10-05T00:00:00.000Z');
      expect(first['context'], {'k': 'v'});
      expect(request.signals.first.externalUserId, 'evil'); // the original stays as it was
    });

    test('fromJson needs signals with a type and a user', () {
      expect(
          () => SignalsRequest.fromJson({
                'signals': ['x']
              }),
          throwsFormatException);
      expect(() => SignalInput.fromJson({'externalUserId': 'u'}), throwsFormatException);
      expect(() => SignalInput.fromJson({'type': 'score_jump'}), throwsFormatException);
      expect(() => SignalInput.fromJson({'type': 'score_jump', 'externalUserId': 'u', 'value': '1'}),
          throwsFormatException);
      expect(
        () => SignalInput.fromJson({'type': 'score_jump', 'externalUserId': 'u', 'occurredAt': 'yesterday'}),
        throwsFormatException,
      );
      expect(() => SignalsRequest.fromJson(const {}), throwsFormatException);
      expect(SignalsRequest.fromJson(const {'signals': []}).signals, isEmpty); // validateSignals reports it
    });
  });

  test('SignalsReceipt reads CreatedSignals', () {
    final receipt = SignalsReceipt.fromJson(decode('{"accepted":3}'));
    expect(receipt, const SignalsReceipt(accepted: 3));
    expect(receipt.hashCode, const SignalsReceipt(accepted: 3).hashCode);
    expect(SignalsReceipt.fromJson(receipt.toJson()), receipt);
    expect(() => SignalsReceipt.fromJson(decode('{}')), throwsFormatException);
    expect(() => SignalsReceipt.fromJson(decode('{"accepted":"3"}')), throwsFormatException);
  });

  test('Limenia.sendSignals sends through the transport', () async {
    final transport = FakeTransport();
    transport.signalsAnswers.add(const SignalsReceipt(accepted: 1));
    final result = await Limenia(transport: transport).sendSignals(
      const SignalsRequest([SignalInput(type: 'score_jump', externalUserId: 'u_1', value: 9000)]),
      idempotencyKey: 'signals-batch-1',
    );
    expect(result, isA<SignalsSent>().having((r) => r.accepted, 'accepted', 1));
    expect(result.idempotencyKey, 'signals-batch-1');
    expect(transport.signalsCalls.single.$2, 'signals-batch-1');
    expect(transport.signalsCalls.single.$1.toJson(), {
      'signals': [
        {'type': 'score_jump', 'externalUserId': 'u_1', 'value': 9000},
      ],
    });
  });

  test('Limenia.sendPendingSignals sends what a restarted app finds in its store', () async {
    final transport = FakeTransport();
    final store = InMemoryPendingSignalsStore();
    final clock = FakeClock(DateTime.utc(2026, 10, 5, 12));
    const request = SignalsRequest([SignalInput(type: 'score_jump', externalUserId: 'u_1')]);
    transport.signalsAnswers.add(const LimeniaException(503, retryAfter: Duration(minutes: 5)));
    final first = Limenia(transport: transport, pendingSignals: store, now: clock.call);
    expect(await first.sendSignals(request, idempotencyKey: 'k'), isA<SignalsQueued>());

    final restarted = Limenia(transport: transport, pendingSignals: store, now: clock.call);
    transport.signalsAnswers.add(const SignalsReceipt(accepted: 1));
    expect((await restarted.sendPendingSignals()).single, isA<SignalsSent>());
    expect(await store.load(), isEmpty);
    expect(transport.signalsCalls.map((c) => c.$2), ['k', 'k']);
  });
}
