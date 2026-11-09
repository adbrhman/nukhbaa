import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

/// The Elite Cup of November as stored: only its state is asked.
final class _Cups implements H2hCupStore {
  _Cups({this.entries = const <H2hCupEntry>[], this.titles = 0});

  final List<H2hCupEntry> entries;
  final int titles;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async => Result.ok(
    H2hCupState(
      entries: entries,
      stages: const <H2hCupStage>[],
      titles: [
        for (var place = 1; place <= titles; place++)
          H2hCupTitle(
            place: place,
            champion: userNo(place),
            runnerUp: null,
            how: 'final',
          ),
      ],
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupEntry _entry(int place) => H2hCupEntry(
  userId: userNo(place),
  place: place,
  groupNumber: 1,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// Nineteen November rounds, as a month that finished its league has.
FakeH2hRoundStore _novemberLeague() {
  final rounds = FakeH2hRoundStore();
  for (var n = 1; n <= 19; n++) {
    rounds.addRound(
      H2hRound(
        id: H2hRoundId('00000000-0000-4000-8000-000000000${200 + n}'),
        monthStart: _november,
        number: n,
        day: DateTime.utc(2026, 11, n),
        fixtureCount: 8,
        approvedBy: null,
        lockedAt: DateTime.utc(2026, 11, n, 12),
      ),
    );
  }
  return rounds;
}

FakeH2hLeagueStore _novemberDrawn() => FakeH2hLeagueStore()
  ..months[_november] = H2hMonthInfo(
    monthStart: _november,
    isPilot: false,
    seatedCount: 80,
  );

/// The terms of the contest: the month's head-to-head rounds do not begin
/// until the Elite Cup of the month before is finished and its champions are
/// crowned, even when that takes the cup into the new month.
void main() {
  // 01:00 Riyadh on 4 December: the 5th has eight fixtures, its first
  // kickoff within 24 hours.
  final now = DateTime.utc(2026, 12, 4, 22);
  final fifth = DateTime.utc(2026, 12, 5);

  FakeH2hRoundStore decemberWithADay() =>
      _novemberLeague()..dayOf(fifth, 8, DateTime.utc(2026, 12, 5, 15));

  Future<int> approved(H2hCupStore? cups, FakeH2hRoundStore rounds) async {
    final result = await RunH2hRounds(
      rounds: rounds,
      leagues: _novemberDrawn(),
      idGenerator: SequenceIds(),
      cups: cups,
    ).call(now: now);
    return (result as Ok<H2hRoundsRun>).value.approved;
  }

  test('a cup still to play holds the new month\'s rounds back', () async {
    final rounds = decemberWithADay();

    final count = await approved(
      _Cups(entries: [_entry(1), _entry(2), _entry(3)], titles: 1),
      rounds,
    );

    expect(count, 0);
    expect(rounds.byMonth[DateTime.utc(2026, 12)], isNull);
  });

  test('once the three paths are crowned the next day is a round', () async {
    final rounds = decemberWithADay();

    final count = await approved(
      _Cups(entries: [_entry(1), _entry(2), _entry(3)], titles: 3),
      rounds,
    );

    expect(count, 1);
    expect(rounds.byMonth[DateTime.utc(2026, 12)]!.single.day, fifth);
  });

  test('a month with no cup entries holds nothing back', () async {
    final rounds = decemberWithADay();

    expect(await approved(_Cups(), rounds), 1);
  });

  test('a month that never finished its league holds nothing back', () async {
    final rounds = FakeH2hRoundStore()
      ..addRound(
        H2hRound(
          id: const H2hRoundId('00000000-0000-4000-8000-000000000301'),
          monthStart: _november,
          number: 1,
          day: DateTime.utc(2026, 11, 3),
          fixtureCount: 8,
          approvedBy: null,
          lockedAt: DateTime.utc(2026, 11, 3, 12),
        ),
      )
      ..dayOf(fifth, 8, DateTime.utc(2026, 12, 5, 15));

    final count = await approved(
      _Cups(entries: [_entry(1)], titles: 0),
      rounds,
    );

    expect(count, 1);
  });

  test('without a cup store (the cup is off) nothing is held back', () async {
    final rounds = decemberWithADay();

    expect(await approved(null, rounds), 1);
  });

  test('November itself is not held back: no cup before it', () async {
    // 01:00 Riyadh on 4 November; October had no Elite Cup.
    final rounds = FakeH2hRoundStore()
      ..dayOf(DateTime.utc(2026, 11, 5), 8, DateTime.utc(2026, 11, 5, 15));

    final result = await RunH2hRounds(
      rounds: rounds,
      leagues: FakeH2hLeagueStore(),
      idGenerator: SequenceIds(),
      cups: _Cups(entries: [_entry(1)], titles: 0),
    ).call(now: DateTime.utc(2026, 11, 4, 22));

    expect((result as Ok<H2hRoundsRun>).value.approved, 1);
  });
}
