import 'package:domain/src/competition/competition_id.dart';
import 'package:shared/shared.dart';

/// The identity of one group of the monthly head-to-head league -- a row of
/// `gamification.h2h_leagues` (migration 0100).
///
/// A value object (Coding Standards ADR, Section 2), canonically a UUID
/// matching that table's primary key. It identifies a GROUP, never a member:
/// membership is `(league_id, user_id)` and a player's seat is found through
/// `(month_start, user_id)`.
final class H2hLeagueId extends EntityId {
  /// Creates an [H2hLeagueId] from its canonical UUID string.
  const H2hLeagueId(super.value);

  /// Parses an [H2hLeagueId] from an untrusted [raw] string, returning a
  /// validation [AppError] when it is absent or not a canonical UUID.
  static Result<H2hLeagueId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'gamification.h2h_league_id_empty',
          'Head-to-head league id is required',
        ),
      );
    }
    if (!uuidPattern.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'gamification.h2h_league_id_malformed',
          'Head-to-head league id must be a UUID',
        ),
      );
    }
    return Result.ok(H2hLeagueId(raw));
  }
}
