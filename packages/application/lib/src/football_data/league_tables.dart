import 'package:application/src/football_data/match_strength.dart';
import 'package:application/src/football_data/ports/league_standings.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:shared/shared.dart';

/// Where one league's table is read: the provider that serves it and its
/// competition id or code there.
final class StandingsRef {
  /// Creates the reference.
  const StandingsRef({required this.source, required this.leagueRef});

  /// `football-data` or `highlightly`.
  final String source;

  /// The provider's competition id (`262041`) or code (`PD`).
  final String leagueRef;

  /// `source:leagueRef`, for maps and the log.
  String get key => '$source:$leagueRef';
}

/// A league table by catalog club: what the selection scores with.
final class LeagueTable {
  /// Creates the table.
  const LeagueTable({
    required this.places,
    required this.size,
    required this.fetchedAt,
  });

  /// Catalog team id -> place, for the clubs whose provider id is mapped.
  final Map<String, int> places;

  /// How many clubs the provider's table holds.
  final int size;

  /// When the provider was asked for it.
  final DateTime fetchedAt;

  /// The place of catalog team [teamId]: null when the club is not in the
  /// table, unless [outsideIsLast], when it is placed below the last club
  /// (a League Cup club from below the Premier League).
  TablePlace? placeOf(String teamId, {bool outsideIsLast = false}) {
    final position = places[teamId];
    if (position != null) {
      return TablePlace(position: position, tableSize: size);
    }
    return outsideIsLast
        ? TablePlace(position: size + 1, tableSize: size)
        : null;
  }
}

/// The season a [riyadhDay] belongs to, by the year it starts in: July
/// onwards is the season starting that year (2026/27 is 2026).
int seasonStartOf(DateTime riyadhDay) =>
    riyadhDay.month >= 7 ? riyadhDay.year : riyadhDay.year - 1;

/// The league tables the daily selection scores with (script 189).
///
/// A table kept less than [maxAge] ago is used as it is, so a provider is
/// asked for each table at most about once a day. An older one is asked for
/// again and kept; should that fail, the last table kept is used however
/// old it is, and with none at all the caller scores without places. Nothing
/// here stops a run: every failure is a line in `notes`. Never throws.
final class LeagueTables {
  /// Creates the reader.
  LeagueTables({
    required Map<String, LeagueStandingsSource> sources,
    required LeagueStandingsStore store,
    required ProviderSyncStore identities,
    this.maxAge = const Duration(hours: 20),
  }) : _sources = sources,
       _store = store,
       _identities = identities;

  final Map<String, LeagueStandingsSource> _sources;
  final LeagueStandingsStore _store;
  final ProviderSyncStore _identities;

  /// How old a kept table may be before the provider is asked again.
  final Duration maxAge;

  /// The table of [ref] for the season of [riyadhDay] as of [nowUtc], or
  /// null when none could be read or kept.
  Future<LeagueTable?> tableOf(
    StandingsRef ref, {
    required DateTime nowUtc,
    required DateTime riyadhDay,
    required List<String> notes,
  }) async {
    final latest = await _store.latest(
      source: ref.source,
      leagueRef: ref.leagueRef,
    );
    final StoredLeagueTable? kept = switch (latest) {
      Ok<StoredLeagueTable?>(:final value) => value,
      Err<StoredLeagueTable?>() => null,
    };
    if (latest case Err<StoredLeagueTable?>(:final error)) {
      notes.add('table ${ref.key}: kept table unreadable (${error.code})');
    }

    var table = kept;
    if (kept == null || nowUtc.difference(kept.fetchedAt) >= maxAge) {
      final source = _sources[ref.source];
      if (source == null) {
        notes.add('table ${ref.key}: no provider configured');
      } else {
        final fetched = await source.standingsOf(
          leagueRef: ref.leagueRef,
          season: seasonStartOf(riyadhDay),
        );
        switch (fetched) {
          case Ok<List<LeagueStandingRow>>(:final value) when value.isNotEmpty:
            table = StoredLeagueTable(rows: value, fetchedAt: nowUtc);
            final saved = await _store.save(
              source: ref.source,
              leagueRef: ref.leagueRef,
              rows: value,
              fetchedAt: nowUtc,
            );
            notes.add(
              saved is Err<void>
                  ? 'table ${ref.key}: read, not kept (${saved.error.code})'
                  : 'table ${ref.key}: read ${value.length} clubs',
            );
          case Ok<List<LeagueStandingRow>>():
            notes.add(
              'table ${ref.key}: provider sent an empty table'
              '${_keptNote(kept)}',
            );
          case Err<List<LeagueStandingRow>>(:final error):
            notes.add(
              'table ${ref.key}: read failed (${error.code})'
              '${_keptNote(kept)}',
            );
        }
      }
    }

    if (table == null || table.rows.isEmpty) {
      return null;
    }
    final ids = await _identities.canonicalIds(
      source: ref.source,
      table: 'team',
      externalIds: [for (final row in table.rows) row.teamExternalId],
    );
    if (ids is Err<Map<String, String>>) {
      notes.add('table ${ref.key}: club lookup failed (${ids.error.code})');
      return null;
    }
    final byExternal = (ids as Ok<Map<String, String>>).value;
    final places = <String, int>{};
    var size = table.rows.length;
    for (final row in table.rows) {
      if (row.position > size) {
        size = row.position;
      }
      final teamId = byExternal[row.teamExternalId];
      if (teamId != null) {
        places.putIfAbsent(teamId, () => row.position);
      }
    }
    return LeagueTable(places: places, size: size, fetchedAt: table.fetchedAt);
  }

  static String _keptNote(StoredLeagueTable? kept) => kept == null
      ? '; no table kept'
      : '; using the table kept ${isoDay(kept.fetchedAt)}';
}
