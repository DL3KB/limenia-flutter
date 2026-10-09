import 'json.dart';

/// An observation of the app about a user, in the format of one entry of
/// `POST /v1/signals` (`SignalInput`, API version 0.18.0), e.g. a jump in the score or an unusual burst of activity.
///
/// A signal is no report and opens no case. The rules the tenant configured
/// for the app turn signals into a case, a higher priority or a flag on the
/// user file; Limenia evaluates them in the background after the answer, and
/// the answer tells nothing about rules.
///
/// Data minimisation: [context] holds IDs and technical details only, never
/// content or personal data of third parties. Send only what the backend of
/// the app computed or checked itself: a value the device reports is as
/// trustworthy as the device.
final class SignalInput {
  const SignalInput({
    required this.type,
    required this.externalUserId,
    this.value,
    this.occurredAt,
    this.context,
  });

  /// Code of an active signal type the tenant configured for the app in the
  /// dashboard, e.g. `score_jump` (pattern `^[a-z0-9_]{2,40}$`). Limenia
  /// rejects an unknown or inactive type with `signal_type_unknown`.
  final String type;

  /// Stable ID of the user in the app (1 to 128 characters), never an e-mail
  /// address. The backend of the app should set it from its own login, see
  /// [SignalsRequest.withExternalUserId].
  final String externalUserId;

  /// A number the signal is about, e.g. a score. What it means is written at
  /// the signal type (`valueLabel`). Must be finite.
  final num? value;

  /// When it happened. Default: when Limenia receives the request. Limenia
  /// accepts at most 5 minutes ahead and at most 24 hours back and rejects the
  /// whole request otherwise (`/signals/{i}/occurredAt` with `invalid`). The
  /// package does not check this, because only the clock of Limenia counts,
  /// not the one of the device.
  final DateTime? occurredAt;

  /// Small JSON object, serialized at most 4 KB, with IDs and technical
  /// details only.
  final Map<String, Object?>? context;

  factory SignalInput.fromJson(JsonMap json) => SignalInput(
        type: readRequired<String>(json, 'type'),
        externalUserId: readRequired<String>(json, 'externalUserId'),
        value: readOptional<num>(json, 'value'),
        occurredAt: readOptionalDate(json, 'occurredAt'),
        context: readOptionalObject(json, 'context'),
      );

  JsonMap toJson() => {
        'type': type,
        'externalUserId': externalUserId,
        if (value != null) 'value': value,
        if (occurredAt != null) 'occurredAt': formatDate(occurredAt!),
        if (context != null) 'context': context,
      };

  /// A copy for another user, everything else unchanged.
  SignalInput withExternalUserId(String externalUserId) =>
      SignalInput(type: type, externalUserId: externalUserId, value: value, occurredAt: occurredAt, context: context);
}

/// Up to 100 signals in the format of `POST /v1/signals`
/// (`CreateSignalsRequest`).
///
/// Limenia checks the request as a whole: one invalid signal rejects it, and
/// nothing is stored. A request counts once against the rate limit whatever
/// the number of signals, so collect signals for a short time and send them
/// together instead of one by one.
///
/// [toJson] gives exactly the body of the ingest API. The backend of the app
/// should still set the user from its own login (see [withExternalUserId]):
/// the device can send anything.
final class SignalsRequest {
  const SignalsRequest(this.signals);

  /// 1 to 100 signals.
  final List<SignalInput> signals;

  factory SignalsRequest.fromJson(JsonMap json) => SignalsRequest([
        for (final s in readRequired<List<Object?>>(json, 'signals'))
          if (s is Map<String, Object?>)
            SignalInput.fromJson(s)
          else
            throw const FormatException('Limenia: "signals" contains a non-object'),
      ]);

  JsonMap toJson() => {
        'signals': [for (final s in signals) s.toJson()],
      };

  /// A copy in which every signal belongs to [externalUserId], e.g. the user a
  /// backend has authenticated, whatever the device sent.
  SignalsRequest withExternalUserId(String externalUserId) =>
      SignalsRequest([for (final s in signals) s.withExternalUserId(externalUserId)]);
}

/// Answer of `POST /v1/signals` (`CreatedSignals`).
final class SignalsReceipt {
  const SignalsReceipt({required this.accepted});

  /// Number of signals Limenia stored. Limenia evaluates the rules after the
  /// answer, so this says nothing about a case or a flag.
  final int accepted;

  factory SignalsReceipt.fromJson(JsonMap json) => SignalsReceipt(accepted: readRequired<int>(json, 'accepted'));

  JsonMap toJson() => {'accepted': accepted};

  @override
  bool operator ==(Object other) => other is SignalsReceipt && other.accepted == accepted;

  @override
  int get hashCode => accepted.hashCode;

  @override
  String toString() => 'SignalsReceipt(accepted: $accepted)';
}
