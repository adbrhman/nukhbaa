import 'package:domain/src/competition/competition_id.dart';
import 'package:shared/shared.dart';

/// The identity of one weekly-league group -- a row of
/// `gamification.weekly_leagues` (migration 0061).
///
/// A value object (Coding Standards ADR, Section 2), canonically a UUID
/// matching that table's primary key. It identifies a GROUP, never a member:
/// membership is `(league_id, user_id)` and a player's seat is found through
/// `(week_start, user_id)`.
final class WeeklyLeagueId extends EntityId {
  /// Creates a [WeeklyLeagueId] from its canonical UUID string.
  const WeeklyLeagueId(super.value);

  /// Parses a [WeeklyLeagueId] from an untrusted [raw] string, returning a
  /// validation [AppError] when it is absent or not a canonical UUID.
  static Result<WeeklyLeagueId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'gamification.weekly_league_id_empty',
          'Weekly league id is required',
        ),
      );
    }
    if (!uuidPattern.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'gamification.weekly_league_id_malformed',
          'Weekly league id must be a UUID',
        ),
      );
    }
    return Result.ok(WeeklyLeagueId(raw));
  }
}
