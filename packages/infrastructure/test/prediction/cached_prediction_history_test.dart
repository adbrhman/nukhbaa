import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// A player's own history behind `GET /me/fixture-predictions` (script 138),
/// read through the real use-case, wired as the composition root wires it:
/// [ListMyFixturePredictions] over [CachedPredictionHistory] and a
/// [CachedFixtureScheduleRepository]; the player's own writes go through the
/// same [CachedPredictionHistory], as `SubmitFixturePrediction` is handed it.
/// On 2026-10-23 these two reads returned the most rows of all while the
/// Supabase egress quota was exceeded.

const _userA = 'aaaaaaaa-0000-4000-8000-000000000001';
const _userB = 'aaaaaaaa-0000-4000-8000-000000000002';
const _octA = 'bbbbbbbb-0000-4000-8000-0000000000a1';
const _octB = 'bbbbbbbb-0000-4000-8000-0000000000b1';
const _novA = 'bbbbbbbb-0000-4000-8000-0000000000a2';
const _f1 = 'ffffffff-0000-4000-8000-000000000001';
const _f2 = 'ffffffff-0000-4000-8000-000000000002';
const _f3 = 'ffffffff-0000-4000-8000-000000000003';
const _season = 'dddddddd-0000-4000-8000-000000000001';

AuthenticatedUser _player(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.user);

FixturePrediction _prediction(String id, String fixture, String participant) =>
    FixturePrediction.fromStored(
      id: PredictionId(id),
      fixture: FixtureRef(fixture),
      participantId: ParticipantId(participant),
      homeGoals: 1,
      awayGoals: 0,
    );

/// The predictions table, counting the history reads that reach it.
final class _Store implements FixturePredictionRepository {
  final Map<String, String> userOf = <String, String>{
    _octA: _userA,
    _octB: _userB,
    _novA: _userA,
  };
  final List<FixturePrediction> rows = <FixturePrediction>[];
  int historyReads = 0;
  int linkReads = 0;
  bool down = false;
  bool writesDown = false;

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async {
    historyReads++;
    if (down) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return Result.ok(<FixturePredictionView>[
      for (final FixturePrediction row in rows)
        if (userOf[row.participantId.value] == userId.value)
          FixturePredictionView(
            prediction: row,
            submittedAt: DateTime.utc(2026, 10, 23),
            seasonId: const SeasonId(_season),
          ),
    ]);
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    if (writesDown) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    rows.add(prediction);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    rows
      ..removeWhere((row) => row.id.value == prediction.id.value)
      ..add(prediction);
    return const Result.ok(null);
  }

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    linkReads++;
    return const Result.ok(null);
  }

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async => const Result.ok(null);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async => const Result.ok(<FixturePredictionView>[]);

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async =>
      const Result.ok(null);

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => const Result.ok(true);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok(<FixtureRef>[]);
}

/// The schedules table, counting the batched reads that reach it and the
/// fixtures each one asked for.
final class _Schedules implements FixtureScheduleRepository {
  int batchReads = 0;
  final List<List<String>> asked = <List<String>>[];

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    batchReads++;
    asked.add(<String>[
      for (final FixtureRef fixture in fixtures) fixture.value,
    ]);
    return const Result.ok(<FixtureSchedule>[]);
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async =>
      const Result.ok(null);
}

void main() {
  late DateTime clock;
  late _Store store;
  late _Schedules schedules;
  late CachedPredictionHistory history;
  late ListMyFixturePredictions listMine;

  setUp(() {
    clock = DateTime.utc(2026, 10, 23, 20);
    store = _Store()
      ..rows.addAll(<FixturePrediction>[
        _prediction('cccccccc-0000-4000-8000-000000000001', _f1, _octA),
        _prediction('cccccccc-0000-4000-8000-000000000002', _f1, _octB),
      ]);
    schedules = _Schedules();
    history = CachedPredictionHistory(store, now: () => clock);
    listMine = ListMyFixturePredictions(
      fixturePredictionRepository: history,
      fixtureScheduleRepository: CachedFixtureScheduleRepository(
        schedules,
        ttl: const Duration(minutes: 10),
        maxEntries: 512,
        now: () => clock,
      ),
    );
  });

  Future<List<String>> mine(String user) async {
    final Result<List<FixturePredictionView>> read = await listMine(
      principal: _player(user),
    );
    return <String>[
      for (final FixturePredictionView view
          in (read as Ok<List<FixturePredictionView>>).value)
        view.prediction.fixture.value,
    ];
  }

  test('reopening the history within 10 minutes reads nothing again', () async {
    expect(await mine(_userA), <String>[_f1]);
    clock = clock.add(const Duration(minutes: 9));
    expect(await mine(_userA), <String>[_f1]);
    expect(store.historyReads, 1);
    expect(schedules.batchReads, 1);

    clock = clock.add(const Duration(minutes: 2));
    expect(await mine(_userA), <String>[_f1]);
    expect(store.historyReads, 2);
    expect(schedules.batchReads, 2);
  });

  test('a player\'s own new prediction shows on the very next read, newest '
      'first, without reading any history again (script 141)', () async {
    await mine(_userA);
    await mine(_userB);
    clock = clock.add(const Duration(minutes: 1));
    await history.save(
      _prediction('cccccccc-0000-4000-8000-000000000003', _f2, _octA),
      clock,
    );
    expect(await mine(_userA), <String>[_f2, _f1]);
    expect(await mine(_userB), <String>[_f1]);
    expect(store.historyReads, 2);
  });

  test('the history read after a save is the one the database would give: '
      'goals, double, time and season (script 141)', () async {
    store.rows.add(
      _prediction('cccccccc-0000-4000-8000-000000000005', _f3, _octA),
    );
    await mine(_userA);
    clock = clock.add(const Duration(minutes: 1));
    const FixturePrediction amended = FixturePrediction.fromStored(
      id: PredictionId('cccccccc-0000-4000-8000-000000000001'),
      fixture: FixtureRef(_f1),
      participantId: ParticipantId(_octA),
      homeGoals: 3,
      awayGoals: 2,
      isDouble: true,
    );
    await history.update(amended, clock);
    final Result<List<FixturePredictionView>> read = await listMine(
      principal: _player(_userA),
    );
    final List<FixturePredictionView> views =
        (read as Ok<List<FixturePredictionView>>).value;
    expect(
      <String>[
        for (final FixturePredictionView view in views)
          view.prediction.fixture.value,
      ],
      <String>[_f1, _f3],
    );
    expect(views.first.prediction, amended);
    expect(views.first.submittedAt, clock);
    expect(views.first.seasonId, const SeasonId(_season));
    expect(store.historyReads, 1);
  });

  test('a failed write drops the history, which is read again', () async {
    await mine(_userA);
    store.writesDown = true;
    await history.save(
      _prediction('cccccccc-0000-4000-8000-000000000006', _f2, _octA),
      clock,
    );
    expect(await mine(_userA), <String>[_f1]);
    expect(store.historyReads, 2);
  });

  test('a history that grew by one prediction reads only that fixture\'s '
      'schedule, and a second player shares the schedules read (script '
      '141)', () async {
    await mine(_userA);
    expect(schedules.asked, <List<String>>[
      <String>[_f1],
    ]);
    await history.save(
      _prediction('cccccccc-0000-4000-8000-000000000003', _f2, _octA),
      clock,
    );
    await mine(_userA);
    await mine(_userB);
    expect(schedules.asked, <List<String>>[
      <String>[_f1],
      <String>[_f2],
    ]);
  });

  test('a first prediction in a new month (a participant not seen yet) drops '
      'every history', () async {
    await mine(_userA);
    await mine(_userB);
    await history.save(
      _prediction('cccccccc-0000-4000-8000-000000000004', _f3, _novA),
      clock,
    );
    expect(await mine(_userA), unorderedEquals(<String>[_f1, _f3]));
    await mine(_userB);
    expect(store.historyReads, 4);
  });

  test('a merge (forget) drops every history', () async {
    await mine(_userA);
    history.forget();
    await mine(_userA);
    expect(store.historyReads, 2);
  });

  test('a failure is not kept', () async {
    store.down = true;
    final Result<List<FixturePredictionView>> failed = await listMine(
      principal: _player(_userA),
    );
    expect(failed, isA<Err<List<FixturePredictionView>>>());
    store.down = false;
    expect(await mine(_userA), <String>[_f1]);
    expect(store.historyReads, 2);
  });

  test('the other reads pass straight through', () async {
    await history.findSeasonFixture(
      const SeasonId('dddddddd-0000-4000-8000-000000000001'),
      const FixtureRef(_f1),
    );
    await history.findSeasonFixture(
      const SeasonId('dddddddd-0000-4000-8000-000000000001'),
      const FixtureRef(_f1),
    );
    expect(store.linkReads, 2);
  });
}
