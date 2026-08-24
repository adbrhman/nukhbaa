import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureReactionRepository] over the `social.fixture_reactions`
/// table (Database ADR; migration `0020_axiom4_fixture_ledger_social.sql`) —
/// the per-fixture sibling of [PostgresReactionRepository].
final class PostgresFixtureReactionRepository
    implements FixtureReactionRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureReactionRepository(this._connection);

  final PostgresConnection _connection;

  static const String _upsertSql = '''
INSERT INTO social.fixture_reactions
  (id, group_id, fixture_id, user_id, emoji, reacted_at)
VALUES
  (@id, @group_id, @fixture_id, @user_id, @emoji, @reacted_at)
ON CONFLICT ON CONSTRAINT fixture_reactions_group_fixture_user_uniq
DO UPDATE SET emoji = excluded.emoji, reacted_at = excluded.reacted_at
''';

  @override
  Future<Result<void>> upsertReaction(FixtureReaction reaction) async {
    final result = await _connection.query(
      _upsertSql,
      parameters: {
        'id': reaction.id.value,
        'group_id': reaction.groupId.value,
        'fixture_id': reaction.fixture.value,
        'user_id': reaction.userId.value,
        'emoji': reaction.emoji.wireValue,
        'reacted_at': reaction.reactedAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  static const String _findSql = '''
SELECT id, group_id, fixture_id, user_id, emoji, reacted_at
FROM social.fixture_reactions
WHERE group_id = @group_id AND fixture_id = @fixture_id AND user_id = @user_id
''';

  @override
  Future<Result<FixtureReaction?>> findReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  ) async {
    final result = await _connection.query(
      _findSql,
      parameters: {
        'group_id': groupId.value,
        'fixture_id': fixture.value,
        'user_id': userId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapOne(value.first),
    };
  }

  static const String _listSql = '''
SELECT id, group_id, fixture_id, user_id, emoji, reacted_at
FROM social.fixture_reactions
WHERE group_id = @group_id AND fixture_id = @fixture_id
ORDER BY reacted_at ASC, id ASC
''';

  @override
  Future<Result<List<FixtureReaction>>> listReactionsForFixture(
    GroupId groupId,
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _listSql,
      parameters: {'group_id': groupId.value, 'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapMany(value),
    };
  }

  static const String _deleteSql = '''
DELETE FROM social.fixture_reactions
WHERE group_id = @group_id AND fixture_id = @fixture_id AND user_id = @user_id
RETURNING id
''';

  @override
  Future<Result<bool>> removeReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  ) async {
    final result = await _connection.query(
      _deleteSql,
      parameters: {
        'group_id': groupId.value,
        'fixture_id': fixture.value,
        'user_id': userId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  Result<List<FixtureReaction>> _mapMany(List<Map<String, dynamic>> rows) {
    final reactions = <FixtureReaction>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<FixtureReaction?>) {
        return Result.err(mapped.error);
      }
      final reaction = (mapped as Ok<FixtureReaction?>).value;
      if (reaction != null) {
        reactions.add(reaction);
      }
    }
    return Result.ok(List<FixtureReaction>.unmodifiable(reactions));
  }

  Result<FixtureReaction?> _mapOne(Map<String, dynamic> row) {
    final idResult = ReactionId.tryParse(row['id']?.toString());
    final groupIdResult = GroupId.tryParse(row['group_id']?.toString());
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final userIdResult = UserId.tryParse(row['user_id']?.toString());
    final emojiResult = ReactionEmoji.tryParse(row['emoji']?.toString());
    final reactedAt = _readUtcTimestamp(row['reacted_at']);

    if (idResult is Err<ReactionId>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    if (groupIdResult is Err<GroupId>) {
      return Result.err(_corrupt('group_id', groupIdResult.error.message));
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixtureResult.error.message));
    }
    if (userIdResult is Err<UserId>) {
      return Result.err(_corrupt('user_id', userIdResult.error.message));
    }
    if (emojiResult is Err<ReactionEmoji>) {
      return Result.err(_corrupt('emoji', emojiResult.error.message));
    }
    if (reactedAt == null) {
      return Result.err(_corrupt('reacted_at', 'not a timestamp'));
    }

    return Result.ok(
      FixtureReaction.fromStored(
        id: (idResult as Ok<ReactionId>).value,
        groupId: (groupIdResult as Ok<GroupId>).value,
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        userId: (userIdResult as Ok<UserId>).value,
        emoji: (emojiResult as Ok<ReactionEmoji>).value,
        reactedAt: reactedAt,
      ),
    );
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    if (constraint == 'fixture_reactions_group_fixture_user_uniq') {
      return const AppError.invariant(
        'social.reaction_conflict',
        'A concurrent reaction won the race',
      );
    }
    if (constraint == 'fixture_reactions_group_id_fkey') {
      return const AppError.invariant(
        'social.group_not_found',
        'Group not found',
      );
    }
    if (constraint == 'fixture_reactions_user_id_fkey') {
      return const AppError.invariant(
        'social.user_not_found',
        'User not found',
      );
    }
    return const AppError.invariant(
      'social.integrity_violation',
      'The write violated a social integrity rule',
    );
  }

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'social.row_corrupt',
    'Stored fixture_reactions row has invalid $field: $detail',
  );
}
