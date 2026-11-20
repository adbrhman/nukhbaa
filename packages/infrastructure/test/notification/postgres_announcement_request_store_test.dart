import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_announcement_request_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

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

const String _id = '00000000-0220-4000-8220-0000000000a1';
const String _author = '00000000-0220-4000-8220-000000000001';

Map<String, dynamic> _row({String status = 'pending', Object? recipients}) =>
    <String, dynamic>{
      'id': _id,
      'author_id': _author,
      'author_name': 'مشرف',
      'title': 'تنبيه',
      'body': 'نص',
      'status': status,
      'created_at': DateTime.utc(2026, 11, 20, 9),
      'decided_at': status == 'pending' ? null : DateTime.utc(2026, 11, 20, 10),
      'recipients': recipients,
    };

// NK290_16
/// Script 290: the adapter the composition root wires for the held
/// announcements. Its table is checked by
/// `supabase/tests/0220_announcement_requests_test.sql`.
void main() {
  test('holds a request once, and reads it with its author', () async {
    final connection = _Connection([
      Result.ok([
        {'id': _id},
      ]),
      Result.ok([_row()]),
      const Result.ok([]),
      Result.ok([_row()]),
    ]);
    final store = PostgresAnnouncementRequestStore(connection);

    final first = await store.hold(
      id: const AnnouncementId(_id),
      author: const UserId(_author),
      title: 'تنبيه',
      body: 'نص',
    );
    final again = await store.hold(
      id: const AnnouncementId(_id),
      author: const UserId(_author),
      title: 'آخر',
      body: 'آخر',
    );

    final (AnnouncementRequest held, bool fresh) =
        (first as Ok<(AnnouncementRequest, bool)>).value;
    expect(fresh, isTrue);
    expect(held.authorName, 'مشرف');
    expect(held.status, AnnouncementRequestStatus.pending);
    expect((again as Ok<(AnnouncementRequest, bool)>).value.$2, isFalse);
    expect(connection.sql.first, contains('ON CONFLICT (id) DO NOTHING'));
    expect(connection.parameters.first['author'], _author);
  });

  test('reads the latest, a decided one with its recipients', () async {
    final connection = _Connection([
      Result.ok([_row(status: 'published', recipients: 12)]),
    ]);

    final result = await PostgresAnnouncementRequestStore(connection).latest();

    final AnnouncementRequest line =
        (result as Ok<List<AnnouncementRequest>>).value.single;
    expect(line.status, AnnouncementRequestStatus.published);
    expect(line.recipients, 12);
    expect(line.decidedAt, DateTime.utc(2026, 11, 20, 10));
    expect(connection.sql.single, contains("(r.status = 'pending') DESC"));
    expect(connection.parameters.single['limit'], 50);
  });

  test('decides only a pending request', () async {
    final connection = _Connection([
      Result.ok([
        {'id': _id},
      ]),
      const Result.ok([]),
    ]);
    final store = PostgresAnnouncementRequestStore(connection);

    final first = await store.decide(
      id: const AnnouncementId(_id),
      to: AnnouncementRequestStatus.rejected,
      by: const UserId(_author),
    );
    final second = await store.decide(
      id: const AnnouncementId(_id),
      to: AnnouncementRequestStatus.published,
      by: const UserId(_author),
      recipients: 3,
    );

    expect((first as Ok<bool>).value, isTrue);
    expect((second as Ok<bool>).value, isFalse);
    expect(connection.sql.first, contains("status = 'pending'"));
    expect(connection.parameters.first, {
      'id': _id,
      'to': 'rejected',
      'by': _author,
      'recipients': null,
    });
  });

  test('a row with an unknown status is corrupt', () async {
    final connection = _Connection([
      Result.ok([_row(status: 'sent')]),
    ]);

    final result = await PostgresAnnouncementRequestStore(
      connection,
    ).byId(const AnnouncementId(_id));

    expect(
      (result as Err<AnnouncementRequest?>).error.code,
      'notification.row_corrupt',
    );
  });
}
