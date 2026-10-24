import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What [LeagueCatalogWriter.add] found or wrote.
final class LeagueAddition {
  /// Creates the answer of one add.
  const LeagueAddition({required this.league, required this.existed});

  /// The league added, or the league already on file under the same name.
  final League league;

  /// `true` when [league] was already in the catalog and nothing was
  /// written.
  final bool existed;
}

/// Write port over the Football Data league catalog
/// (`football_data.leagues`): an admin adds a competition the list lacks
/// (script 139, migration 0183).
///
/// Two names are one league when their spelling keys agree
/// (`competition.team_name_key`, migration 0110: hamza forms, alif
/// maqsura, taa marbuta, case and spaces folded). The catalog never takes
/// a second league under such a name.
abstract interface class LeagueCatalogWriter {
  /// Adds [name] as a continental league (its clubs come from the whole
  /// catalog, as the big derbies of migration 0104), unless a league whose
  /// name has the same spelling key is on file: then that league is
  /// answered with [LeagueAddition.existed] and nothing is written.
  Future<Result<LeagueAddition>> add({required String name});
}
