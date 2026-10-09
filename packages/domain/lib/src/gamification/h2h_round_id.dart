import 'package:domain/src/competition/competition_id.dart';
import 'package:shared/shared.dart';

/// The identity of one approved round of the monthly head-to-head league --
/// a row of `gamification.h2h_rounds` (migration 0100).
///
/// A value object (Coding Standards ADR, Section 2), canonically a UUID
/// matching that table's primary key.
final class H2hRoundId extends EntityId {
  /// Creates an [H2hRoundId] from its canonical UUID string.
  const H2hRoundId(super.value);

  /// Parses an [H2hRoundId] from an untrusted [raw] string, returning a
  /// validation [AppError] when it is absent or not a canonical UUID.
  static Result<H2hRoundId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'gamification.h2h_round_id_empty',
          'Head-to-head round id is required',
        ),
      );
    }
    if (!uuidPattern.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'gamification.h2h_round_id_malformed',
          'Head-to-head round id must be a UUID',
        ),
      );
    }
    return Result.ok(H2hRoundId(raw));
  }
}
