import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_new_player_reader.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/support/postgres_support_conversation_opener.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _c = '99999999-9999-4999-8999-999999999999';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.parameters.add(parameters);
    return _answers.removeAt(0);
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

/// Script 202: the adapters the composition root wires for the admin's
/// new-players list and his first message. Their SQL runs against the
/// schema in `supabase/tests/new_players_query_test.sql`.
void main() {
  group('PostgresNewPlayerReader', () {
    test('maps a row, its phone, its predictions and its hint', () async {
      final connection = _Connection([
        Result.ok([
          {
            'id': _a,
            'email': 'a@t.io',
            'role': 'user',
            'status': 'active',
            'display_name': 'ملك التوقعات',
            'created_at': DateTime.utc(2026, 11, 2, 12),
            'phone_accounts': 11,
            'predictions': 10,
            'name_hint': 'title',
          },
          {
            'id': _c,
            'email': 'c@t.io',
            'role': 'user',
            'status': 'suspended',
            'display_name': 'محمد علي',
            'created_at': '2026-11-01T09:00:00Z',
            'phone_accounts': 0,
            'predictions': 0,
            'name_hint': null,
          },
        ]),
      ]);

      final read = await PostgresNewPlayerReader(
        connection,
      ).newPlayers(days: 7, limit: 200);

      final players = (read as Ok<List<NewPlayer>>).value;
      expect(players, hasLength(2));
      expect(players[0].user.displayName, 'ملك التوقعات');
      expect(players[0].phoneAccounts, 11);
      expect(players[0].nameHint, NewPlayerNameHint.title);
      expect(players[1].user.status, UserStatus.suspended);
      expect(players[1].joinedAt, DateTime.utc(2026, 11, 1, 9));
      expect(players[1].nameHint, isNull);
      expect(connection.parameters.single, {'days': 7, 'limit': 200});
    });

    test('a malformed row is a transient row_corrupt', () async {
      final read = await PostgresNewPlayerReader(
        _Connection([
          const Result.ok([
            {'id': 'x', 'role': 'user', 'status': 'active'},
          ]),
        ]),
      ).newPlayers(days: 7, limit: 200);

      expect((read as Err<List<NewPlayer>>).error.code, 'identity.row_corrupt');
    });
  });

  group('PostgresSupportConversationOpener', () {
    test('answers the conversation opened or found', () async {
      final connection = _Connection([
        const Result.ok([
          {'id': _c},
        ]),
      ]);

      final opened = await PostgresSupportConversationOpener(
        connection,
      ).openFor(const UserId(_a));

      expect((opened as Ok<SupportConversationId>).value.value, _c);
      expect(connection.parameters.single, {'player_id': _a});
    });

    test('an opening at the same moment is read once more', () async {
      final connection = _Connection([
        const Result.ok([]),
        const Result.ok([
          {'id': _c},
        ]),
      ]);

      final opened = await PostgresSupportConversationOpener(
        connection,
      ).openFor(const UserId(_a));

      expect((opened as Ok<SupportConversationId>).value.value, _c);
      expect(connection.parameters, hasLength(2));
    });

    test('a database failure is passed on', () async {
      final opened = await PostgresSupportConversationOpener(
        _Connection([
          const Result.err(AppError.transient('db.unavailable', 'down')),
        ]),
      ).openFor(const UserId(_a));

      expect(
        (opened as Err<SupportConversationId>).error.code,
        'db.unavailable',
      );
    });
  });
}
