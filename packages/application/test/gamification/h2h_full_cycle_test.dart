/// The whole head-to-head cycle through the real use-cases over the
/// in-memory stores (migration 0100, scripts 171, 172 and NK182): the first
/// month is drawn from the players of the month before by the elite draw,
/// its round is approved by the system and frozen when it kicks off, the
/// month is judged by `CloseH2hMonth`, and only then does the next month's
/// draw run -- the crossing of November into December 2026. How the elite
/// groups carry into December is the next batch, so December waits undrawn
/// with the reason.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _october = DateTime.utc(2026, 10);
final _november = DateTime.utc(2026, 11);
final _december = DateTime.utc(2026, 12);

/// 2026-11-01 00:30 Riyadh: already November.
final _novemberNight = DateTime.utc(2026, 10, 31, 21, 30);

/// 2026-12-01 01:00 Riyadh: December's first night, November not judged.
final _decemberNight = DateTime.utc(2026, 11, 30, 22);

/// 2026-12-01 03:30 Riyadh: half an hour past November's grace.
final _afterGrace = DateTime.utc(2026, 12, 1, 0, 30);

/// The only round day of the test month, with its first kickoff at 18:00
/// Riyadh.
final _roundDay = DateTime.utc(2026, 11, 10);
final _firstKickoff = DateTime.utc(2026, 11, 10, 15);

/// The stores, the scripted sources and the three use-cases of the cycle.
final class _Cycle {
  _Cycle({RecordingEvents? recorder}) : events = recorder ?? RecordingEvents() {
    // Three players: one elite group (the elite draw opens a group per pair
    // of players when there are fewer than eight).
    source.active[_october] = <UserId>[for (var i = 1; i <= 3; i++) userNo(i)];
    rounds.dayOf(_roundDay, 8, _firstKickoff);
  }

  final RecordingEvents events;
  final FakeH2hLeagueStore leagues = FakeH2hLeagueStore();
  final FakeH2hRoundStore rounds = FakeH2hRoundStore();
  final FakeH2hDrawSource source = FakeH2hDrawSource();
  final FakeH2hSheetReader sheets = FakeH2hSheetReader();
  final SequenceIds ids = SequenceIds();

  DrawH2hMonth get draw =>
      DrawH2hMonth(leagues: leagues, source: source, idGenerator: ids);

  RunH2hRounds get run =>
      RunH2hRounds(rounds: rounds, leagues: leagues, idGenerator: ids);

  CloseH2hMonth get close => CloseH2hMonth(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets,
    events: events,
    idGenerator: ids,
  );

  /// Draws November, approves and freezes its round, and has the round
  /// scored and settled: user 1 first, user 3 last and under five days.
  Future<void> playNovember() async {
    final seated = await draw.call(now: _novemberNight);
    expect((seated as Ok<int>).value, 3);

    // The system approves the day a day ahead, with no admin.
    final approved = await run.call(now: DateTime.utc(2026, 11, 9, 16));
    expect((approved as Ok<H2hRoundsRun>).value.approved, 1);
    expect(rounds.byMonth[_november]!.single.locked, isFalse);

    // The first match kicked off: the round's list is frozen.
    final frozen = await run.call(now: DateTime.utc(2026, 11, 10, 16));
    expect((frozen as Ok<H2hRoundsRun>).value.locked, 1);
    expect(rounds.byMonth[_november]!.single.locked, isTrue);

    final group = leagues.drawn[_november]!.single;
    expect(group.group.division, H2hLeaguePolicy.eliteDivision);
    sheets.sheets[group.leagueId] = H2hGroupSheet(
      members: <H2hMember>[
        for (final seat in group.group.seats)
          H2hMember(
            userId: seat.userId,
            slot: seat.slot,
            joinedAt: DateTime.utc(2026, 11, 1, 0, seat.slot),
          ),
      ],
      scores: <H2hRoundScore>[
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
          points: 0,
          exactCount: 0,
          predictedCount: 1,
        ),
      ],
      settledRounds: <int>{1},
      voidRounds: const <int>{},
    );
    sheets.activeDays
      ..[userNo(1)] = 9
      ..[userNo(2)] = 6
      ..[userNo(3)] = 2;
  }
}

/// What the draw reads of the events a judged month wrote: the players the
/// month sends on, in their next division.
List<H2hCarry> _carriedBy(List<GamificationEvent> events) {
  final carried = <H2hCarry>[];
  for (final event in events) {
    final nextLevel = event.payload['next_division'] as int?;
    if (nextLevel == null) {
      continue;
    }
    final next = H2hDivision.ofLevel(nextLevel);
    final division = H2hDivision.ofLevel(event.payload['division'] as int);
    if (next == null || division == null) {
      continue;
    }
    carried.add(
      H2hCarry(
        userId: event.userId,
        nextDivision: next,
        division: division,
        rank: event.payload['rank'] as int,
      ),
    );
  }
  return carried;
}

void main() {
  group('H2H full cycle', () {
    test('November is drawn, played and judged; December waits for the carry '
        'of the elite groups', () async {
      final cycle = _Cycle();
      await cycle.playNovember();

      // December waits for November's judgement: nothing is drawn yet.
      final early = await cycle.draw.call(now: _decemberNight);
      expect((early as Ok<int>).value, 0);
      expect(cycle.leagues.months.containsKey(_december), isFalse);

      // The close judges November: one event per member, then the closure.
      final closed = await cycle.close.call(now: _afterGrace);
      expect((closed as Ok<int>).value, 1);
      expect(cycle.leagues.closed[_november], 3);
      expect(cycle.events.recorded, hasLength(3));
      final byUser = {
        for (final e in cycle.events.recorded) e.userId: e.payload,
      };
      expect(byUser[userNo(1)]!['rank'], 1);
      expect(byUser[userNo(1)]!['next_division'], 1);
      // Two days with a prediction: out of the next draw.
      expect(byUser[userNo(3)]!['outcome'], 'out');
      expect(byUser[userNo(3)]!['next_division'], isNull);

      // November is judged, but the carry of the elite groups (NK182,
      // next batch) is not built: December is not drawn by the old
      // ladder -- a draw is never repeated -- and the run says why.
      cycle.source
        ..carried[_november] = _carriedBy(cycle.events.recorded)
        ..active[_november] = <UserId>[userNo(1), userNo(2), userNo(5)];
      final seated = await cycle.draw.call(now: _afterGrace);

      expect((seated as Err<int>).error.code, 'h2h.elite_carry_pending');
      expect(cycle.source.carriedAsked, isEmpty);
      expect(cycle.leagues.months.containsKey(_december), isFalse);
    });

    test('a lost event leaves November open and December undrawn', () async {
      final cycle = _Cycle(recorder: RecordingEvents(failFrom: 2));
      await cycle.playNovember();

      final closed = await cycle.close.call(now: _afterGrace);
      expect(closed.isOk, isFalse);
      expect(cycle.leagues.closed, isEmpty);

      final seated = await cycle.draw.call(now: _afterGrace);
      expect((seated as Ok<int>).value, 0);
      expect(cycle.leagues.months.containsKey(_december), isFalse);
    });
  });
}
