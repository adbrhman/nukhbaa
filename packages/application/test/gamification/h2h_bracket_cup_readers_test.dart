// NK359_01
/// The readers of the Elite Cup count the titles of the month's own cup
/// (NK359_01, owner decision 2026-11-28): a bracket month ends with its one
/// title, so the next month's rounds are no longer held back once it is
/// crowned, and the finished bracket leaves the player's screen after its
/// lingering days. Up to November 2026 the three paths stay as they were.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
final _december = DateTime.utc(2026, 12);

/// The Elite Cups as stored, by month: only their state is asked.
final class _Cups implements H2hCupStore {
  _Cups(this.byMonth);

  final Map<DateTime, H2hCupState> byMonth;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async =>
      Result.ok(byMonth[monthStart] ?? H2hCupState.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupEntry _entry(int n, int place) => H2hCupEntry(
  userId: userNo(n),
  place: place,
  groupNumber: n,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// The sixteen of a bracket's first round, two of each of eight groups.
List<H2hCupEntry> _sixteen() => [
  for (var g = 1; g <= 8; g++) ...[_entry(g, 1), _entry(g + 10, 2)],
];

H2hCupTitle _title(int place) => H2hCupTitle(
  place: place,
  champion: userNo(place),
  runnerUp: null,
  how: 'final',
);

/// A stage of [step] decided on December [day].
H2hCupStage _stage(int day) => H2hCupStage(
  id: const H2hCupStageId('33333333-3333-4333-8333-000000000001'),
  monthStart: _december,
  step: const H2hCupStep(1, H2hCupRound.finale, bracket: true),
  attempt: 1,
  day: DateTime.utc(2026, 12, day),
  fixtureCount: 8,
  lockedAt: DateTime.utc(2026, 12, day, 12),
  pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(11))],
  results: const [],
);

H2hCupState _decemberCup({required int titles, int lastDay = 23}) =>
    H2hCupState(
      entries: _sixteen(),
      stages: [_stage(lastDay)],
      titles: [for (var place = 1; place <= titles; place++) _title(place)],
    );

/// Nineteen December rounds, as a month that finished its league has.
FakeH2hRoundStore _decemberLeague() {
  final rounds = FakeH2hRoundStore();
  for (var n = 1; n <= 19; n++) {
    rounds.addRound(
      H2hRound(
        id: H2hRoundId('00000000-0000-4000-8000-000000000${400 + n}'),
        monthStart: _december,
        number: n,
        day: DateTime.utc(2026, 12, n),
        fixtureCount: 8,
        approvedBy: null,
        lockedAt: DateTime.utc(2026, 12, n, 12),
      ),
    );
  }
  return rounds;
}

void main() {
  group('the next month waits for the bracket (RunH2hRounds)', () {
    // 01:00 Riyadh on 4 January: the 5th has eight fixtures, its first
    // kickoff within 24 hours.
    final now = DateTime.utc(2027, 1, 4, 22);
    final fifth = DateTime.utc(2027, 1, 5);

    Future<FakeH2hRoundStore> run(H2hCupState december) async {
      final rounds = _decemberLeague()
        ..dayOf(fifth, 8, DateTime.utc(2027, 1, 5, 15));
      final result = await RunH2hRounds(
        rounds: rounds,
        leagues: FakeH2hLeagueStore()
          ..months[_december] = H2hMonthInfo(
            monthStart: _december,
            isPilot: false,
            seatedCount: 200,
          ),
        idGenerator: SequenceIds(),
        cups: _Cups({_december: december}),
      ).call(now: now);
      expect(result, isA<Ok<H2hRoundsRun>>(), reason: '$result');
      return rounds;
    }

    test('a bracket with no champion yet holds January back', () async {
      final rounds = await run(_decemberCup(titles: 0));

      expect(rounds.byMonth[DateTime.utc(2027, 1)], isNull);
    });

    test('once its one title is crowned January starts', () async {
      final rounds = await run(_decemberCup(titles: 1));

      expect(rounds.byMonth[DateTime.utc(2027, 1)]!.single.day, fifth);
    });
  });

  group('the bracket on the player\'s screen (H2hCupMonthPicker)', () {
    test('a bracket with its one title stays three days, then goes', () {
      final state = _decemberCup(titles: 1);

      bool over(int day) => H2hCupMonthPicker.isOver(
        state,
        DateTime.utc(2026, 12, day),
        month: _december,
      );

      expect(over(25), isFalse);
      expect(over(26), isFalse, reason: 'three days after the 23rd');
      expect(over(27), isTrue);
    });

    test('a bracket with no title is never over', () {
      expect(
        H2hCupMonthPicker.isOver(
          _decemberCup(titles: 0),
          DateTime.utc(2027, 2),
          month: _december,
        ),
        isFalse,
      );
    });

    test('November\'s three paths need all three titles, as before', () {
      final one = H2hCupState(
        entries: _sixteen(),
        stages: [_stage(23)],
        titles: [_title(1)],
      );
      final three = H2hCupState(
        entries: _sixteen(),
        stages: [_stage(23)],
        titles: [_title(1), _title(2), _title(3)],
      );
      final later = DateTime.utc(2027, 2);

      expect(H2hCupMonthPicker.isOver(one, later, month: _november), isFalse);
      expect(H2hCupMonthPicker.isOver(three, later, month: _november), isTrue);
    });

    test(
      'pick shows the crowned bracket in its days, not after them',
      () async {
        final cups = _Cups({_december: _decemberCup(titles: 1)});

        final during = await H2hCupMonthPicker.pick(
          cups: cups,
          today: DateTime.utc(2026, 12, 25),
          user: userNo(1),
        );
        final after = await H2hCupMonthPicker.pick(
          cups: cups,
          today: DateTime.utc(2026, 12, 30),
          user: userNo(1),
        );

        expect((during as Ok<H2hCupMonthPick?>).value?.month, _december);
        expect((after as Ok<H2hCupMonthPick?>).value, isNull);
      },
    );
  });
}
