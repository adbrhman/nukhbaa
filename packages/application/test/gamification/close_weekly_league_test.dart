import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart' show FakeIdGenerator;

const _leagueBronze = '11111111-1111-1111-1111-111111111111';
const _leagueSilver = '22222222-2222-2222-2222-222222222222';

/// An older week, already well past its grace period by [_now].
final _weekA = DateTime.utc(2026, 9, 7);

/// The week right after [_weekA], also past its grace period by [_now].
final _weekB = DateTime.utc(2026, 9, 14);

/// The week in progress when [_now] is read: it has groups (P2-3 seats lazily
/// as players are seen) but has not ended yet, so it must never be closed.
final _weekCurrent = DateTime.utc(2026, 9, 21);

/// Comfortably after weekA's and weekB's grace period, and inside weekCurrent.
final _now = DateTime.utc(2026, 9, 23, 10);

WeeklyLeagueEntry _entry(
  String id, {
  required int points,
  DateTime? joinedAt,
}) => WeeklyLeagueEntry(
  userId: UserId(id),
  points: points,
  exactCount: 0,
  decidedCount: 0,
  joinedAt: joinedAt ?? DateTime.utc(2026, 9, 7, 9),
);

String _id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

CloseWeeklyLeague _useCase({
  required _FakeClosureStore closures,
  required _FakeStandings standings,
  _FakeEvents? events,
  int maxWeeksPerRun = 8,
}) => CloseWeeklyLeague(
  closures: closures,
  standings: standings,
  events: events ?? _FakeEvents(),
  idGenerator: FakeIdGenerator(<String>[_id(900)]),
  maxWeeksPerRun: maxWeeksPerRun,
);

void main() {
  group('CloseWeeklyLeague', () {
    test('does nothing when every started week is already closed', () async {
      final closures = _FakeClosureStore(weeks: const []);
      final standings = _FakeStandings(const {});

      final result = await _useCase(
        closures: closures,
        standings: standings,
      ).call(now: _now);

      expect((result as Ok<int>).value, 0);
      expect(closures.markClosedCalls, isEmpty);
    });

    test('the week in progress is never closed -- it has not ended', () async {
      final closures = _FakeClosureStore(
        weeks: [_weekCurrent],
        groups: {
          _weekCurrent: const [
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueBronze),
              tier: WeeklyLeagueTier.bronze,
            ),
          ],
        },
      );
      final standings = _FakeStandings({
        _leagueBronze: [_entry(_id(1), points: 5)],
      });

      final result = await _useCase(
        closures: closures,
        standings: standings,
      ).call(now: _now);

      expect((result as Ok<int>).value, 0);
      expect(standings.calls, 0);
      expect(closures.markClosedCalls, isEmpty);
    });

    test('closes overdue weeks oldest first', () async {
      final closures = _FakeClosureStore(
        weeks: [_weekB, _weekA],
        groups: {
          _weekA: const [
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueBronze),
              tier: WeeklyLeagueTier.bronze,
            ),
          ],
          _weekB: const [
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueBronze),
              tier: WeeklyLeagueTier.bronze,
            ),
          ],
        },
      );
      final standings = _FakeStandings({
        _leagueBronze: [_entry(_id(1), points: 5)],
      });

      final result = await _useCase(
        closures: closures,
        standings: standings,
      ).call(now: _now);

      expect((result as Ok<int>).value, 2);
      expect(
        [for (final c in closures.markClosedCalls) c.weekStart],
        [_weekA, _weekB],
      );
    });

    test(
      'waits for the grace period after the week ends, then closes',
      () async {
        final closures = _FakeClosureStore(
          weeks: [_weekA],
          groups: {
            _weekA: const [
              WeeklyLeagueGroupRef(
                leagueId: WeeklyLeagueId(_leagueBronze),
                tier: WeeklyLeagueTier.bronze,
              ),
            ],
          },
        );
        final standings = _FakeStandings({
          _leagueBronze: [_entry(_id(1), points: 5)],
        });

        // weekA's real end is 2026-09-13 21:00 UTC; 30 minutes later is
        // still inside the default 3-hour grace.
        final tooSoon = await _useCase(
          closures: closures,
          standings: standings,
        ).call(now: DateTime.utc(2026, 9, 13, 21, 30));
        expect((tooSoon as Ok<int>).value, 0);
        expect(closures.markClosedCalls, isEmpty);

        // Exactly 3 hours after the end: the grace is over.
        final onTime = await _useCase(
          closures: closures,
          standings: standings,
        ).call(now: DateTime.utc(2026, 9, 14));
        expect((onTime as Ok<int>).value, 1);
      },
    );

    test('judges every group, emits one event per member and tallies '
        'member_count across groups', () async {
      final events = _FakeEvents();
      final closures = _FakeClosureStore(
        weeks: [_weekA],
        groups: {
          _weekA: const [
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueBronze),
              tier: WeeklyLeagueTier.bronze,
            ),
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueSilver),
              tier: WeeklyLeagueTier.silver,
            ),
          ],
        },
      );
      final standings = _FakeStandings({
        _leagueBronze: [_entry(_id(1), points: 10), _entry(_id(2), points: 5)],
        _leagueSilver: [
          _entry(_id(3), points: 20),
          _entry(_id(4), points: 15),
          _entry(_id(5), points: 9),
        ],
      });

      final result = await _useCase(
        closures: closures,
        standings: standings,
        events: events,
      ).call(now: _now);

      expect((result as Ok<int>).value, 1);
      expect(events.recorded, hasLength(5));
      expect(closures.markClosedCalls.single.memberCount, 5);
    });

    test(
      'the recorded event carries the group tier, the rank and points '
      "judge gave the member, and the week's own end as occurred_at",
      () async {
        final events = _FakeEvents();
        final closures = _FakeClosureStore(
          weeks: [_weekA],
          groups: {
            _weekA: const [
              WeeklyLeagueGroupRef(
                leagueId: WeeklyLeagueId(_leagueBronze),
                tier: WeeklyLeagueTier.bronze,
              ),
            ],
          },
        );
        final standings = _FakeStandings({
          _leagueBronze: [
            _entry(_id(1), points: 10),
            _entry(_id(2), points: 5),
          ],
        });

        await _useCase(
          closures: closures,
          standings: standings,
          events: events,
        ).call(now: _now);

        final leader = events.recorded.firstWhere(
          (e) => e.userId == UserId(_id(1)),
        );
        expect(leader.payload['tier'], WeeklyLeagueTier.bronze.level);
        expect(leader.payload['rank'], 1);
        expect(leader.payload['points'], 10);
        expect(leader.dedupeKey, 'weekly_league_finished:${_id(1)}:2026-09-07');
        // weekA's real end: Monday 2026-09-14 00:00 Riyadh = Sunday
        // 2026-09-13 21:00 UTC.
        expect(leader.occurredAt, DateTime.utc(2026, 9, 13, 21));
      },
    );

    test('a long backlog is closed at most maxWeeksPerRun at a time', () async {
      final weekC = DateTime.utc(2026, 8, 31);
      final closures = _FakeClosureStore(
        weeks: [_weekB, weekC, _weekA],
        groups: {
          for (final w in [_weekA, _weekB, weekC])
            w: const [
              WeeklyLeagueGroupRef(
                leagueId: WeeklyLeagueId(_leagueBronze),
                tier: WeeklyLeagueTier.bronze,
              ),
            ],
        },
      );
      final standings = _FakeStandings({
        _leagueBronze: [_entry(_id(1), points: 5)],
      });

      final first = await _useCase(
        closures: closures,
        standings: standings,
        maxWeeksPerRun: 2,
      ).call(now: _now);
      expect((first as Ok<int>).value, 2);
      expect(
        [for (final c in closures.markClosedCalls) c.weekStart],
        [weekC, _weekA],
      );

      final second = await _useCase(
        closures: closures,
        standings: standings,
        maxWeeksPerRun: 2,
      ).call(now: _now);
      expect((second as Ok<int>).value, 1);
    });

    test('re-running after everything is closed changes nothing', () async {
      final closures = _FakeClosureStore(
        weeks: [_weekA],
        groups: {
          _weekA: const [
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueBronze),
              tier: WeeklyLeagueTier.bronze,
            ),
          ],
        },
      );
      final standings = _FakeStandings({
        _leagueBronze: [_entry(_id(1), points: 5)],
      });
      final useCase = _useCase(closures: closures, standings: standings);

      await useCase.call(now: _now);
      final again = await useCase.call(now: _now);

      expect((again as Ok<int>).value, 0);
      expect(closures.markClosedCalls, hasLength(1));
    });

    test('a watermark failure is returned and nothing is touched', () async {
      final closures = _FakeClosureStore(weeks: const [])
        ..failNext = const AppError.transient('db.down', 'down');
      final standings = _FakeStandings(const {});

      final result = await _useCase(
        closures: closures,
        standings: standings,
      ).call(now: _now);

      expect((result as Err<int>).error.code, 'db.down');
    });

    test(
      'a groups-of failure is returned and standings are never read',
      () async {
        final closures = _FakeClosureStore(weeks: [_weekA])
          ..failGroups = const AppError.transient('db.down', 'down');
        final standings = _FakeStandings(const {});

        final result = await _useCase(
          closures: closures,
          standings: standings,
        ).call(now: _now);

        expect((result as Err<int>).error.code, 'db.down');
        expect(standings.calls, 0);
        expect(closures.markClosedCalls, isEmpty);
      },
    );

    test(
      'a standings failure is returned and the week is not marked closed',
      () async {
        final closures = _FakeClosureStore(
          weeks: [_weekA],
          groups: {
            _weekA: const [
              WeeklyLeagueGroupRef(
                leagueId: WeeklyLeagueId(_leagueBronze),
                tier: WeeklyLeagueTier.bronze,
              ),
            ],
          },
        );
        final standings = _FakeStandings(const {})
          ..failWith = const AppError.transient('db.down', 'down');

        final result = await _useCase(
          closures: closures,
          standings: standings,
        ).call(now: _now);

        expect((result as Err<int>).error.code, 'db.down');
        expect(closures.markClosedCalls, isEmpty);
      },
    );

    test(
      'an event-sink failure is returned and the week is not marked closed',
      () async {
        final events = _FakeEvents()
          ..failWith = const AppError.transient('db.down', 'down');
        final closures = _FakeClosureStore(
          weeks: [_weekA],
          groups: {
            _weekA: const [
              WeeklyLeagueGroupRef(
                leagueId: WeeklyLeagueId(_leagueBronze),
                tier: WeeklyLeagueTier.bronze,
              ),
            ],
          },
        );
        final standings = _FakeStandings({
          _leagueBronze: [_entry(_id(1), points: 5)],
        });

        final result = await _useCase(
          closures: closures,
          standings: standings,
          events: events,
        ).call(now: _now);

        expect((result as Err<int>).error.code, 'db.down');
        expect(closures.markClosedCalls, isEmpty);
      },
    );

    test('a mark-closed failure is returned', () async {
      final closures = _FakeClosureStore(
        weeks: [_weekA],
        groups: {
          _weekA: const [
            WeeklyLeagueGroupRef(
              leagueId: WeeklyLeagueId(_leagueBronze),
              tier: WeeklyLeagueTier.bronze,
            ),
          ],
        },
      )..failMark = const AppError.transient('db.down', 'down');
      final standings = _FakeStandings({
        _leagueBronze: [_entry(_id(1), points: 5)],
      });

      final result = await _useCase(
        closures: closures,
        standings: standings,
      ).call(now: _now);

      expect((result as Err<int>).error.code, 'db.down');
    });
  });
}

/// One `markClosed` call the use-case made.
final class _MarkClosedCall {
  const _MarkClosedCall(this.weekStart, this.memberCount);

  final DateTime weekStart;
  final int memberCount;
}

/// An in-memory [WeeklyLeagueClosureStore]: `markClosed` moves the
/// watermark, as the real store's inserted row does.
final class _FakeClosureStore implements WeeklyLeagueClosureStore {
  _FakeClosureStore({required List<DateTime> weeks, this.groups = const {}})
    : _weeks = List<DateTime>.of(weeks);

  final List<DateTime> _weeks;
  final Map<DateTime, List<WeeklyLeagueGroupRef>> groups;
  final Set<DateTime> _closed = <DateTime>{};
  final List<_MarkClosedCall> markClosedCalls = <_MarkClosedCall>[];

  AppError? failNext;
  AppError? failGroups;
  AppError? failMark;

  @override
  Future<Result<DateTime?>> nextUnclosedWeek() async {
    final error = failNext;
    if (error != null) {
      return Result.err(error);
    }
    final remaining = _weeks.where((w) => !_closed.contains(w)).toList()
      ..sort();
    return Result.ok(remaining.isEmpty ? null : remaining.first);
  }

  @override
  Future<Result<List<WeeklyLeagueGroupRef>>> groupsOf(
    DateTime weekStart,
  ) async {
    final error = failGroups;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(groups[weekStart] ?? const <WeeklyLeagueGroupRef>[]);
  }

  @override
  Future<Result<void>> markClosed({
    required DateTime weekStart,
    required int memberCount,
  }) async {
    final error = failMark;
    if (error != null) {
      return Result.err(error);
    }
    markClosedCalls.add(_MarkClosedCall(weekStart, memberCount));
    _closed.add(weekStart);
    return const Result.ok(null);
  }
}

/// Scripted [WeeklyLeagueStandingsReader], keyed by league id.
final class _FakeStandings implements WeeklyLeagueStandingsReader {
  _FakeStandings(this._byLeague);

  final Map<String, List<WeeklyLeagueEntry>> _byLeague;
  AppError? failWith;
  int calls = 0;

  @override
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  }) async {
    calls++;
    final error = failWith;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(_byLeague[leagueId.value] ?? const <WeeklyLeagueEntry>[]);
  }
}

/// Records every event handed to it, as the real sink's insert would.
final class _FakeEvents implements GamificationEventSink {
  final List<GamificationEvent> recorded = <GamificationEvent>[];
  AppError? failWith;

  @override
  Future<Result<void>> record(GamificationEvent event) async {
    final error = failWith;
    if (error != null) {
      return Result.err(error);
    }
    recorded.add(event);
    return const Result.ok(null);
  }
}
