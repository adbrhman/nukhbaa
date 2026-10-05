import 'package:shared/shared.dart';

/// The identity of one accepted duel.
///
/// A value object matching `social.duels.id`. Winner, points and lifecycle are
/// deliberately not part of this identity; they are derived later from the
/// fixture, predictions and official result.
final class DuelId extends EntityId {
  /// Creates a duel id from its canonical UUID string.
  const DuelId(super.value);

  /// Parses a duel id received from an untrusted boundary.
  static Result<DuelId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation('social.duel_id_empty', 'Duel id is required'),
      );
    }
    if (!_uuid.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'social.duel_id_malformed',
          'Duel id must be a UUID',
        ),
      );
    }
    return Result.ok(DuelId(raw));
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
