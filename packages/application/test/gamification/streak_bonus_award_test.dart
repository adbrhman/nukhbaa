import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../ledger/fakes.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';

const String _seasonId = '33333333-3333-3333-3333-333333333333';
const String _userId = 'user-1';
const String _participantId = 'participant-1';

void main() {
  group('streak bonus, through SubmitFixturePrediction', () {
    test('pays nothing before the seventh consecutive completed day', () async {
      final world = _World(matchDays: _days(1, 8));

      for (var day = 1; day <= 6; day++) {
        await world.submit(day);
      }

      expect(await world.bonuses(), isEmpty);
    });

    test('pays 5 on the submission that completes the seventh day, '
        'stamped with the same instant as the completion event', () async {
      final world = _World(matchDays: _days(1, 8));

      for (var day = 1; day <= 7; day++) {
        final result = await world.submit(day);
        expect(result, isA<Ok<FixturePredictionView>>());
      }

      final bonuses = await world.bonuses();
      expect(bonuses, hasLength(1));
      final bonus = bonuses.single;
      expect(bonus.kind, EntryKind.streakBonus);
      expect(bonus.amount, 5);
      expect(bonus.sourceRef, 'streak:7');
      // Stored against the fixture whose prediction completed the day.
      expect(bonus.fixture, FixtureRef(_fixtureId(7)));
      expect(bonus.participantId, const ParticipantId(_participantId));
      // One `now` per submission: the ledger entry and the gamification
      // event that completed the day carry the very same instant.
      expect(bonus.occurredAt, _morning(7));
      final completion = world.events.recorded.lastWhere(
        (event) => event.type == GamificationEventType.dailyChallengeCompleted,
      );
      expect(completion.occurredAt, bonus.occurredAt);
    });

    test('pays each rung once: later completed days add nothing', () async {
      final world = _World(matchDays: _days(1, 9));

      for (var day = 1; day <= 9; day++) {
        await world.submit(day);
      }

      final bonuses = await world.bonuses();
      expect(bonuses, hasLength(1));
      expect(bonuses.single.sourceRef, 'streak:7');
    });

    test('pays the 14 rung on top of the 7 rung: 5 then 10', () async {
      final world = _World(matchDays: _days(1, 14));

      for (var day = 1; day <= 14; day++) {
        await world.submit(day);
      }

      final bonuses = await world.bonuses();
      expect(bonuses.map((entry) => entry.sourceRef), <String>[
        'streak:7',
        'streak:14',
      ]);
      expect(bonuses.map((entry) => entry.amount), <int>[5, 10]);
    });

    test('one missed match day ends the run, so nothing is paid', () async {
      final world = _World(matchDays: _days(1, 8));

      // Days 1-3, a gap on day 4, then 5-8: the run is 4 long, not 7.
      for (final day in <int>[1, 2, 3, 5, 6, 7, 8]) {
        await world.submit(day);
      }

      expect(await world.bonuses(), isEmpty);
    });

    test('a bonus whose write failed is caught up on the next completed day, '
        'and the prediction is saved either way', () async {
      final world = _World(matchDays: _days(1, 8));
      for (var day = 1; day <= 6; day++) {
        await world.submit(day);
      }

      // The ledger is down at the moment the seventh day completes.
      world.ledger.failNextWith(
        const AppError.transient('ledger.db_down', 'ledger is down'),
      );
      final seventh = await world.submit(7);

      expect(seventh, isA<Ok<FixturePredictionView>>());
      expect(world.predictions.count, 7);
      expect(await world.bonuses(), isEmpty);

      // The run is 8 long on the next completed day, so `>=` pays the 7 rung
      // then, against the fixture that completed that day.
      await world.submit(8);

      final bonuses = await world.bonuses();
      expect(bonuses, hasLength(1));
      expect(bonuses.single.sourceRef, 'streak:7');
      expect(bonuses.single.amount, 5);
      expect(bonuses.single.fixture, FixtureRef(_fixtureId(8)));
    });

    test('amending a prediction never consults the bonus', () async {
      final world = _World(matchDays: _days(1, 8));
      for (var day = 1; day <= 6; day++) {
        await world.submit(day);
      }
      world.ledger.failNextWith(
        const AppError.transient('ledger.db_down', 'ledger is down'),
      );
      await world.submit(7);

      // Day 7 is still open; an amend rewrites a score the participant
      // already had, so it cannot have completed anything.
      final amended = await world.submit(7, home: 3, away: 3);

      expect(amended, isA<Ok<FixturePredictionView>>());
      expect(await world.bonuses(), isEmpty);
    });
  });

  group('AwardStreakBonus', () {
    late FakeFixtureLedgerRepository ledger;
    late _SequentialIdGenerator ids;
    const participant = ParticipantId(_participantId);
    final fixture = FixtureRef(_fixtureId(1));
    final now = DateTime.utc(2026, 8, 31, 10);

    AwardStreakBonus awardFor(
      int streakDays, {
      FixtureLedgerRepository? over,
      StreakRepository? streaks,
    }) => AwardStreakBonus(
      getMyStreak: GetMyStreak(
        streaks: streaks ?? _ScriptedStreaks.completed(streakDays),
        clock: FixedClock(now),
      ),
      fixtureLedgerRepository: over ?? ledger,
      idGenerator: ids,
    );

    Future<Result<List<FixturePointEntry>>> pay(
      AwardStreakBonus award, {
      ParticipantId? forParticipant,
    }) => award(
      principal: userPrincipal(_userId),
      participantId: forParticipant ?? participant,
      fixture: fixture,
      now: now,
    );

    setUp(() {
      ledger = FakeFixtureLedgerRepository();
      // One generator per test, shared by every award in it: each entry needs
      // its own id, or the in-memory ledger would overwrite the earlier one.
      ids = _SequentialIdGenerator();
    });

    test('pays every rung the run has reached, lowest first', () async {
      final result = await pay(awardFor(30));

      final paid = (result as Ok<List<FixturePointEntry>>).value;
      expect(paid.map((entry) => entry.sourceRef), <String>[
        'streak:7',
        'streak:14',
        'streak:30',
      ]);
      expect(paid.map((entry) => entry.amount), <int>[5, 10, 20]);
      expect(paid.every((entry) => entry.occurredAt == now), isTrue);
      expect(ledger.count, 3);
    });

    test('pays nothing for a run shorter than the first rung', () async {
      final result = await pay(awardFor(6));

      expect((result as Ok<List<FixturePointEntry>>).value, isEmpty);
      expect(ledger.count, 0);
    });

    test('skips a rung the ledger already holds', () async {
      await pay(awardFor(7));
      expect(ledger.count, 1);

      final again = await pay(awardFor(14));

      final paid = (again as Ok<List<FixturePointEntry>>).value;
      expect(paid.map((entry) => entry.sourceRef), <String>['streak:14']);
      expect(ledger.count, 2);
    });

    test('evaluating twice in a row appends nothing the second time', () async {
      await pay(awardFor(14));
      final second = await pay(awardFor(14));

      expect((second as Ok<List<FixturePointEntry>>).value, isEmpty);
      expect(ledger.count, 2);
    });

    test(
      'a rung is scoped to its participant: a new season is paid again',
      () async {
        await pay(awardFor(7));

        final otherSeason = await pay(
          awardFor(7),
          forParticipant: const ParticipantId('participant-2'),
        );

        final paid = (otherSeason as Ok<List<FixturePointEntry>>).value;
        expect(paid.map((entry) => entry.sourceRef), <String>['streak:7']);
        expect(ledger.count, 2);
      },
    );

    test(
      'treats ledger.already_posted from a concurrent grant as paid',
      () async {
        final racing = _LedgerLosingTheRace(ledger);

        final result = await pay(awardFor(14, over: racing));

        expect(result, isA<Ok<List<FixturePointEntry>>>());
        expect((result as Ok<List<FixturePointEntry>>).value, isEmpty);
        expect(racing.appendAttempts, 2);
      },
    );

    test('propagates any other ledger failure', () async {
      final result = await pay(
        awardFor(7, over: _LedgerRefusingWrites(ledger)),
      );

      expect(result, isA<Err<List<FixturePointEntry>>>());
      expect(
        (result as Err<List<FixturePointEntry>>).error.code,
        'ledger.db_down',
      );
    });

    test('propagates a streak read failure and writes nothing', () async {
      final result = await pay(awardFor(7, streaks: _FailingStreaks()));

      expect(result, isA<Err<List<FixturePointEntry>>>());
      expect(ledger.count, 0);
    });

    test('refuses a non-UTC instant instead of writing it', () async {
      final result = await awardFor(7)(
        principal: userPrincipal(_userId),
        participantId: participant,
        fixture: fixture,
        now: DateTime(2026, 8, 31, 10),
      );

      expect(result, isA<Err<List<FixturePointEntry>>>());
      expect(ledger.count, 0);
    });
  });
}

// ---------------------------------------------------------------------------
// The world the real entry point runs in: one fixture per Riyadh match day in
// August 2026, kicking off 20:00 UTC (23:00 Riyadh, the same calendar day).
// ---------------------------------------------------------------------------

List<int> _days(int first, int last) => <int>[
  for (var day = first; day <= last; day++) day,
];

String _fixtureId(int day) =>
    '00000000-0000-0000-0000-0000000000${day.toString().padLeft(2, '0')}';

DateTime _kickoff(int day) => DateTime.utc(2026, 8, day, 20);

DateTime _morning(int day) => DateTime.utc(2026, 8, day, 10);

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Wires the REAL [SubmitFixturePrediction] to real use-cases and in-memory
/// ports, so a test drives the feature from its actual entry point:
/// submission -> daily completion -> streak -> bonus -> ledger.
final class _World {
  _World({required List<int> matchDays}) {
    for (final day in matchDays) {
      predictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: const SeasonId(_seasonId),
                  fixture: FixtureRef(_fixtureId(day)),
                  displayOrder: day,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: FixtureRef(_fixtureId(day)),
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
          kickoffAt: _kickoff(day),
        ),
      );
    }
    competition.seedParticipant(
      Participant.fromStored(
        id: const ParticipantId(_participantId),
        seasonId: const SeasonId(_seasonId),
        userId: const UserId(_userId),
        status: ParticipantStatus.active,
        joinedAt: DateTime.utc(2026),
      ),
    );

    clock = _MutableClock(_morning(matchDays.first));
    final ids = _SequentialIdGenerator();
    final streaks = _EventBackedStreaks(
      events: events,
      matchDays: <DateTime>[
        for (final day in matchDays) DateTime.utc(2026, 8, day),
      ],
    );
    useCase = SubmitFixturePrediction(
      fixturePredictionRepository: predictions,
      competitionRepository: competition,
      fixtureScheduleRepository: schedules,
      idGenerator: ids,
      clock: clock,
      gamificationEventSink: events,
      dailyChallengeRepository: _DailyChallenges(predictions, matchDays),
      awardStreakBonus: AwardStreakBonus(
        getMyStreak: GetMyStreak(streaks: streaks, clock: clock),
        fixtureLedgerRepository: ledger,
        idGenerator: ids,
      ),
    );
  }

  final FakeFixturePredictionRepository predictions =
      FakeFixturePredictionRepository();
  final FakeCompetitionRepository competition = FakeCompetitionRepository();
  final FakeFixtureScheduleRepository schedules =
      FakeFixtureScheduleRepository();
  final FakeFixtureLedgerRepository ledger = FakeFixtureLedgerRepository();
  final _RecordingGamificationEventSink events =
      _RecordingGamificationEventSink();
  late final _MutableClock clock;
  late final SubmitFixturePrediction useCase;

  /// Submits (or amends) the prediction for [day]'s fixture at 10:00 UTC that
  /// same day, well before its 20:00 UTC kickoff.
  Future<Result<FixturePredictionView>> submit(
    int day, {
    int home = 1,
    int away = 0,
  }) {
    clock.now = _morning(day);
    return useCase(
      principal: userPrincipal(_userId),
      seasonId: _seasonId,
      fixtureId: _fixtureId(day),
      homeGoals: home,
      awayGoals: away,
    );
  }

  /// The `streak_bonus` entries on the participant's ledger, in stream order.
  Future<List<FixturePointEntry>> bonuses() async {
    final result = await ledger.listEntries(
      const ParticipantId(_participantId),
    );
    return <FixturePointEntry>[
      for (final entry in (result as Ok<List<FixturePointEntry>>).value)
        if (entry.kind == EntryKind.streakBonus) entry,
    ];
  }
}

final class _MutableClock implements Clock {
  _MutableClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// Unique, valid UUIDs: every entry and event needs its own id, and the
/// scripted generator in `fakes.dart` repeats its last one.
final class _SequentialIdGenerator implements IdGenerator {
  int _next = 1;

  @override
  String newUuid() {
    final n = _next++;
    return 'aaaaaaaa-0000-0000-0000-${n.toString().padLeft(12, '0')}';
  }
}

final class _RecordingGamificationEventSink implements GamificationEventSink {
  final List<GamificationEvent> recorded = <GamificationEvent>[];

  @override
  Future<Result<void>> record(GamificationEvent event) async {
    recorded.add(event);
    return const Result.ok(null);
  }
}

/// Coverage of a one-fixture match day, read from the prediction store the
/// use-case just wrote to.
final class _DailyChallenges implements DailyChallengeRepository {
  _DailyChallenges(this._predictions, this._matchDays);

  final FakeFixturePredictionRepository _predictions;
  final List<int> _matchDays;

  @override
  Future<Result<DailyChallengeProgress>> progressOn({
    required SeasonId seasonId,
    required ParticipantId participantId,
    required DateTime day,
  }) async {
    if (!_matchDays.contains(day.day)) {
      return const Result.ok(DailyChallengeProgress(total: 0, predicted: 0));
    }
    final found = await _predictions.findByFixtureAndParticipant(
      FixtureRef(_fixtureId(day.day)),
      participantId,
    );
    final predicted = found is Ok<FixturePredictionView?> && found.value != null
        ? 1
        : 0;
    return Result.ok(DailyChallengeProgress(total: 1, predicted: predicted));
  }
}

/// The streak read, derived from the recorded completion events exactly as
/// the SQL adapter derives it from `gamification.events`.
final class _EventBackedStreaks implements StreakRepository {
  _EventBackedStreaks({required this.events, required this.matchDays});

  final _RecordingGamificationEventSink events;
  final List<DateTime> matchDays;

  @override
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  }) async {
    final days = <DateTime>[
      for (final day in matchDays)
        if (!day.isAfter(upToDay)) day,
    ]..sort((a, b) => b.compareTo(a));
    return Result.ok(<MatchDayCompletion>[
      for (final day in days.take(limitDays))
        MatchDayCompletion(
          day: day,
          completed: events.recorded.any(
            (event) =>
                event.type == GamificationEventType.dailyChallengeCompleted &&
                event.userId == userId &&
                event.payload['day'] == _iso(day),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Collaborators for the AwardStreakBonus unit tests.
// ---------------------------------------------------------------------------

/// A calendar of [days] completed match days ending on 2026-08-31, newest
/// first, so the run is exactly [days] long.
final class _ScriptedStreaks implements StreakRepository {
  _ScriptedStreaks.completed(this.days);

  final int days;

  @override
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  }) async => Result.ok(<MatchDayCompletion>[
    for (var i = 0; i < days; i++)
      MatchDayCompletion(day: DateTime.utc(2026, 8, 31 - i), completed: true),
  ]);
}

final class _FailingStreaks implements StreakRepository {
  @override
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  }) async => const Result.err(
    AppError.transient('streak.db_down', 'streak store is down'),
  );
}

/// A ledger that reads normally but loses every append to a concurrent
/// writer: what the adapter reports when the partial unique index refuses.
final class _LedgerLosingTheRace implements FixtureLedgerRepository {
  _LedgerLosingTheRace(this._inner);

  final FakeFixtureLedgerRepository _inner;
  int appendAttempts = 0;

  @override
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  ) async {
    appendAttempts++;
    return const Result.err(
      AppError.invariant(
        'ledger.already_posted',
        'This streak bonus was already granted',
      ),
    );
  }

  @override
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  ) => _inner.listEntries(participantId);

  @override
  Future<Result<List<FixturePointEntry>>> findByFixture(FixtureRef fixture) =>
      _inner.findByFixture(fixture);
}

/// A ledger that reads normally but cannot write.
final class _LedgerRefusingWrites implements FixtureLedgerRepository {
  _LedgerRefusingWrites(this._inner);

  final FakeFixtureLedgerRepository _inner;

  @override
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  ) async =>
      const Result.err(AppError.transient('ledger.db_down', 'ledger is down'));

  @override
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  ) => _inner.listEntries(participantId);

  @override
  Future<Result<List<FixturePointEntry>>> findByFixture(FixtureRef fixture) =>
      _inner.findByFixture(fixture);
}
