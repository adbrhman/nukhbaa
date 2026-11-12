import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/media/postgres_crest_catalog.dart';
import 'package:infrastructure/src/media/supabase_crest_files.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '11111111-1111-4111-8111-111111111111';

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

Result<List<Map<String, dynamic>>> _list({bool enabled = true}) =>
    Result.ok(<Map<String, dynamic>>[
      {
        'clubs_enabled': enabled,
        'slug': 'arsenal',
        'object_path': 'clubs/arsenal.11111111.png',
        'status': 'active',
        'reason': null,
        'complainant': null,
        'changed_at': null,
      },
      {
        'clubs_enabled': enabled,
        'slug': 'milan',
        'object_path': 'clubs/milan.22222222.png',
        'status': 'hidden',
        'reason': 'شكوى',
        'complainant': 'x',
        'changed_at': DateTime.utc(2026, 11, 12),
      },
    ]);

/// Script 265: the adapter the composition root wires for the club crests.
/// Its SQL runs against the schema in
/// `supabase/tests/0210_club_crests_test.sql`.
void main() {
  test('reads the list once, holds it, and drops it on a write', () async {
    final connection = _Connection([
      _list(),
      Result.ok([
        {'moved': 1},
      ]),
      _list(enabled: false),
    ]);
    final catalog = PostgresCrestCatalog(connection);

    final first = await catalog.crests();
    final held = await catalog.crests();
    final moved = await catalog.setStatus(
      slug: 'arsenal',
      from: const {CrestStatus.active},
      to: CrestStatus.hidden,
      action: 'hidden',
      reason: 'شكوى',
      complainant: null,
      by: const UserId(_owner),
    );
    final fresh = await catalog.crests();

    final list = (first as Ok<CrestList>).value;
    expect(list.clubsEnabled, isTrue);
    expect(list.crests.last.status, CrestStatus.hidden);
    expect(list.crests.last.changedAt, DateTime.utc(2026, 11, 12));
    expect(identical((held as Ok<CrestList>).value, list), isTrue);
    expect((moved as Ok<bool>).value, isTrue);
    expect((fresh as Ok<CrestList>).value.clubsEnabled, isFalse);
    expect(connection.sql, hasLength(3));
    expect(connection.parameters[1], {
      'slug': 'arsenal',
      'from': 'active',
      'to': 'hidden',
      'action': 'hidden',
      'reason': 'شكوى',
      'complainant': '',
      'by': _owner,
    });
  });

  test('nothing moved is false; a bad status row is corrupt', () async {
    final connection = _Connection([
      Result.ok([
        {'moved': 0},
      ]),
      Result.ok([
        {
          'clubs_enabled': true,
          'slug': 'arsenal',
          'object_path': 'p',
          'status': 'gone',
        },
      ]),
    ]);
    final catalog = PostgresCrestCatalog(connection);

    final moved = await catalog.setStatus(
      slug: 'nope',
      from: const {CrestStatus.active, CrestStatus.hidden},
      to: CrestStatus.deleted,
      action: 'deleted',
      reason: 'x',
      complainant: 'y',
      by: const UserId(_owner),
    );
    final list = await catalog.crests();

    expect((moved as Ok<bool>).value, isFalse);
    expect(
      connection.parameters.first['from'],
      anyOf('active,hidden', 'hidden,active'),
    );
    expect((list as Err<CrestList>).error.code, 'media.row_corrupt');
  });

  test('the switch and the log', () async {
    final connection = _Connection([
      Result.ok([
        {'id': 7},
      ]),
      Result.ok([
        {
          'slug': null,
          'action': 'clubs_off',
          'reason': 'مراجعة',
          'complainant': null,
          'at': DateTime.utc(2026, 11, 12, 10),
        },
      ]),
    ]);
    final catalog = PostgresCrestCatalog(connection);

    final off = await catalog.setClubsEnabled(
      enabled: false,
      reason: 'مراجعة',
      by: const UserId(_owner),
    );
    final events = await catalog.events(limit: 10);

    expect(off, isA<Ok<void>>());
    expect(connection.parameters.first['enabled'], isFalse);
    expect((events as Ok<List<CrestEvent>>).value.single.action, 'clubs_off');
    expect(connection.parameters.last['limit'], 10);
  });

  test("the bucket's public address", () {
    expect(
      crestsPublicBase('abc'),
      'https://abc.supabase.co/storage/v1/object/public/crests/',
    );
  });
}
