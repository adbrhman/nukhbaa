import 'dart:convert';

import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [MatchDetailsStore] over `football_data.match_details` (migration 0179).
///
/// The events are kept as one JSONB array, already in the app's kinds; a
/// fixture the provider has no match for is a row with `found = false`, so it
/// is not asked about again.
final class PostgresMatchDetailsStore implements MatchDetailsStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresMatchDetailsStore(this._connection);

  final PostgresConnection _connection;

  // A finished match: its result is recorded. Hidden fixtures are left out,
  // as by every sync (0098). The provider's own match id comes along when
  // the fixture came from it.
  static const String _pendingSql = '''
SELECT s.fixture_id::text  AS fixture_id,
       s.kickoff_at        AS kickoff_at,
       l.name              AS league_name,
       r.home_goals        AS home_goals,
       r.away_goals        AS away_goals,
       m.external_id       AS external_id
FROM competition.fixture_schedules s
JOIN scoring.fixture_results r
  ON r.fixture_id = s.fixture_id
JOIN football_data.leagues l
  ON l.id = s.league_id
LEFT JOIN football_data.match_details d
  ON d.fixture_id = s.fixture_id
LEFT JOIN football_data.external_identity_map m
  ON m.canonical_id = s.fixture_id
 AND m.external_source = @source
 AND m.canonical_table = 'fixture'
WHERE d.fixture_id IS NULL
  AND s.hidden_at IS NULL
  AND s.kickoff_at >= @from::timestamptz
  AND s.kickoff_at < @before::timestamptz
ORDER BY s.kickoff_at DESC, s.fixture_id
LIMIT 100
''';

  static const String _saveSql = '''
INSERT INTO football_data.match_details
  (fixture_id, source, external_match_id, found, half_time_home,
   half_time_away, venue, round, referee, events, fetched_at)
VALUES (@fixture_id::uuid, @source::text, @external_match_id::text,
        @found::boolean, @half_time_home::integer, @half_time_away::integer,
        @venue::text, @round::text, @referee::text, @events::jsonb,
        @fetched_at::timestamptz)
ON CONFLICT (fixture_id) DO UPDATE
SET source = EXCLUDED.source,
    external_match_id = EXCLUDED.external_match_id,
    found = EXCLUDED.found,
    half_time_home = EXCLUDED.half_time_home,
    half_time_away = EXCLUDED.half_time_away,
    venue = EXCLUDED.venue,
    round = EXCLUDED.round,
    referee = EXCLUDED.referee,
    events = EXCLUDED.events,
    fetched_at = EXCLUDED.fetched_at
''';

  static const String _findSql = '''
SELECT fixture_id::text   AS fixture_id,
       source             AS source,
       external_match_id  AS external_match_id,
       found              AS found,
       half_time_home     AS half_time_home,
       half_time_away     AS half_time_away,
       venue              AS venue,
       round              AS round,
       referee            AS referee,
       events::text       AS events,
       fetched_at         AS fetched_at
FROM football_data.match_details
WHERE fixture_id = @fixture_id::uuid
''';

  @override
  Future<Result<List<PendingMatchDetails>>> pending({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  }) async {
    final result = await _connection.query(
      _pendingSql,
      parameters: {
        'source': source,
        'from': kickedOffFrom.toUtc().toIso8601String(),
        'before': kickedOffBefore.toUtc().toIso8601String(),
      },
    );
    switch (result) {
      case Err<List<Map<String, dynamic>>>(:final error):
        return Result.err(error);
      case Ok<List<Map<String, dynamic>>>(:final value):
        final pending = <PendingMatchDetails>[];
        for (final row in value) {
          final kickoff = row['kickoff_at'];
          final home = row['home_goals'];
          final away = row['away_goals'];
          if (kickoff is! DateTime || home is! int || away is! int) {
            return Result.err(_corrupt('pending fixture'));
          }
          pending.add(
            PendingMatchDetails(
              fixtureId: row['fixture_id'].toString(),
              kickoffAt: kickoff.toUtc(),
              leagueName: row['league_name']?.toString() ?? '',
              homeGoals: home,
              awayGoals: away,
              externalMatchId: row['external_id']?.toString(),
            ),
          );
        }
        return Result.ok(pending);
    }
  }

  @override
  Future<Result<void>> save(MatchDetails details) async {
    final result = await _connection.query(
      _saveSql,
      parameters: {
        'fixture_id': details.fixtureId,
        'source': details.source,
        'external_match_id': details.externalMatchId,
        'found': details.found,
        'half_time_home': details.halfTimeHome,
        'half_time_away': details.halfTimeAway,
        'venue': details.venue,
        'round': details.round,
        'referee': details.referee,
        'events': jsonEncode([
          for (final event in details.events) encodeEvent(event),
        ]),
        'fetched_at': details.fetchedAt.toUtc().toIso8601String(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<MatchDetails?>> find(String fixtureId) async {
    final result = await _connection.query(
      _findSql,
      parameters: {'fixture_id': fixtureId},
    );
    switch (result) {
      case Err<List<Map<String, dynamic>>>(:final error):
        return Result.err(error);
      case Ok<List<Map<String, dynamic>>>(:final value):
        if (value.isEmpty) {
          return const Result.ok(null);
        }
        final row = value.first;
        final fetchedAt = row['fetched_at'];
        final found = row['found'];
        if (fetchedAt is! DateTime || found is! bool) {
          return Result.err(_corrupt('match_details row'));
        }
        final List<MatchEvent> events;
        try {
          final decoded = jsonDecode(row['events']?.toString() ?? '[]');
          events = <MatchEvent>[
            if (decoded is List)
              for (final raw in decoded)
                if (raw is Map) decodeEvent(raw),
          ];
        } on FormatException {
          return Result.err(_corrupt('match_details.events'));
        }
        return Result.ok(
          MatchDetails(
            fixtureId: row['fixture_id'].toString(),
            found: found,
            source: row['source']?.toString() ?? '',
            externalMatchId: row['external_match_id']?.toString(),
            events: events,
            halfTimeHome: row['half_time_home'] as int?,
            halfTimeAway: row['half_time_away'] as int?,
            venue: row['venue'] as String?,
            round: row['round'] as String?,
            referee: row['referee'] as String?,
            fetchedAt: fetchedAt.toUtc(),
          ),
        );
    }
  }

  /// One event as stored in the `events` array.
  static Map<String, Object?> encodeEvent(MatchEvent event) => {
    'minute': event.minute,
    'kind': event.kind.wire,
    'home': event.home,
    'player': event.player,
    'assist': event.assist,
    'detail': event.detail,
  };

  /// One stored event back; an unknown kind reads as
  /// [MatchEventKind.other].
  static MatchEvent decodeEvent(Map<dynamic, dynamic> raw) => MatchEvent(
    minute: raw['minute']?.toString() ?? '',
    kind: MatchEventKind.fromWire(raw['kind']?.toString() ?? ''),
    home: raw['home'] == true,
    player: raw['player']?.toString(),
    assist: raw['assist']?.toString(),
    detail: raw['detail']?.toString(),
  );

  static AppError _corrupt(String what) => AppError.transient(
    'football_data.row_corrupt',
    'Stored $what is malformed',
  );
}
