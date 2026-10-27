import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The month's feed (`GET /feed/current-month-fixtures`) read through the
/// real use-case, its caches wired as the composition root wires them
/// (script 155): the schedules, the results and the win-share split are
/// held per fixture until a write drops them. A result is recorded through
/// the real [RecordFixtureResult] and a prediction sent through the real
/// [SubmitFixturePrediction], each handed the decorator the composition
/// root hands it. In the day and a half after script 141 these three reads
/// returned a whole month's rows every 20 to 60 seconds while the Supabase
/// egress quota was exceeded.

const _user = 'aaaaaaaa-0000-4000-8000-000000000001';
const _participant = 'bbbbbbbb-0000-4000-8000-000000000001';
const _competition = 'cccccccc-0000-4000-8000-000000000001';
const _season = 'dddddddd-0000-4000-8000-000000000001';
const _f1 = 'ffffffff-0000-4000-8000-000000000001';
const _f2 = 'ffffffff-0000-4000-8000-000000000002';
const _f3 = 'ffffffff-0000-4000-8000-000000000003';

const _player = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);
const _service = AuthenticatedUser(
  userId: UserId('eeeeeeee-0000-4000-8000-000000000001'),
  role: PlatformRole.service,
);

final class _Clock implements Clock {
  DateTime now = DateTime.utc(2026, 10, 27, 18);

  @override
  DateTime nowUtc() => now;
}

final class _Ids implements IdGenerator {
  int next = 0;

  @override
  String newUuid() {
    next++;
    return '99999999-0000-4000-8000-${next.toString().padLeft(12, '0')}';
  }
}

final class _Competitions implements CompetitionRepository {
  @override
  Future<Result<List<Competition>>> listCompetitions() async =>
      Result.ok(<Competition>[
        (Competition.create(
                  id: const CompetitionId(_competition),
                  name: 'Month',
                  format: FormatType.footballScoreline,
                  visibility: CompetitionVisibility.public,
                )
                as Ok<Competition>)
            .value,
      ]);

  @override
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  }) async => Result.ok(
    (CompetitionSeason.create(
              id: const SeasonId(_season),
              competitionId: const CompetitionId(_competition),
              label: '10/2026',
              startAt: DateTime.utc(2026, 10),
              endAt: DateTime.utc(2026, 11),
            )
            as Ok<CompetitionSeason>)
        .value,
  );

  @override
  Future<Result<Participant?>> findParticipant(
    SeasonId seasonId,
    UserId userId,
  ) async => Result.ok(
    Participant.fromStored(
      id: const ParticipantId(_participant),
      seasonId: seasonId,
      userId: userId,
      status: ParticipantStatus.active,
      joinedAt: DateTime.utc(2026, 10),
    ),
  );

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The predictions table and the grouped split read over it; each split
/// read records the fixtures it asked for.
final class _Predictions
    implements FixturePredictionRepository, FixturePredictionTallyReader {
  final List<FixturePrediction> rows = <FixturePrediction>[];
  final List<List<String>> tallyAsked = <List<String>>[];

  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    tallyAsked.add(<String>[for (final FixtureRef f in fixtures) f.value]);
    return Result.ok(<FixtureOutcomeTally>[
      for (final FixtureRef fixture in fixtures)
        if (rows.any((r) => r.fixture.value == fixture.value))
          FixtureOutcomeTally(
            fixture: fixture,
            homeWins: rows
                .where(
                  (r) =>
                      r.fixture.value == fixture.value &&
                      r.homeGoals > r.awayGoals,
                )
                .length,
            awayWins: rows
                .where(
                  (r) =>
                      r.fixture.value == fixture.value &&
                      r.homeGoals < r.awayGoals,
                )
                .length,
            draws: rows
                .where(
                  (r) =>
                      r.fixture.value == fixture.value &&
                      r.homeGoals == r.awayGoals,
                )
                .length,
          ),
    ]);
  }

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok(<FixtureRef>[
    FixtureRef(_f1),
    FixtureRef(_f2),
    FixtureRef(_f3),
  ]);

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async => Result.ok(
    SeasonFixture.fromStored(
      seasonId: seasonId,
      fixture: fixture,
      displayOrder: 0,
    ),
  );

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async {
    for (final FixturePrediction row in rows) {
      if (row.fixture.value == fixture.value &&
          row.participantId.value == participantId.value) {
        return Result.ok(
          FixturePredictionView(
            prediction: row,
            submittedAt: DateTime.utc(2026, 10, 27),
          ),
        );
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    rows.add(prediction);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    rows
      ..removeWhere((r) => r.id.value == prediction.id.value)
      ..add(prediction);
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok(<FixturePredictionView>[]);

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
}

/// The schedules table; each batched read records the fixtures it asked for.
final class _Schedules implements FixtureScheduleRepository {
  final Map<String, FixtureSchedule> rows = <String, FixtureSchedule>{
    _f1: FixtureSchedule.fromStored(
      fixture: const FixtureRef(_f1),
      homeTeam: 'A',
      awayTeam: 'B',
      kickoffAt: DateTime.utc(2026, 10, 27, 15),
    ),
    _f2: FixtureSchedule.fromStored(
      fixture: const FixtureRef(_f2),
      homeTeam: 'C',
      awayTeam: 'D',
      kickoffAt: DateTime.utc(2026, 10, 27, 16),
    ),
    _f3: FixtureSchedule.fromStored(
      fixture: const FixtureRef(_f3),
      homeTeam: 'E',
      awayTeam: 'F',
      kickoffAt: DateTime.utc(2026, 10, 28, 20),
    ),
  };
  final List<List<String>> asked = <List<String>>[];

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
    rows[schedule.fixture.value] = schedule;
    return const Result.ok(null);
  }
}

/// The results table; each batched read records the fixtures it asked for.
final class _Results implements FixtureResultRepository {
  final Map<String, FixtureResult> rows = <String, FixtureResult>{};
  final List<List<String>> asked = <List<String>>[];

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    asked.add(<String>[for (final FixtureRef f in fixtures) f.value]);
    return Result.ok(<FixtureResult>[
      for (final FixtureRef f in fixtures)
        if (rows[f.value] case final FixtureResult result) result,
    ]);
  }

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) async =>
      Result.ok(rows[fixture.value]);

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) async {
    rows[result.fixture.value] = result;
    return const Result.ok(null);
  }
}

void main() {
  late _Clock clock;
  late _Predictions predictions;
  late _Schedules schedules;
  late _Results results;
  late CachedFixturePredictionTallyReader tallies;
  late CachedFixtureScheduleRepository heldSchedules;
  late ListCurrentMonthFixtures feed;
  late RecordFixtureResult recordResult;
  late SubmitFixturePrediction submit;

  setUp(() {
    clock = _Clock();
    predictions = _Predictions()
      ..rows.add(
        const FixturePrediction.fromStored(
          id: PredictionId('cccccccc-0000-4000-8000-0000000000f3'),
          fixture: FixtureRef(_f3),
          participantId: ParticipantId('bbbbbbbb-0000-4000-8000-000000000002'),
          homeGoals: 2,
          awayGoals: 0,
        ),
      );
    schedules = _Schedules();
    results = _Results()
      ..rows[_f1] = const FixtureResult.fromStored(
        fixture: FixtureRef(_f1),
        homeGoals: 1,
        awayGoals: 1,
      );
    DateTime now() => clock.now;
    // As the composition root wires them.
    tallies = CachedFixturePredictionTallyReader(predictions, now: now);
    heldSchedules = CachedFixtureScheduleRepository(
      schedules,
      maxEntries: 8192,
      now: now,
    );
    final CachedFixtureResultReads resultReads = CachedFixtureResultReads(
      results,
      now: now,
    );
    final CachedPredictionHistory history = CachedPredictionHistory(
      predictions,
      onFixtureWritten: tallies.forgetFixture,
      now: now,
    );
    feed = ListCurrentMonthFixtures(
      competitionRepository: _Competitions(),
      fixturePredictionRepository: CachedFixturePredictionReads(
        predictions,
        now: now,
      ),
      fixtureScheduleRepository: heldSchedules,
      clock: clock,
      predictionTallyReader: tallies,
      resultRepository: resultReads,
    );
    recordResult = RecordFixtureResult(
      resultRepository: resultReads,
      fixtureScheduleRepository: heldSchedules,
      clock: clock,
    );
    submit = SubmitFixturePrediction(
      fixturePredictionRepository: history,
      competitionRepository: _Competitions(),
      fixtureScheduleRepository: heldSchedules,
      idGenerator: _Ids(),
      clock: clock,
    );
  });

  Future<Map<String, CurrentMonthFixtureEntry>> readFeed() async {
    final Result<List<CurrentMonthFixtureEntry>> read = await feed(
      principal: _player,
    );
    return <String, CurrentMonthFixtureEntry>{
      for (final CurrentMonthFixtureEntry entry
          in (read as Ok<List<CurrentMonthFixtureEntry>>).value)
        entry.fixture.fixtureId.value: entry,
    };
  }

  test('the feed read again within 30 minutes reads no schedule, result or '
      'split again', () async {
    final Map<String, CurrentMonthFixtureEntry> first = await readFeed();
    expect(first.keys, <String>[_f1, _f2, _f3]);
    expect(first[_f1]!.resultHomeGoals, 1);
    expect(first[_f3]!.totalPredictions, 1);
    expect(schedules.asked, hasLength(1));
    expect(results.asked, hasLength(1));
    expect(predictions.tallyAsked, hasLength(1));

    clock.now = clock.now.add(const Duration(minutes: 29));
    final Map<String, CurrentMonthFixtureEntry> again = await readFeed();
    expect(again[_f1]!.resultHomeGoals, 1);
    expect(again[_f3]!.totalPredictions, 1);
    expect(schedules.asked, hasLength(1));
    expect(results.asked, hasLength(1));
    expect(predictions.tallyAsked, hasLength(1));

    clock.now = clock.now.add(const Duration(minutes: 2));
    await readFeed();
    expect(schedules.asked, hasLength(2), reason: 'expired after the ttl');
    expect(results.asked, hasLength(2));
    expect(predictions.tallyAsked, hasLength(2));
  });

  test('a result recorded by the provider sync shows on the very next feed '
      'read, which reads only that fixture\'s result', () async {
    await readFeed();
    final Result<FixtureResult> recorded = await recordResult(
      principal: _service,
      fixtureId: _f2,
      homeGoals: 3,
      awayGoals: 0,
    );
    expect(recorded, isA<Ok<FixtureResult>>());

    final Map<String, CurrentMonthFixtureEntry> next = await readFeed();
    expect(next[_f2]!.resultHomeGoals, 3);
    expect(next[_f2]!.resultAwayGoals, 0);
    expect(next[_f1]!.resultHomeGoals, 1);
    expect(results.asked.last, <String>[_f2]);
    expect(schedules.asked, hasLength(1));
  });

  test('a prediction sent moves that fixture\'s split on the very next feed '
      'read, which reads only that fixture\'s split', () async {
    expect((await readFeed())[_f3]!.totalPredictions, 1);
    final Result<FixturePredictionView> sent = await submit(
      principal: _player,
      seasonId: _season,
      fixtureId: _f3,
      homeGoals: 0,
      awayGoals: 1,
    );
    expect(sent, isA<Ok<FixturePredictionView>>());

    final CurrentMonthFixtureEntry f3 = (await readFeed())[_f3]!;
    expect(f3.totalPredictions, 2);
    expect(f3.homeOutcomeShare, 50);
    expect(f3.awayOutcomeShare, 50);
    expect(predictions.tallyAsked.last, <String>[_f3]);

    // An amendment moves it again.
    await submit(
      principal: _player,
      seasonId: _season,
      fixtureId: _f3,
      homeGoals: 1,
      awayGoals: 1,
    );
    final CurrentMonthFixtureEntry amended = (await readFeed())[_f3]!;
    expect(amended.totalPredictions, 2);
    expect(amended.drawOutcomeShare, 50);
    expect(predictions.tallyAsked, hasLength(3));
  });

  test('a merge (forget) reads every split again; a kickoff corrected '
      'through the schedules shows on the next read', () async {
    await readFeed();
    tallies.forget();
    await readFeed();
    expect(predictions.tallyAsked.last, <String>[_f1, _f2, _f3]);

    await heldSchedules.upsert(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_f3),
        homeTeam: 'E',
        awayTeam: 'F',
        kickoffAt: DateTime.utc(2026, 10, 28, 21),
      ),
    );
    final CurrentMonthFixtureEntry f3 = (await readFeed())[_f3]!;
    expect(f3.fixture.kickoffAt, DateTime.utc(2026, 10, 28, 21));
  });
}
