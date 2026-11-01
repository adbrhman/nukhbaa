import 'package:shared/shared.dart';

/// One row of a league table as a provider reports it (script 189).
final class LeagueStandingRow {
  /// Creates the row.
  const LeagueStandingRow({
    required this.teamExternalId,
    required this.position,
    this.points,
    this.played,
  });

  /// The provider's team id.
  final String teamExternalId;

  /// The place in the table, 1 for the leader.
  final int position;

  /// League points, when the provider reports them.
  final int? points;

  /// Matches played, when the provider reports them.
  final int? played;
}

/// A league table the server keeps, with when it was read.
final class StoredLeagueTable {
  /// Creates the table.
  const StoredLeagueTable({required this.rows, required this.fetchedAt});

  /// The rows, leader first.
  final List<LeagueStandingRow> rows;

  /// When the provider was asked for it.
  final DateTime fetchedAt;
}

/// Read port over a provider's league tables (script 189).
abstract interface class LeagueStandingsSource {
  /// The current table of [leagueRef] (the provider's competition id or
  /// code) in the season that starts in [season] (2026 for 2026/27).
  ///
  /// Returns an error with code `football_data.provider_quota` when the
  /// adapter is keeping the rest of its daily quota.
  Future<Result<List<LeagueStandingRow>>> standingsOf({
    required String leagueRef,
    required int season,
  });
}

/// The tables already read, one per provider league
/// (`football_data.league_standings`, migration 0192). A table is asked for
/// at most once a day and kept, so a failed read still has the last one.
abstract interface class LeagueStandingsStore {
  /// The last table kept for [leagueRef] of [source], or null.
  Future<Result<StoredLeagueTable?>> latest({
    required String source,
    required String leagueRef,
  });

  /// Keeps [rows] as the table of [leagueRef] of [source], read at
  /// [fetchedAt], in place of the one before.
  Future<Result<void>> save({
    required String source,
    required String leagueRef,
    required List<LeagueStandingRow> rows,
    required DateTime fetchedAt,
  });
}
