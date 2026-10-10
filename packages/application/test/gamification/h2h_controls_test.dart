import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

DateTime _day(int d) => DateTime.utc(2026, 11, d);

/// Kickoff [hour]:00 Riyadh on November [d], as UTC.
DateTime _kickoff(int d, int hour) => DateTime.utc(2026, 11, d, hour - 3);

/// In-memory [H2hControlStore].
final class _Controls implements H2hControlStore {
  H2hSettings knobs = H2hSettings.defaults;
  final Set<DateTime> excluded = <DateTime>{};
  final List<H2hAdminActionKind> log = <H2hAdminActionKind>[];
  bool unreadable = false;

  @override
  Future<Result<H2hSettings>> settings() async => unreadable
      ? const Result.err(AppError.transient('db.down', 'Database down'))
      : Result.ok(knobs);

  @override
  Future<Result<void>> saveSettings({
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
    required UserId by,
  }) async {
    knobs = H2hSettings(
      autoApprove: autoApprove,
      leadHours: leadHours,
      minActiveDays: minActiveDays,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  }) async => Result.ok({
    for (final d in excluded)
      if (!d.isBefore(from) && !d.isAfter(through)) d,
  });

  @override
  Future<Result<bool>> exclude({
    required DateTime day,
    required UserId by,
  }) async => Result.ok(excluded.add(day));

  @override
  Future<Result<bool>> include(DateTime day) async =>
      Result.ok(excluded.remove(day));

  @override
  Future<Result<void>> addSeat({
    required H2hLeagueId leagueId,
    required DateTime monthStart,
    required UserId userId,
    required int slot,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> record({
    required String id,
    required H2hAdminActionKind action,
    required UserId? by,
    required Map<String, Object?> detail,
  }) async {
    log.add(action);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<H2hAdminAction>>> recentActions(int limit) async =>
      const Result.ok(<H2hAdminAction>[]);
}

/// A round store whose withdrawal is refused.
final class _RefusingWithdraw implements H2hRoundStore {
  _RefusingWithdraw(this._inner);

  final FakeH2hRoundStore _inner;

  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) =>
      _inner.roundsOf(monthStart);

  @override
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day) =>
      _inner.dayFixtures(day);

  @override
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  }) => _inner.daysBetween(from: from, through: through);

  @override
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  }) => _inner.approve(
    id: id,
    monthStart: monthStart,
    number: number,
    day: day,
    fixtureCount: fixtureCount,
    approvedBy: approvedBy,
  );

  @override
  Future<Result<void>> withdraw(H2hRoundId roundId) async => const Result.err(
    AppError.invariant('h2h.round_locked', 'The round already started'),
  );

  @override
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  }) => _inner.lock(roundId: roundId, day: day);
}

RunH2hRounds _run(FakeH2hRoundStore rounds, {_Controls? controls}) =>
    RunH2hRounds(
      rounds: rounds,
      leagues: FakeH2hLeagueStore(),
      idGenerator: SequenceIds(),
      controls: controls,
    );

WithdrawH2hRound _withdraw(
  H2hRoundStore rounds,
  _Controls controls,
  DateTime now,
) => WithdrawH2hRound(
  rounds: rounds,
  controls: controls,
  clock: AtClock(now),
  idGenerator: SequenceIds(),
);

void main() {
  // 19:00 Riyadh on November 10; tomorrow's first kickoff is 20 hours away.
  final now = DateTime.utc(2026, 11, 10, 16);

  FakeH2hRoundStore tomorrowIsRegular() =>
      FakeH2hRoundStore()..dayOf(_day(11), 9, _kickoff(11, 15));

  group('a withdrawn day stays out', () {
    test('without the controls the scheduler approves it straight back '
        '(the reason for this batch)', () async {
      final rounds = tomorrowIsRegular();
      await _run(rounds).call(now: now);
      final round = rounds.byMonth[_november]!.single;
      rounds.byMonth[_november]!.clear(); // what a withdrawal leaves

      await _run(rounds).call(now: now);

      expect(rounds.byMonth[_november], hasLength(1));
      expect(round.day, _day(11));
    });

    test('withdrawing excludes the day, so the next run leaves it', () async {
      final rounds = tomorrowIsRegular();
      final controls = _Controls();
      await _run(rounds, controls: controls).call(now: now);
      final round = rounds.byMonth[_november]!.single;

      final done = await _withdraw(
        rounds,
        controls,
        now,
      ).call(principal: admin, roundId: round.id);
      rounds.byMonth[_november]!.clear();
      final again = await _run(rounds, controls: controls).call(now: now);

      expect(done.isOk, isTrue);
      expect(rounds.withdrawCalls, [round.id]);
      expect(controls.excluded, {_day(11)});
      expect(controls.log, [H2hAdminActionKind.roundWithdrawn]);
      expect((again as Ok<H2hRoundsRun>).value.approved, 0);
      expect(rounds.byMonth[_november], isEmpty);
    });

    test('a refused withdrawal lifts the exclusion it made', () async {
      final inner = tomorrowIsRegular();
      final controls = _Controls();
      await _run(inner, controls: controls).call(now: now);
      final round = inner.byMonth[_november]!.single;

      final done = await _withdraw(
        _RefusingWithdraw(inner),
        controls,
        now,
      ).call(principal: admin, roundId: round.id);

      expect((done as Err<void>).error.code, 'h2h.round_locked');
      expect(controls.excluded, isEmpty);
      expect(controls.log, isEmpty);
    });

    test('an admin approving the day by hand lifts the exclusion', () async {
      final rounds = tomorrowIsRegular();
      final controls = _Controls()..excluded.add(_day(11));

      final approved = await ApproveH2hRound(
        rounds: rounds,
        idGenerator: SequenceIds(),
        clock: AtClock(now),
        controls: controls,
      ).call(principal: admin, day: _day(11));

      expect(approved.isOk, isTrue);
      expect(controls.excluded, isEmpty);
      expect(controls.log, [H2hAdminActionKind.roundApproved]);
    });

    test('only an admin may withdraw', () async {
      final controls = _Controls();
      final done = await _withdraw(tomorrowIsRegular(), controls, now).call(
        principal: player,
        roundId: const H2hRoundId('00000000-0000-4000-8000-000000000101'),
      );

      expect(done.isErr, isTrue);
      expect(controls.excluded, isEmpty);
    });
  });

  group('the settings steer automatic approval', () {
    test(
      'automatic approval off: nothing approved, locking unchanged',
      () async {
        final rounds = tomorrowIsRegular()
          ..dayOf(_day(10), 8, _kickoff(10, 15))
          ..addRound(
            H2hRound(
              id: const H2hRoundId('00000000-0000-4000-8000-000000000101'),
              monthStart: _november,
              number: 1,
              day: _day(10),
              fixtureCount: 8,
              approvedBy: null,
              lockedAt: null,
            ),
          );
        final controls = _Controls()
          ..knobs = const H2hSettings(
            autoApprove: false,
            leadHours: 24,
            minActiveDays: 5,
          );

        final result = await _run(rounds, controls: controls).call(now: now);

        final run = (result as Ok<H2hRoundsRun>).value;
        expect(run.approved, 0);
        expect(run.locked, 1);
        expect(rounds.byMonth[_november], hasLength(1));
      },
    );

    test('unreadable controls approve nothing but still lock', () async {
      final rounds = tomorrowIsRegular()
        ..dayOf(_day(10), 8, _kickoff(10, 15))
        ..addRound(
          H2hRound(
            id: const H2hRoundId('00000000-0000-4000-8000-000000000101'),
            monthStart: _november,
            number: 1,
            day: _day(10),
            fixtureCount: 8,
            approvedBy: null,
            lockedAt: null,
          ),
        );
      final controls = _Controls()..unreadable = true;

      final result = await _run(rounds, controls: controls).call(now: now);

      expect((result as Err<H2hRoundsRun>).error.code, 'db.down');
      expect(rounds.lockCalls, hasLength(1));
      expect(rounds.byMonth[_november], hasLength(1));
    });

    test('a shorter lead waits until the day is that close', () async {
      final controls = _Controls()
        ..knobs = const H2hSettings(
          autoApprove: true,
          leadHours: 6,
          minActiveDays: 5,
        );

      final early = tomorrowIsRegular();
      final tooEarly = await _run(early, controls: controls).call(now: now);
      final late = tomorrowIsRegular();
      final inTime = await _run(
        late,
        controls: controls,
      ).call(now: DateTime.utc(2026, 11, 11, 7)); // 10:00 Riyadh, 5 h ahead

      expect((tooEarly as Ok<H2hRoundsRun>).value.approved, 0);
      expect((inTime as Ok<H2hRoundsRun>).value.approved, 1);
    });

    test('an excluded day is skipped, the next one is not', () async {
      final rounds = FakeH2hRoundStore()
        ..dayOf(_day(10), 9, _kickoff(10, 21))
        ..dayOf(_day(11), 9, _kickoff(11, 15));
      final controls = _Controls()..excluded.add(_day(10));

      final result = await _run(rounds, controls: controls).call(now: now);

      expect((result as Ok<H2hRoundsRun>).value.approved, 1);
      expect(rounds.byMonth[_november]!.single.day, _day(11));
    });
  });
}
