import 'package:shared/shared.dart';

/// A *reference* to a team owned by the Football Data context
/// (`football_data.teams`), used wherever another aggregate names a team by
/// id only — mirrors [FixtureRef]'s reasoning exactly: the referencing
/// aggregate never reaches into Football Data, it only names what it needs.
///
/// A value object (Coding Standards ADR, Section 2), canonically a UUID.
final class TeamRef extends EntityId {
  /// Creates a [TeamRef] from its canonical UUID string.
  const TeamRef(super.value);

  /// Parses a [TeamRef] from an untrusted [raw] string, returning a
  /// validation [AppError] when it is absent or not a canonical UUID.
  static Result<TeamRef> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'football_data.team_ref_empty',
          'Team id is required',
        ),
      );
    }
    if (!_uuid.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'football_data.team_ref_malformed',
          'Team id must be a UUID',
        ),
      );
    }
    return Result.ok(TeamRef(raw));
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
