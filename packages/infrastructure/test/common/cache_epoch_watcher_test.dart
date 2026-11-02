import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The database's `ops.cache_epoch`, through the real reader's query.
final class _Db implements DbExecutor {
  Result<List<Map<String, dynamic>>> next = const Result.ok(
    <Map<String, dynamic>>[
      {'epoch': 7, 'source': null},
    ],
  );
  final List<String> asked = <String>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    asked.add(sql.trim());
    return next;
  }

  void epoch(int n, String source) => next = Result.ok(<Map<String, dynamic>>[
    {'epoch': n, 'source': source},
  ]);
}

/// A schedule store that counts its reads.
final class _Schedules implements FixtureScheduleRepository {
  int reads = 0;

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    reads++;
    return Result.ok(<FixtureSchedule>[
      for (final f in fixtures)
        FixtureSchedule.fromStored(
          fixture: f,
          homeTeam: 'A',
          awayTeam: 'B',
          kickoffAt: DateTime.utc(2026, 11, 3, 18),
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Db db;
  late _Schedules inner;
  late CachedFixtureScheduleRepository schedules;
  late CacheEpochWatcher watcher;
  const FixtureRef fixture = FixtureRef('11111111-1111-1111-1111-111111111111');

  setUp(() {
    db = _Db();
    inner = _Schedules();
    // Held for hours, as since script 192.
    schedules = CachedFixtureScheduleRepository(
      inner,
      ttl: const Duration(hours: 6),
    );
    watcher = CacheEpochWatcher(
      reader: PostgresCacheEpochReader(db),
      flush: schedules.forget,
    );
  });

  Future<void> readSchedule() async {
    await schedules.findByFixtures(const <FixtureRef>[fixture]);
  }

  test('the server names its sessions as 0194 expects', () {
    expect(serverApplicationName, 'nukhbaa-server');
  });

  test('the first reading is the baseline and drops nothing', () async {
    await readSchedule();
    expect((await watcher.check() as Ok<String?>).value, isNull);
    await readSchedule();
    expect(inner.reads, 1, reason: 'still held');
    expect(db.asked.single, contains('FROM ops.cache_epoch'));
  });

  test('an edit in the SQL Editor drops the held reads at the next '
      'reading, once', () async {
    await watcher.check();
    await readSchedule();
    db.epoch(8, 'competition.fixture_schedules by supabase/dashboard');

    final said = (await watcher.check() as Ok<String?>).value;
    expect(
      said,
      'epoch 8: competition.fixture_schedules by supabase/dashboard',
    );
    await readSchedule();
    expect(inner.reads, 2, reason: 'read again from the database');

    expect((await watcher.check() as Ok<String?>).value, isNull);
    await readSchedule();
    expect(inner.reads, 2, reason: 'the same epoch drops nothing');
  });

  test('a failed reading drops nothing and keeps the baseline', () async {
    await watcher.check();
    await readSchedule();
    db.next = const Result.err(AppError.transient('db.down', 'down'));
    expect(await watcher.check(), isA<Err<String?>>());
    await readSchedule();
    expect(inner.reads, 1);

    db.epoch(9, 'identity.users by psql');
    expect((await watcher.check() as Ok<String?>).value, isNotNull);
  });

  test('without the row (0194 not applied) nothing happens', () async {
    db.next = const Result.ok(<Map<String, dynamic>>[]);
    expect((await watcher.check() as Ok<String?>).value, isNull);
    expect((await watcher.check() as Ok<String?>).value, isNull);
  });
}
