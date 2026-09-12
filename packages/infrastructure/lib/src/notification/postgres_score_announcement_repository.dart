import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ScoreAnnouncementRepository] over
/// `competition.participants`, `notification.device_tokens` (migration 0039)
/// and `competition.fixture_schedules` (migration 0012).
///
/// Total (Application ADR SS2): never throws, binds every value through a
/// `@named` parameter, and speaks only in domain types.
final class PostgresScoreAnnouncementRepository
    implements ScoreAnnouncementRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresScoreAnnouncementRepository(this._connection);

  final PostgresConnection _connection;

  // The ids arrive as one comma-separated string rather than an array
  // parameter: binding a `uuid[]` through the driver is what produced the
  // 503 on `/rounds/{id}/fixtures`, and `string_to_array` avoids that class
  // of bug entirely while staying a bound parameter.
  static const String _targetsSql = '''
SELECT p.id::text AS participant_id,
       p.user_id::text AS user_id,
       dt.token AS token
FROM competition.participants p
JOIN notification.device_tokens dt ON dt.user_id = p.user_id
WHERE p.id::text = ANY(string_to_array(@participant_ids, ','))
ORDER BY p.id
''';

  static const String _labelSql = '''
SELECT home_team, away_team
FROM competition.fixture_schedules
WHERE fixture_id = @fixture_id
''';

  @override
  Future<Result<List<ScoreNoticeTarget>>> targetsForParticipants(
    List<ParticipantId> participantIds,
  ) async {
    if (participantIds.isEmpty) {
      return const Result.ok(<ScoreNoticeTarget>[]);
    }
    final result = await _connection.query(
      _targetsSql,
      parameters: {
        'participant_ids': [
          for (final id in participantIds) id.value,
        ].join(','),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _targets(value),
    };
  }

  Result<List<ScoreNoticeTarget>> _targets(List<Map<String, dynamic>> rows) {
    final tokensByParticipant = <String, List<String>>{};
    final userByParticipant = <String, String>{};
    for (final row in rows) {
      final participantId = row['participant_id'];
      final userId = row['user_id'];
      final token = row['token'];
      if (participantId is! String || userId is! String || token is! String) {
        continue;
      }
      userByParticipant[participantId] = userId;
      tokensByParticipant
          .putIfAbsent(participantId, () => <String>[])
          .add(token);
    }

    final targets = <ScoreNoticeTarget>[];
    for (final entry in tokensByParticipant.entries) {
      final participant = ParticipantId.tryParse(entry.key);
      final user = UserId.tryParse(userByParticipant[entry.key]);
      if (participant is! Ok<ParticipantId> || user is! Ok<UserId>) {
        continue;
      }
      targets.add(
        ScoreNoticeTarget(
          participantId: participant.value,
          userId: user.value,
          tokens: List<String>.unmodifiable(entry.value),
        ),
      );
    }
    return Result.ok(List<ScoreNoticeTarget>.unmodifiable(targets));
  }

  @override
  Future<Result<String?>> matchLabel(FixtureRef fixture) async {
    final result = await _connection.query(
      _labelSql,
      parameters: {'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _label(value),
    };
  }

  Result<String?> _label(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final home = rows.first['home_team'];
    final away = rows.first['away_team'];
    if (home is! String || away is! String) {
      return const Result.ok(null);
    }
    return Result.ok('$home × $away');
  }
}
