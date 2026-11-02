import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _f1 = 'ffffffff-0000-4000-8000-000000000001';
const _f2 = 'ffffffff-0000-4000-8000-000000000002';
const _f3 = 'ffffffff-0000-4000-8000-000000000003';

FixtureSchedule _schedule(String fixture, DateTime kickoff) =>
    FixtureSchedule.fromStored(
      fixture: FixtureRef(fixture),
      homeTeam: 'Home $fixture',
      awayTeam: 'Away $fixture',
      kickoffAt: kickoff,
    );

/// The schedules table; each batched read records the fixtures it asked for.
final class _Schedules implements FixtureScheduleRepository {
  final Map<String, FixtureSchedule> rows = <String, FixtureSchedule>{};
  final List<List<String>> asked = <List<String>>[];
  bool writesDown = false;

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    asked.add(<String>[for (final FixtureRef f in fixtures) f.value]);
    return Result.ok(<FixtureSchedule>[
      for (final FixtureRef f in fixtures)
        if (rows[f.value] case final FixtureSchedule schedule) schedule,
    ]);
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      Result.ok(rows[fixture.value]);

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    if (writesDown) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    rows[schedule.fixture.value] = schedule;
    return const Result.ok(null);
  }
}

/// Script 201 (Supabase egress): a schedule write -- a kickoff the provider
/// moved, a fixture the sync registered, an admin's correction -- drops
/// that fixture alone. It used to drop every held schedule, so each write
/// read the whole month and every player's history again.
void main() {
  late _Schedules table;
  late CachedFixtureScheduleRepository schedules;

  setUp(() {
    table = _Schedules()
      ..rows[_f1] = _schedule(_f1, DateTime.utc(2026, 11, 2, 18))
      ..rows[_f2] = _schedule(_f2, DateTime.utc(2026, 11, 2, 20))
      ..rows[_f3] = _schedule(_f3, DateTime.utc(2026, 11, 3, 20));
    schedules = CachedFixtureScheduleRepository(table, maxEntries: 8192);
  });

  Future<Map<String, DateTime>> read() async {
    final Result<List<FixtureSchedule>> found = await schedules.findByFixtures(
      const <FixtureRef>[FixtureRef(_f1), FixtureRef(_f2), FixtureRef(_f3)],
    );
    return <String, DateTime>{
      for (final FixtureSchedule s
          in (found as Ok<List<FixtureSchedule>>).value)
        s.fixture.value: s.kickoffAt,
    };
  }

  test('a moved kickoff reads that fixture alone, and shows', () async {
    await read();
    expect(table.asked, <List<String>>[
      <String>[_f1, _f2, _f3],
    ]);

    await schedules.upsert(_schedule(_f2, DateTime.utc(2026, 11, 2, 21)));
    final Map<String, DateTime> after = await read();

    expect(after[_f2], DateTime.utc(2026, 11, 2, 21));
    expect(after[_f1], DateTime.utc(2026, 11, 2, 18));
    expect(table.asked.last, <String>[_f2]);
    expect(table.asked, hasLength(2));
  });

  test('a fixture registered after a read of it as absent shows', () async {
    const String fresh = 'ffffffff-0000-4000-8000-000000000004';
    await schedules.findByFixtures(const <FixtureRef>[FixtureRef(fresh)]);

    await schedules.upsert(_schedule(fresh, DateTime.utc(2026, 11, 4, 20)));
    final Result<List<FixtureSchedule>> found = await schedules.findByFixtures(
      const <FixtureRef>[FixtureRef(fresh)],
    );

    expect(
      (found as Ok<List<FixtureSchedule>>).value.single.kickoffAt,
      DateTime.utc(2026, 11, 4, 20),
    );
  });

  test('a failed write drops that fixture too: it may have landed', () async {
    await read();
    table.writesDown = true;

    await schedules.upsert(_schedule(_f3, DateTime.utc(2026, 11, 3, 21)));
    await read();

    expect(table.asked.last, <String>[_f3]);
  });

  test('a fixture id in upper case drops the same fixture', () async {
    await read();

    await schedules.upsert(
      _schedule(_f1.toUpperCase(), DateTime.utc(2026, 11, 2, 19)),
    );
    await read();

    expect(table.asked.last, <String>[_f1]);
  });

  test('hiding or merging (forget) still drops every schedule', () async {
    await read();

    schedules.forget();
    await read();

    expect(table.asked.last, <String>[_f1, _f2, _f3]);
  });
}
