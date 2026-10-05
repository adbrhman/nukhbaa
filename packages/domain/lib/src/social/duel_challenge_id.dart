import 'package:shared/shared.dart';

/// The identity of a shareable duel challenge.
///
/// A value object matching `social.duel_challenges.id`. Raw strings must not
/// cross a domain boundary when naming a duel aggregate.
final class DuelChallengeId extends EntityId {
  /// Creates a challenge id from its canonical UUID string.
  const DuelChallengeId(super.value);

  /// Parses a challenge id received from an untrusted boundary.
  static Result<DuelChallengeId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'social.duel_challenge_id_empty',
          'Duel challenge id is required',
        ),
      );
    }
    if (!_uuid.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'social.duel_challenge_id_malformed',
          'Duel challenge id must be a UUID',
        ),
      );
    }
    return Result.ok(DuelChallengeId(raw));
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
