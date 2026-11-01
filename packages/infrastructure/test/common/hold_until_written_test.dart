import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Script 192: the reads that were still read whole every 20 to 60 seconds
/// (or on every request) are held until this server writes them -- a
/// fixture's predictions, a season's fixture list, the players' names and a
/// player's own points. Each is read through its real use-case, the caches
/// wired as the composition root wires them, and each write goes through
/// the real use-case that makes it: `SubmitFixturePrediction`,
/// `LinkFixtureToSeason`, `UpdateDisplayName`, `RecordFixtureResult` and
/// `ScoreFixture`. Between 25 October and 1 November 2026 these reads
/// returned about 4.2 million rows while the Supabase egress quota was
/// exceeded.

const _user = 'aaaaaaaa-0000-4000-8000-000000000001';
const _participant = 'bbbbbbbb-0000-4000-8000-000000000001';
const _other = 'bbbbbbbb-0000-4000-8000-000000000002';
const _competition = 'cccccccc-0000-4000-8000-000000000001';
const _season = 'dddddddd-0000-4000-8000-000000000001';
const _f1 = 'ffffffff-0000-4000-8000-000000000001';
const _f2 = 'ffffffff-0000-4000-8000-000000000002';
const _f4 = 'ffffffff-0000-4000-8000-000000000004';

const _hold = Duration(hours: 6);

const _player = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);
const _admin = AuthenticatedUser(
  userId: UserId('eeeeeeee-0000-4000-8000-000000000002'),
  role: PlatformRole.admin,
);
const _service = AuthenticatedUser(
  userId: UserId('eeeeeeee-0000-4000-8000-000000000001'),
  role: PlatformRole.service,
);

final class _Clock implements Clock {
  DateTime now = DateTime.utc(2026, 11, 1, 18);

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

CompetitionSeason _month() =>
    (CompetitionSeason.create(
              id: const SeasonId(_season),
              competitionId: const CompetitionId(_competition),
              label: '11/2026',
              startAt: DateTime.utc(2026, 11),
              endAt: DateTime.utc(2026, 12),
            )
            as Ok<CompetitionSeason>)
        .value;

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
  }) async => Result.ok(_month());

  @override
  Future<Result<CompetitionSeason>> findSeason(SeasonId id) async =>
      Result.ok(_month());

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
      joinedAt: DateTime.utc(2026, 11),
    ),
  );

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The predictions and season-links tables; every read is counted.
final class _Predictions
    implements FixturePredictionRepository, FixturePredictionTallyReader {
  final List<FixturePrediction> rows = <FixturePrediction>[];
  final List<String> links = <String>[_f1, _f2];
  final List<String> byFixtureAsked = <String>[];
  int seasonFixturesAsked = 0;

  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async => const Result.ok(<FixtureOutcomeTally>[]);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) async {
    seasonFixturesAsked++;
    return Result.ok(<FixtureRef>[
      for (final String id in links) FixtureRef(id),
    ]);
  }

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async => Result.ok(
    links.contains(fixture.value)
        ? SeasonFixture.fromStored(
            seasonId: seasonId,
            fixture: fixture,
            displayOrder: links.indexOf(fixture.value),
          )
        : null,
  );

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
    links.add(link.fixture.value);
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => Result.ok(links.remove(fixture.value));

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async {
    byFixtureAsked.add(fixture.value);
    return Result.ok(<FixturePredictionView>[
      for (final FixturePrediction row in rows)
        if (row.fixture.value == fixture.value)
          FixturePredictionView(
            prediction: row,
            submittedAt: DateTime.utc(2026, 11),
          ),
    ]);
  }

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
            submittedAt: DateTime.utc(2026, 11),
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
}

/// The schedules: f1 kicked off at 15:00, f2 and f4 kick off tomorrow.
final class _Schedules implements FixtureScheduleRepository {
  final Map<String, FixtureSchedule> rows = <String, FixtureSchedule>{
    _f1: FixtureSchedule.fromStored(
      fixture: const FixtureRef(_f1),
      homeTeam: 'A',
      awayTeam: 'B',
      kickoffAt: DateTime.utc(2026, 11, 1, 15),
    ),
    _f2: FixtureSchedule.fromStored(
      fixture: const FixtureRef(_f2),
      homeTeam: 'C',
      awayTeam: 'D',
      kickoffAt: DateTime.utc(2026, 11, 2, 20),
    ),
    _f4: FixtureSchedule.fromStored(
      fixture: const FixtureRef(_f4),
      homeTeam: 'E',
      awayTeam: 'F',
      kickoffAt: DateTime.utc(2026, 11, 2, 21),
    ),
  };

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async => Result.ok(<FixtureSchedule>[
    for (final FixtureRef f in fixtures)
      if (rows[f.value] case final FixtureSchedule schedule) schedule,
  ]);

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      Result.ok(rows[fixture.value]);

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    rows[schedule.fixture.value] = schedule;
    return const Result.ok(null);
  }
}

final class _Results implements FixtureResultRepository {
  final Map<String, FixtureResult> rows = <String, FixtureResult>{};

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async => Result.ok(<FixtureResult>[
    for (final FixtureRef f in fixtures)
      if (rows[f.value] case final FixtureResult result) result,
  ]);

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) async =>
      Result.ok(rows[fixture.value]);

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) async {
    rows[result.fixture.value] = result;
    return const Result.ok(null);
  }
}

final class _Scores implements FixtureScoreRepository {
  final List<ParticipantFixtureScore> rows = <ParticipantFixtureScore>[];

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    rows.addAll(scores);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async => Result.ok(<ParticipantFixtureScore>[
    for (final ParticipantFixtureScore row in rows)
      if (row.fixture.value == fixture.value) row,
  ]);

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) async => Result.ok(List<ParticipantFixtureScore>.of(rows));
}

/// `scoring.my_fixture_scores`: a row per prediction of the player with a
/// result or a score, built from the tables above; every read is counted.
final class _MyScores implements MyFixtureScoreReader {
  _MyScores(this.predictions, this.results, this.scores);

  final _Predictions predictions;
  final _Results results;
  final _Scores scores;
  int asked = 0;

  @override
  Future<Result<List<MyFixtureScore>>> listByUser(UserId userId) async {
    asked++;
    return Result.ok(<MyFixtureScore>[
      for (final FixturePrediction row in predictions.rows)
        if (row.participantId.value == _participant &&
            (results.rows.containsKey(row.fixture.value) ||
                scores.rows.any((s) => s.fixture.value == row.fixture.value)))
          MyFixtureScore(
            participantId: row.participantId,
            fixture: row.fixture,
            points: <int?>[
              for (final ParticipantFixtureScore s in scores.rows)
                if (s.fixture.value == row.fixture.value &&
                    s.participantId.value == row.participantId.value)
                  s.result.points,
            ].firstOrNull,
          ),
    ]);
  }
}

/// `identity.users` joined to the participants: one name per participant;
/// every names read is counted.
final class _Names implements ParticipantReader {
  final Map<String, String> byParticipant = <String, String>{
    _participant: 'player',
    _other: 'Sara',
  };
  int asked = 0;

  @override
  Future<Result<Map<String, String>>> findDisplayNames(
    List<ParticipantId> ids,
  ) async {
    asked++;
    return Result.ok(<String, String>{
      for (final ParticipantId id in ids)
        if (byParticipant[id.value] case final String name) id.value: name,
    });
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// `identity.users`: the player still carries the name from his e-mail.
final class _Users implements UserDirectory {
  _Users(this.names);

  final _Names names;
  User user = const User(
    id: UserId(_user),
    email: 'player@example.com',
    role: PlatformRole.user,
    status: UserStatus.active,
    displayName: 'player',
  );

  @override
  Future<Result<User?>> findUser(UserId id) async => Result.ok(user);

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async {
    user = User(
      id: user.id,
      email: user.email,
      role: user.role,
      status: user.status,
      displayName: displayName,
    );
    names.byParticipant[_participant] = displayName;
    return Result.ok(user);
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _Clock clock;
  late _Predictions predictions;
  late _Results results;
  late _Scores scores;
  late _MyScores myScores;
  late _Names names;
  late ListFixturePredictions board;
  late GetFixturePredictionDistribution split;
  late SubmitFixturePrediction submit;
  late UpdateDisplayName rename;
  late ListMyFixtureScores myPoints;
  late RecordFixtureResult recordResult;
  late ScoreFixture scoreFixture;
  late LinkFixtureToSeason link;
  late ListCurrentMonthFixtures feed;

  setUp(() {
    clock = _Clock();
    predictions = _Predictions()
      ..rows.addAll(const <FixturePrediction>[
        FixturePrediction.fromStored(
          id: PredictionId('cccccccc-0000-4000-8000-000000000001'),
          fixture: FixtureRef(_f1),
          participantId: ParticipantId(_participant),
          homeGoals: 2,
          awayGoals: 1,
        ),
        FixturePrediction.fromStored(
          id: PredictionId('cccccccc-0000-4000-8000-000000000002'),
          fixture: FixtureRef(_f1),
          participantId: ParticipantId(_other),
          homeGoals: 0,
          awayGoals: 0,
        ),
      ]);
    final _Schedules schedules = _Schedules();
    results = _Results();
    scores = _Scores();
    myScores = _MyScores(predictions, results, scores);
    names = _Names();
    DateTime now() => clock.now;

    // As the composition root wires them (script 192).
    final CachedParticipantReader participants = CachedParticipantReader(
      names,
      ttl: _hold,
      now: now,
    );
    final CachedUserDirectory directory = CachedUserDirectory(
      _Users(names),
      onNameChanged: participants.forgetNames,
      now: now,
    );
    final CachedFixturePredictionTallyReader tallies =
        CachedFixturePredictionTallyReader(predictions, ttl: _hold, now: now);
    final CachedMyFixtureScoreReader heldMyScores = CachedMyFixtureScoreReader(
      myScores,
      ttl: _hold,
      now: now,
    );
    final CachedFixtureScoreRepository scoreRepository =
        CachedFixtureScoreRepository(
          scores,
          ttl: _hold,
          onWritten: heldMyScores.forget,
          now: now,
        );
    final CachedFixtureScheduleRepository heldSchedules =
        CachedFixtureScheduleRepository(
          schedules,
          ttl: _hold,
          maxEntries: 8192,
          now: now,
        );
    final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
      predictions,
      linkTtl: _hold,
      predictionsTtl: _hold,
      now: now,
    );
    final CachedFixtureResultReads resultReads = CachedFixtureResultReads(
      results,
      ttl: _hold,
      onWritten: heldMyScores.forget,
      now: now,
    );
    final CachedPredictionHistory history = CachedPredictionHistory(
      predictions,
      ttl: _hold,
      onFixtureWritten: (FixtureRef fixture) {
        tallies.forgetFixture(fixture);
        reads.forgetFixture(fixture);
      },
      now: now,
    );

    board = ListFixturePredictions(
      competitionRepository: _Competitions(),
      fixturePredictionRepository: reads,
      fixtureScheduleRepository: heldSchedules,
      participantReader: participants,
      clock: clock,
    );
    split = GetFixturePredictionDistribution(
      fixturePredictionRepository: reads,
      // One call shows its split here: this tests the cache (M-2).
      shareMinimum: 1,
    );
    submit = SubmitFixturePrediction(
      fixturePredictionRepository: history,
      competitionRepository: _Competitions(),
      fixtureScheduleRepository: heldSchedules,
      idGenerator: _Ids(),
      clock: clock,
    );
    rename = UpdateDisplayName(userDirectory: directory);
    myPoints = ListMyFixtureScores(reader: heldMyScores);
    recordResult = RecordFixtureResult(
      resultRepository: resultReads,
      fixtureScheduleRepository: heldSchedules,
      clock: clock,
    );
    scoreFixture = ScoreFixture(
      fixturePredictionRepository: predictions,
      resultRepository: results,
      scoreRepository: scoreRepository,
      rulesetProvider: const ConfiguredRulesetProvider(),
      fixtureScheduleRepository: heldSchedules,
    );
    link = LinkFixtureToSeason(
      competitionRepository: _Competitions(),
      fixturePredictionRepository: reads,
    );
    feed = ListCurrentMonthFixtures(
      competitionRepository: _Competitions(),
      fixturePredictionRepository: reads,
      fixtureScheduleRepository: heldSchedules,
      clock: clock,
      predictionTallyReader: tallies,
      resultRepository: resultReads,
    );
  });

  Future<FixturePredictionReveal> readBoard() async {
    final Result<FixturePredictionReveal> read = await board(
      principal: _player,
      seasonId: _season,
      fixtureId: _f1,
    );
    return (read as Ok<FixturePredictionReveal>).value;
  }

  Future<FixturePredictionDistribution> readSplit() async {
    final Result<FixturePredictionDistribution> read = await split(
      principal: _player,
      seasonId: _season,
      fixtureId: _f2,
    );
    return (read as Ok<FixturePredictionDistribution>).value;
  }

  Future<List<MyFixtureScore>> readMyPoints() async {
    final Result<List<MyFixtureScore>> read = await myPoints(
      principal: _player,
    );
    return (read as Ok<List<MyFixtureScore>>).value;
  }

  Future<List<String>> readFeed() async {
    final Result<List<CurrentMonthFixtureEntry>> read = await feed(
      principal: _player,
    );
    return <String>[
      for (final CurrentMonthFixtureEntry entry
          in (read as Ok<List<CurrentMonthFixtureEntry>>).value)
        entry.fixture.fixtureId.value,
    ];
  }

  test('the predictions board read again five hours later reads neither the '
      'predictions nor the names again', () async {
    final FixturePredictionReveal first = await readBoard();
    expect(first.predictions, hasLength(2));
    expect(first.displayNames[_other], 'Sara');
    expect(predictions.byFixtureAsked, <String>[_f1]);
    expect(names.asked, 1);

    clock.now = clock.now.add(const Duration(hours: 5));
    final FixturePredictionReveal again = await readBoard();
    expect(again.predictions, hasLength(2));
    expect(again.displayNames[_participant], 'player');
    expect(predictions.byFixtureAsked, <String>[_f1]);
    expect(names.asked, 1);

    clock.now = clock.now.add(const Duration(hours: 2));
    await readBoard();
    expect(predictions.byFixtureAsked, <String>[_f1, _f1], reason: 'bound');
    expect(names.asked, 2);
  });

  test('a rename shows on the very next board read', () async {
    await readBoard();
    final Result<User> renamed = await rename(
      principal: _player,
      displayName: 'Khalid',
    );
    expect(renamed, isA<Ok<User>>());

    final FixturePredictionReveal after = await readBoard();
    expect(after.displayNames[_participant], 'Khalid');
    expect(after.displayNames[_other], 'Sara');
    expect(names.asked, 2);
    expect(predictions.byFixtureAsked, <String>[_f1], reason: 'unchanged');
  });

  test('a prediction sent before kickoff shows in the split at once, which '
      'is held until then', () async {
    expect((await readSplit()).homeWinPercentage, 0);
    clock.now = clock.now.add(const Duration(hours: 1));
    await readSplit();
    expect(predictions.byFixtureAsked, <String>[_f2]);

    final Result<FixturePredictionView> sent = await submit(
      principal: _player,
      seasonId: _season,
      fixtureId: _f2,
      homeGoals: 3,
      awayGoals: 1,
      isDouble: false,
    );
    expect(sent, isA<Ok<FixturePredictionView>>());

    expect((await readSplit()).homeWinPercentage, 100);
    expect(predictions.byFixtureAsked, <String>[_f2, _f2]);
  });

  test('my points are held for hours and read again after a recorded result '
      'and after scoring', () async {
    expect(await readMyPoints(), isEmpty);
    clock.now = clock.now.add(const Duration(hours: 5));
    expect(await readMyPoints(), isEmpty);
    expect(myScores.asked, 1);

    final Result<FixtureResult> recorded = await recordResult(
      principal: _service,
      fixtureId: _f1,
      homeGoals: 2,
      awayGoals: 1,
    );
    expect(recorded, isA<Ok<FixtureResult>>());
    final List<MyFixtureScore> afterResult = await readMyPoints();
    expect(afterResult, hasLength(1));
    expect(afterResult.single.points, isNull);
    expect(myScores.asked, 2);
    await readMyPoints();
    expect(myScores.asked, 2);

    final Result<List<ParticipantFixtureScore>> scored = await scoreFixture(
      principal: _admin,
      fixtureId: _f1,
    );
    expect(scored, isA<Ok<List<ParticipantFixtureScore>>>());
    final List<MyFixtureScore> afterScoring = await readMyPoints();
    expect(afterScoring.single.points, isNotNull);
    expect(afterScoring.single.points, greaterThan(0));
    expect(myScores.asked, 3);
  });

  test('a fixture the admin links shows in the month feed at once, and the '
      'list is held until then', () async {
    expect(await readFeed(), <String>[_f1, _f2]);
    clock.now = clock.now.add(const Duration(hours: 1));
    expect(await readFeed(), <String>[_f1, _f2]);
    expect(predictions.seasonFixturesAsked, 1);

    final Result<SeasonFixture> linked = await link(
      principal: _admin,
      seasonId: _season,
      fixtureId: _f4,
      displayOrder: 2,
    );
    expect(linked, isA<Ok<SeasonFixture>>());

    expect(await readFeed(), <String>[_f1, _f2, _f4]);
    expect(predictions.seasonFixturesAsked, 2);
  });
}
