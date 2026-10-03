/// The one place secrets are removed before an error is kept (migration
/// 0087).
library;

/// Removes passwords, tokens, the `Authorization` header, API keys, install
/// ids and emails from what an error report carries, before anything is
/// stored. `RecordError` runs every field through it, so no caller can
/// skip it.
abstract final class ErrorRedaction {
  /// What a removed value is replaced with.
  static const String mask = '[redacted]';

  /// What a removed email is replaced with.
  static const String emailMask = '[email]';

  /// The longest string kept inside a JSON value.
  static const int maxJsonString = 500;

  /// The most items kept from one JSON list or object.
  static const int maxJsonItems = 50;

  /// The deepest JSON nesting kept.
  static const int maxJsonDepth = 6;

  // A key whose value is always a secret, wherever it appears.
  static final RegExp _secretKey = RegExp(
    'pass(word|wd)?|pwd|secret|token|authori[sz]ation|api[_-]?key|'
    'cookie|install(ation)?[_-]?id|device[_-]?id|otp|credential|'
    'session|signature|e-?mail',
    caseSensitive: false,
  );

  static final RegExp _bearer = RegExp(
    r'\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );

  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*',
  );

  static final RegExp _urlCredentials = RegExp(
    r'\b([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@',
    caseSensitive: false,
  );

  // `password=x`, `"token": "x"`, `api_key: x` inside free text.
  static final RegExp _keyValue = RegExp(
    r'''(["']?[A-Za-z0-9_-]*(?:pass(?:word|wd)?|pwd|secret|token|authori[sz]ation|api[_-]?key|apikey|cookie|install(?:ation)?[_-]?id|device[_-]?id|otp|credential|signature)[A-Za-z0-9_-]*["']?\s*[:=]\s*["']?)([^"'\s,&;}\]]+)''',
    caseSensitive: false,
  );

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  );

  // A long run of key-like characters with both a letter and a digit:
  // FCM tokens, API keys, refresh tokens, raw ids.
  static final RegExp _tokenLike = RegExp(r'[A-Za-z0-9_+=-]{32,}');
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _hasLetter = RegExp('[A-Za-z]');

  /// [input] with every secret replaced.
  static String text(String input) {
    var out = input.replaceAllMapped(
      _urlCredentials,
      (m) => '${m.group(1)}$mask@',
    );
    out = out.replaceAllMapped(_bearer, (m) => '${m.group(1)} $mask');
    out = out.replaceAll(_jwt, mask);
    out = out.replaceAllMapped(_keyValue, (m) {
      final value = m.group(2)!;
      return value == mask ? m.group(0)! : '${m.group(1)}$mask';
    });
    out = out.replaceAll(_email, emailMask);
    out = out.replaceAllMapped(_tokenLike, (m) {
      final run = m.group(0)!;
      return _hasDigit.hasMatch(run) && _hasLetter.hasMatch(run) ? mask : run;
    });
    return out;
  }

  /// Whether a JSON key names a secret.
  static bool isSecretKey(String key) => _secretKey.hasMatch(key);

  /// [value] (decoded JSON) with every secret replaced: a secret key's
  /// value whole, every string through [text]. Strings, lists, objects and
  /// nesting are capped so one report stays small.
  static Object? json(Object? value) => _json(value, 0);

  static Object? _json(Object? value, int depth) {
    if (value == null || value is bool || value is num) {
      return value;
    }
    if (depth >= maxJsonDepth) {
      return mask;
    }
    if (value is String) {
      final cut = value.length > maxJsonString
          ? value.substring(0, maxJsonString)
          : value;
      return text(cut);
    }
    if (value is List<Object?>) {
      return [
        for (final item in value.take(maxJsonItems)) _json(item, depth + 1),
      ];
    }
    if (value is Map<String, Object?>) {
      final out = <String, Object?>{};
      for (final entry in value.entries.take(maxJsonItems)) {
        out[entry.key] = isSecretKey(entry.key)
            ? mask
            : _json(entry.value, depth + 1);
      }
      return out;
    }
    return text(value.toString());
  }
}
