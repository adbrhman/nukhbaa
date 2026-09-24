import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_frame_report_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = 'aaaaaaaa-0000-0000-0000-000000000001';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

/// Hermetic unit tests for the row mapping of the frame-report adapter.
/// The totals SQL itself is checked by hand against the live database.
void main() {
  test('record binds every field', () async {
    final connection = _FakeConnection(const Result.ok([]));
    final at = DateTime.utc(2026, 9, 24, 12);

    final result = await PostgresFrameReportRepository(connection).record(
      userId: const UserId(_user),
      report: const FrameReport(
        build: 'abc1234',
        platform: 'android',
        refreshRateHz: 120,
        frames: 1000,
        slowFrames: 30,
        frozenFrames: 1,
        worstFrameMs: 900,
      ),
      reportedAt: at,
    );

    expect(result.isOk, isTrue);
    expect(connection.sqls.single, contains('ops.frame_reports'));
    expect(connection.params.single, {
      'user_id': _user,
      'reported_at': at,
      'build': 'abc1234',
      'platform': 'android',
      'refresh_rate_hz': 120,
      'frames': 1000,
      'slow_frames': 30,
      'frozen_frames': 1,
      'worst_frame_ms': 900,
    });
  });

  test('totals map rows, overall first, empty window as zeros', () async {
    final at = DateTime.utc(2026, 9, 24, 9);
    final connection = _FakeConnection(
      Result.ok([
        {
          'build': null,
          'reports': 3,
          'users': 2,
          'frames': 6000,
          'slow_frames': 120,
          'frozen_frames': 2,
          'worst_frame_ms': 1200,
          'last_reported_at': at,
          'ord': 0,
        },
        {
          'build': 'abc1234',
          'reports': 3,
          'users': 2,
          'frames': 6000,
          'slow_frames': 120,
          'frozen_frames': 2,
          'worst_frame_ms': 1200,
          'last_reported_at': at,
          'ord': 1,
        },
      ]),
    );
    final since = DateTime.utc(2026, 9, 17, 12);

    final result = await PostgresFrameReportRepository(
      connection,
    ).totals(since: since, maxBuilds: 5);

    final rows = (result as Ok<List<FrameTotals>>).value;
    expect(rows.map((r) => r.build), [null, 'abc1234']);
    expect(rows.first.frames, 6000);
    expect(rows.first.slowFrames, 120);
    expect(rows.first.lastReportedAt, at);
    expect(connection.params.single, {'since': since, 'max_builds': 5});
  });

  test('a driver failure comes back as an error, never a throw', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.down', 'down')),
    );

    final result = await PostgresFrameReportRepository(
      connection,
    ).totals(since: DateTime.utc(2026), maxBuilds: 5);

    expect(result.isErr, isTrue);
  });
}
