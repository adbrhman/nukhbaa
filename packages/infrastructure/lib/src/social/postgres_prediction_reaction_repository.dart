import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PredictionReactionRepository] (migration 0094).
///
/// The three statements below are the ones
/// `supabase/tests/0094_prediction_reactions_test.sql` runs against the
/// real table and its trigger, with their parameters inlined.
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter.
final class PostgresPredictionReactionRepository
    implements PredictionReactionRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresPredictionReactionRepository(this._connection);

  final PostgresConnection _connection;

  /// One live reaction per (fixture, prediction owner, reacting player):
  /// a second one changes the first. `xmax = 0` is true only for a row this
  /// statement inserted, which tells a first reaction from a change; the
  /// owner's user id comes back for the notification.
  static const String upsertSql = '''
INSERT INTO social.prediction_reactions
  (id, season_id, fixture_id, target_participant_id, user_id, emoji,
   reacted_at)
VALUES
  (@id::uuid, @season_id::uuid, @fixture_id::uuid,
   @target_participant_id::uuid, @user_id::uuid,
   @emoji::social.reaction_kind, @reacted_at::timestamptz)
ON CONFLICT ON CONSTRAINT prediction_reactions_one_per_player DO UPDATE SET
  emoji = EXCLUDED.emoji,
  reacted_at = EXCLUDED.reacted_at
RETURNING (xmax = 0) AS inserted,
  (SELECT p.user_id::text
     FROM competition.participants p
    WHERE p.id = target_participant_id) AS target_user_id
''';

  /// Takes one reaction back; no row back means there was none.
  static const String removeSql = '''
DELETE FROM social.prediction_reactions
WHERE fixture_id = @fixture_id::uuid
  AND target_participant_id = @target_participant_id::uuid
  AND user_id = @user_id::uuid
RETURNING id
''';

  /// How many of each kind every prediction of the fixture received, and
  /// whether the viewer gave that kind.
  static const String talliesSql = '''
SELECT r.target_participant_id::text AS target_participant_id,
       r.emoji::text AS emoji,
       count(*)::int AS reactions,
       bool_or(r.user_id = @viewer::uuid) AS mine
FROM social.prediction_reactions r
WHERE r.season_id = @season_id::uuid
  AND r.fixture_id = @fixture_id::uuid
GROUP BY r.target_participant_id, r.emoji
''';

  @override
  Future<Result<PredictionReactionWrite>> upsert({
    required String id,
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
    required ReactionKind kind,
    required DateTime reactedAt,
  }) async {
    final result = await _connection.query(
      upsertSql,
      parameters: {
        'id': id,
        'season_id': seasonId.value,
        'fixture_id': fixture.value,
        'target_participant_id': target.value,
        'user_id': reactor.value,
        'emoji': kind.wireValue,
        'reacted_at': reactedAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapWrite(value),
    };
  }

  @override
  Future<Result<bool>> remove({
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
  }) async {
    final result = await _connection.query(
      removeSql,
      parameters: {
        'fixture_id': fixture.value,
        'target_participant_id': target.value,
        'user_id': reactor.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  @override
  Future<Result<List<PredictionReactionTally>>> tallies({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required UserId viewer,
  }) async {
    final result = await _connection.query(
      talliesSql,
      parameters: {
        'season_id': seasonId.value,
        'fixture_id': fixture.value,
        'viewer': viewer.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapTallies(value),
    };
  }

  Result<PredictionReactionWrite> _mapWrite(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Result.err(_corrupt('inserted', 'the upsert returned no row'));
    }
    final Object? inserted = rows.first['inserted'];
    if (inserted is! bool) {
      return Result.err(_corrupt('inserted', 'not a boolean'));
    }
    final owner = UserId.tryParse(rows.first['target_user_id']?.toString());
    if (owner is Err<UserId>) {
      return Result.err(_corrupt('target_user_id', owner.error.message));
    }
    return Result.ok(
      PredictionReactionWrite(
        inserted: inserted,
        targetUserId: (owner as Ok<UserId>).value,
      ),
    );
  }

  Result<List<PredictionReactionTally>> _mapTallies(
    List<Map<String, dynamic>> rows,
  ) {
    final Map<String, Map<ReactionKind, int>> counts = {};
    final Map<String, ReactionKind> mine = {};
    final Map<String, ParticipantId> targets = {};
    for (final row in rows) {
      final target = ParticipantId.tryParse(
        row['target_participant_id']?.toString(),
      );
      if (target is Err<ParticipantId>) {
        return Result.err(
          _corrupt('target_participant_id', target.error.message),
        );
      }
      final emoji = ReactionEmoji.tryParse(row['emoji']?.toString());
      if (emoji is Err<ReactionEmoji>) {
        return Result.err(_corrupt('emoji', emoji.error.message));
      }
      final Object? n = row['reactions'];
      if (n is! int || n < 1) {
        return Result.err(_corrupt('reactions', 'not a positive integer'));
      }
      final ParticipantId id = (target as Ok<ParticipantId>).value;
      final ReactionKind kind = (emoji as Ok<ReactionEmoji>).value.kind;
      targets[id.value] = id;
      (counts[id.value] ??= {})[kind] = n;
      if (row['mine'] == true) {
        mine[id.value] = kind;
      }
    }
    return Result.ok([
      for (final MapEntry<String, ParticipantId> e in targets.entries)
        PredictionReactionTally(
          targetParticipantId: e.value,
          counts: counts[e.key]!,
          mine: mine[e.key],
        ),
    ]);
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'social.prediction_reaction_row_corrupt',
    'prediction_reactions.$field is corrupt: $detail',
  );
}
