import 'package:shared/shared.dart';

/// A *reference* to a league owned by the Football Data context
/// (`football_data.leagues`), mirroring [TeamRef] exactly: the referencing
/// aggregate never reaches into Football Data, it only names what it needs.
final class LeagueRef extends EntityId {
  /// Creates a [LeagueRef] from its canonical UUID string.
  const LeagueRef(super.value);

  /// Parses a [LeagueRef] from an untrusted [raw] string.
  static Result<LeagueRef> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'football_data.league_ref_empty',
          'League id is required',
        ),
      );
    }
    if (!_uuid.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'football_data.league_ref_malformed',
          'League id must be a UUID',
        ),
      );
    }
    return Result.ok(LeagueRef(raw));
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
