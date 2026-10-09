import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _october = DateTime.utc(2026, 10);
final _november = DateTime.utc(2026, 11);
const _league = H2hLeagueId('11111111-1111-4111-8111-111111111111');

/// 2026-12-01 03:30 Riyadh: half an hour past November's grace.
final _afterGrace = DateTime.utc(2026, 12, 1, 0, 30);

H2hRound _round1({bool locked = true}) => H2hRound(
  id: const H2hRoundId('22222222-2222-4222-8222-222222222222'),
  monthStart: _november,
  number: 1,
  day: DateTime.utc(2026, 11, 8),
  fixtureCount: 8,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, 8, 12) : null,
);

/// November drawn with one first-division group of four, one round played.
({
  FakeH2hLeagueStore leagues,
  FakeH2hRoundStore rounds,
  FakeH2hSheetReader sheets,
})
_world({bool settled = true, bool pilot = false, DateTime? month}) {
  final m = month ?? _november;
  final leagues = FakeH2hLeagueStore();
  leagues.drawn[m] = [
    H2hDrawnGroup(
      leagueId: _league,
      group: H2hDrawGroup(
        division: H2hDivision.first,
        groupIndex: 0,
        seats: [
          for (var i = 0; i < 4; i++)
            H2hDrawSeat(userId: userNo(i + 1), slot: i),
        ],
      ),
    ),
  ];
  leagues.months[m] = H2hMonthInfo(
    monthStart: m,
    isPilot: pilot,
    seatedCount: 4,
  );
  final rounds = FakeH2hRoundStore()..addRound(_round1());
  final sheets = FakeH2hSheetReader();
  sheets.sheets[_league] = H2hGroupSheet(
    members: [
      for (var i = 0; i < 4; i++)
        H2hMember(
          userId: userNo(i + 1),
          slot: i,
          joinedAt: DateTime.utc(2026, 11, 1, 0, i),
        ),
    ],
    scores: [
      H2hRoundScore(
        userId: userNo(1),
        round: 1,
        points: 10,
        exactCount: 2,
        predictedCount: 8,
      ),
      H2hRoundScore(
        userId: userNo(2),
        round: 1,
        points: 6,
        exactCount: 1,
        predictedCount: 8,
      ),
      H2hRoundScore(
        userId: userNo(3),
        round: 1,
        points: 3,
        exactCount: 0,
        predictedCount: 8,
      ),
      H2hRoundScore(
        userId: userNo(4),
        round: 1,
        points: 0,
        exactCount: 0,
        predictedCount: 1,
      ),
    ],
    settledRounds: settled ? <int>{1} : <int>{},
    voidRounds: const <int>{},
  );
  sheets.activeDays
    ..[userNo(1)] = 9
    ..[userNo(2)] = 6
    ..[userNo(3)] = 5
    ..[userNo(4)] = 2;
  return (leagues: leagues, rounds: rounds, sheets: sheets);
}

CloseH2hMonth _close(
  ({
    FakeH2hLeagueStore leagues,
    FakeH2hRoundStore rounds,
    FakeH2hSheetReader sheets,
  })
  world,
  RecordingEvents events,
) => CloseH2hMonth(
  leagues: world.leagues,
  rounds: world.rounds,
  sheets: world.sheets,
  events: events,
  idGenerator: SequenceIds(),
);

void main() {
  group('CloseH2hMonth', () {
    test('waits for the grace after the month ends', () async {
      final world = _world();
      final events = RecordingEvents();

      final result = await _close(
        world,
        events,
      ).call(now: DateTime.utc(2026, 11, 30, 22));

      expect((result as Ok<int>).value, 0);
      expect(events.recorded, isEmpty);
      expect(world.leagues.closed, isEmpty);
    });

    test(
      'judges the month: one event per member, then the month is closed',
      () async {
        final world = _world();
        final events = RecordingEvents();

        final result = await _close(world, events).call(now: _afterGrace);

        expect((result as Ok<int>).value, 1);
        expect(world.leagues.closed[_november], 4);
        expect(events.recorded, hasLength(4));
        final byUser = {for (final e in events.recorded) e.userId: e.payload};
        // Every seat but the four plays the average (4.75) in round 1.
        expect(byUser[userNo(1)]!['rank'], 1);
        expect(byUser[userNo(1)]!['league_points'], 3);
        expect(byUser[userNo(1)]!['points'], 10);
        expect(byUser[userNo(1)]!['next_division'], 1);
        expect(byUser[userNo(2)]!['rank'], 2);
        expect(byUser[userNo(3)]!['outcome'], 'held');
        // Two days with a prediction: not drawn next month.
        expect(byUser[userNo(4)]!['next_division'], isNull);
        expect(byUser[userNo(4)]!['outcome'], 'out');
        expect(
          events.recorded.every(
            (e) => e.occurredAt == DateTime.utc(2026, 11, 30, 21),
          ),
          isTrue,
        );
        expect(events.recorded.every((e) => e.refId == _league.value), isTrue);
      },
    );

    test('waits for unsettled rounds, then judges without them', () async {
      final world = _world(settled: false);
      final events = RecordingEvents();

      final early = await _close(world, events).call(now: _afterGrace);
      expect((early as Ok<int>).value, 0);
      expect(world.leagues.closed, isEmpty);

      final late = await _close(
        world,
        events,
      ).call(now: DateTime.utc(2026, 12, 4));
      expect((late as Ok<int>).value, 1);
      expect(events.recorded, hasLength(4));
    });

    test('a pilot month is closed without events', () async {
      final world = _world(pilot: true, month: _october);
      final events = RecordingEvents();

      final result = await _close(
        world,
        events,
      ).call(now: DateTime.utc(2026, 11, 1, 1));

      expect((result as Ok<int>).value, 1);
      expect(world.leagues.closed.containsKey(_october), isTrue);
      expect(events.recorded, isEmpty);
    });

    test('a lost event leaves the month open', () async {
      final world = _world();
      final events = RecordingEvents(failFrom: 2);

      final result = await _close(world, events).call(now: _afterGrace);

      expect(result.isOk, isFalse);
      expect(world.leagues.closed, isEmpty);
    });
  });
}
