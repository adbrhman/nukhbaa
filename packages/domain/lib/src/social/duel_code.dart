import 'package:shared/shared.dart';

/// The shareable code for a duel challenge.
///
/// The shape mirrors the database backstop in migration 0090: twelve
/// characters from a fixed unambiguous alphabet. Generation is deliberately
/// outside the pure domain; the backend database owns the cryptographic code
/// generation in this phase.
final class DuelCode {
  const DuelCode._(this.value);

  /// The canonical share code.
  final String value;

  /// Fixed code length stored by `social.duel_challenges`.
  static const int codeLength = 12;

  /// The URL-safe alphabet shared by the domain validator and the DB check.
  static const String _alphabet = 'ABCDEFGHJKMNPQRSTVWXYZ23456789';

  /// Whether [character] belongs to the closed duel-code alphabet.
  static bool isAllowedChar(String character) => _alphabet.contains(character);

  /// The alphabet a compliant generator must draw from.
  static String get alphabet => _alphabet;

  /// Parses a duel code from an untrusted token.
  static Result<DuelCode> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation('social.duel_code_empty', 'Duel code is required'),
      );
    }
    if (raw.length != codeLength) {
      return const Result.err(
        AppError.validation(
          'social.duel_code_malformed',
          'Duel code must be exactly $codeLength characters',
        ),
      );
    }
    for (var i = 0; i < raw.length; i++) {
      if (!_alphabet.contains(raw[i])) {
        return const Result.err(
          AppError.validation(
            'social.duel_code_malformed',
            'Duel code contains an unsupported character',
          ),
        );
      }
    }
    return Result.ok(DuelCode._(raw));
  }

  @override
  bool operator ==(Object other) => other is DuelCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DuelCode($value)';
}
