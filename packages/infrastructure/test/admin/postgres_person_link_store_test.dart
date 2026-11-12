import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_account_name_directory.dart';
import 'package:infrastructure/src/admin/postgres_person_link_store.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql.add(sql);
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

Map<String, dynamic> _row(String person, String id, bool counted) => {
  'person_id': person,
  'id': id,
  'email': '$id@t.io',
  'role': 'user',
  'status': 'active',
  'display_name': 'P',
  'counted': counted,
  'hidden_at': counted ? null : DateTime.utc(2026, 11, 12),
};

/// Script 263: the adapters the composition root wires for one person's
/// accounts. Their SQL runs against the schema in
/// `supabase/tests/0209_person_links_test.sql`.
void main() {
  test('groups the linked accounts by person, the main one first', () async {
    final connection = _Connection([
      Result.ok([_row(_a, _a, true), _row(_a, _b, false)]),
    ]);

    final result = await PostgresPersonLinkStore(connection).list();

    final person = (result as Ok<List<LinkedPerson>>).value.single;
    expect(person.main, const UserId(_a));
    expect([for (final a in person.accounts) a.user.id.value], [_a, _b]);
    expect(person.accounts.last.hidden, isTrue);
    expect(person.accounts.last.counted, isFalse);
  });

  test('sets a person with text parameters, no second as empty', () async {
    final connection = _Connection([
      Result.ok([
        {'outcome': 'ok'},
      ]),
      Result.ok([
        {'outcome': 'taken'},
      ]),
    ]);
    final store = PostgresPersonLinkStore(connection);

    final set = await store.set(
      main: const UserId(_a),
      second: null,
      others: const [UserId(_b), UserId(_c)],
      by: const UserId(_a),
    );
    final taken = await store.set(
      main: const UserId(_c),
      second: const UserId(_b),
      others: const [],
      by: const UserId(_a),
    );

    expect((set as Ok<PersonLinkRefusal?>).value, isNull);
    expect((taken as Ok<PersonLinkRefusal?>).value, PersonLinkRefusal.taken);
    expect(connection.parameters.first, {
      'main': _a,
      'second': '',
      'others': '$_b,$_c',
      'by': _a,
    });
    expect(connection.parameters.last['second'], _b);
    expect(connection.parameters.last['others'], '');
    expect(connection.sql.first, contains('identity.set_person'));
  });

  test('an unknown answer is corrupt; unlink answers the count', () async {
    final connection = _Connection([
      Result.ok([
        {'outcome': 'what'},
      ]),
      Result.ok([
        {'unlinked': 3},
      ]),
    ]);
    final store = PostgresPersonLinkStore(connection);

    final odd = await store.set(
      main: const UserId(_a),
      second: null,
      others: const [UserId(_b)],
      by: const UserId(_a),
    );
    final unlinked = await store.unlink(const UserId(_a));

    expect((odd as Err<PersonLinkRefusal?>).error.code, 'identity.row_corrupt');
    expect((unlinked as Ok<int>).value, 3);
    expect(connection.sql.last, contains('identity.unlink_person'));
  });

  test('the name directory skips a malformed row', () async {
    final connection = _Connection([
      Result.ok([
        {'id': _a, 'email': 'a@t.io', 'display_name': 'عبدالرحمن المغربي'},
        {'id': 'nope', 'email': null, 'display_name': 'x'},
        {'id': _b, 'email': null, 'display_name': 'عبد الرحمن المغربي'},
      ]),
    ]);

    final result = await PostgresAccountNameDirectory(connection).all();

    final names = (result as Ok<List<AccountName>>).value;
    expect([for (final n in names) n.id.value], [_a, _b]);
    expect(names.last.email, isNull);
  });
}
