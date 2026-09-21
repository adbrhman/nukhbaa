import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read/write port over `identity.user_favorite_teams` (0065, plan P3-1).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Tier-3: nothing on the points path
/// reads or writes it.
abstract interface class FavoriteTeamRepository {
  /// The teams [userId] follows, in the order they were stored;
  /// [FavoriteTeams.none] when none.
  Future<Result<FavoriteTeams>> favoritesOf(UserId userId);

  /// Replaces [userId]'s teams with [teams] in one transaction and returns
  /// what was stored. A team id missing from the catalog is a validation
  /// error (`identity.favorite_team_unknown`) and nothing changes.
  Future<Result<FavoriteTeams>> replace(UserId userId, FavoriteTeams teams);
}
