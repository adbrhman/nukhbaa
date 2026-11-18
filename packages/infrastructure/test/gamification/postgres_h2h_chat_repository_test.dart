import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_chat_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const String _player = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _other = 'aaaaaaaa-0000-4000-8000-000000000002';
const String _league = 'bbbbbbbb-0000-4000-8000-000000000001';

/// Answers each query with the next canned rows, and keeps what it ran.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    return _answers.isEmpty ? const Result.ok([]) : _answers.removeAt(0);
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async {
    return action(this);
  }

  @override
  Future<void> close() async {}
}

Result<List<Map<String, dynamic>>> _rows(List<Map<String, dynamic>> rows) =>
    Result.ok(rows);

/// Hermetic tests of the group chat adapter's binding and row mapping; the
/// statements themselves run against Postgres in
/// supabase/tests/0216_h2h_chat_queries_test.sql.
void main() {
  test('a player with no seat gets no group, after one query', () async {
    final conn = _FakeConnection([_rows([])]);
    final result = await PostgresH2hChatRepository(
      conn,
    ).page(playerId: const UserId(_player), afterId: null, limit: 50);

    expect((result as Ok<H2hChatPage>).value.hasGroup, isFalse);
    expect(conn.sqls, hasLength(1));
    expect(conn.params.single, {'player_id': _player});
  });

  test('a page comes back oldest first with its flags', () async {
    final conn = _FakeConnection([
      _rows([
        {
          'league_id': _league,
          'muted': false,
          'rules_accepted': true,
          'unread': 2,
        },
      ]),
      // Newest first, as the statement orders them.
      _rows([
        {
          'id': 8,
          'sender_id': _other,
          'sender_name': 'سالم',
          'body': 'الثانية',
          'created_at': DateTime.utc(2026, 11, 15, 10, 1),
        },
        {
          'id': 7,
          'sender_id': _player,
          'sender_name': 'أنا',
          'body': 'الأولى',
          'created_at': DateTime.utc(2026, 11, 15, 10),
        },
      ]),
    ]);

    final result = await PostgresH2hChatRepository(
      conn,
    ).page(playerId: const UserId(_player), afterId: 6, limit: 50);

    final H2hChatPage page = (result as Ok<H2hChatPage>).value;
    expect(page.hasGroup, isTrue);
    expect(page.rulesAccepted, isTrue);
    expect(page.muted, isFalse);
    expect(page.unread, 2);
    expect(page.messages.map((m) => m.id), [7, 8]);
    expect(page.messages.last.senderName, 'سالم');
    expect(conn.params.last, {'league_id': _league, 'after': 6, 'limit': 50});
  });

  test('a send answers the stored message; no seat is refused', () async {
    final conn = _FakeConnection([
      _rows([
        {
          'id': 9,
          'created_at': DateTime.utc(2026, 11, 15, 10, 2),
          'sender_name': 'أنا',
        },
      ]),
      _rows([]),
    ]);
    final repo = PostgresH2hChatRepository(conn);
    final H2hChatBody body =
        (H2hChatBody.parse('مرحبا') as Ok<H2hChatBody>).value;

    final sent = await repo.send(
      playerId: const UserId(_player),
      body: body,
      at: DateTime.utc(2026, 11, 15, 10, 2),
    );
    final H2hChatMessage message = (sent as Ok<H2hChatMessage>).value;
    expect(message.id, 9);
    expect(message.body, 'مرحبا');
    expect(conn.params.first['body'], 'مرحبا');

    final none = await repo.send(
      playerId: const UserId(_player),
      body: body,
      at: DateTime.utc(2026, 11, 15, 10, 3),
    );
    expect((none as Err<H2hChatMessage>).error.code, 'h2h.chat_no_group');
  });

  test('a failed query passes through', () async {
    const AppError down = AppError.transient('db.down', 'down');
    final conn = _FakeConnection([const Result.err(down)]);

    final result = await PostgresH2hChatRepository(
      conn,
    ).markRead(playerId: const UserId(_player), at: DateTime.utc(2026));

    expect((result as Err<void>).error, down);
  });
}
