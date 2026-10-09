// Helpers to read JSON objects from Limenia with clear errors instead of
// casts that fail with a TypeError.

/// A JSON object as decoded by `jsonDecode`.
typedef JsonMap = Map<String, Object?>;

T readRequired<T extends Object>(JsonMap json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Limenia: field "$key" is missing or not a $T');
}

T? readOptional<T extends Object>(JsonMap json, String key) {
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('Limenia: field "$key" is not a $T');
}

DateTime readDate(JsonMap json, String key) => parseDate(readRequired<String>(json, key), key);

DateTime? readOptionalDate(JsonMap json, String key) {
  final value = readOptional<String>(json, key);
  return value == null ? null : parseDate(value, key);
}

DateTime parseDate(String value, String key) {
  final date = DateTime.tryParse(value);
  if (date == null) throw FormatException('Limenia: field "$key" is not an RFC 3339 timestamp', value);
  return date;
}

JsonMap readObject(JsonMap json, String key) => readRequired<Map<String, Object?>>(json, key);

JsonMap? readOptionalObject(JsonMap json, String key) => readOptional<Map<String, Object?>>(json, key);

List<JsonMap> readObjectList(JsonMap json, String key) {
  final list = readOptional<List<Object?>>(json, key) ?? const [];
  return [
    for (final item in list)
      if (item is Map<String, Object?>) item else throw FormatException('Limenia: "$key" contains a non-object'),
  ];
}

/// Timestamps go out as UTC in RFC 3339, as Limenia expects them.
String formatDate(DateTime date) => date.toUtc().toIso8601String();
