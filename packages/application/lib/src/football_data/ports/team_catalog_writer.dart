import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What [TeamCatalogWriter.add] found or wrote.
final class TeamAddition {
  /// Creates the answer of one add.
  const TeamAddition({required this.team, required this.existed});

  /// The club added, or the club already on file under the same name.
  final Team team;

  /// `true` when [team] was already in the catalog and nothing was written.
  final bool existed;
}

/// Write port over the Football Data team catalog (`football_data.teams`):
/// an admin adds a club the list lacks (script 91, migration 0173).
///
/// Two names are one club when their spelling keys agree
/// (`competition.team_name_key`, migration 0110: hamza forms, alif
/// maqsura, taa marbuta, case and spaces folded). The catalog never takes
/// a second club under such a name.
abstract interface class TeamCatalogWriter {
  /// Adds [name] under [leagueId] (none when `null`), unless a club whose
  /// name has the same spelling key is on file: then that club is answered
  /// with [TeamAddition.existed] and nothing is written. A blocked club
  /// (migration 0174) is refused with `AdminAddTeam.blocked`.
  Future<Result<TeamAddition>> add({
    required String name,
    required LeagueRef? leagueId,
  });
}
