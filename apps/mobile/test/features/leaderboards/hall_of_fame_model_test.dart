/// The Hall of Fame is worked out, never typed in: these pin the rules that
/// work it out -- the order of the record of titles, the three records and
/// their ties, the lead over the runner-up, and who counts as a legend.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/hall_of_fame_model.dart';

MonthChampionDto _champion({
  required String month,
  required String userId,
  int points = 100,
  int exact = 20,
  int day = 1,
}) {
  final String id = 's-$month';
  return MonthChampionDto(
    seasonId: id,
    seasonLabel: '$month/2026',
    userId: userId,
    displayName: 'name-$userId',
    points: points,
    exactCount: exact,
    decidedCount: 200,
    crownedAt: DateTime.utc(2026, int.parse(month) + 1, day).toIso8601String(),
    celebrateUntil: DateTime.utc(
      2026,
      int.parse(month) + 1,
      3,
    ).toIso8601String(),
  );
}

MonthPodiumDto _second(String month, int points) => MonthPodiumDto(
  seasonId: 's-$month',
  place: 2,
  userId: 'runner-$month',
  displayName: 'runner-$month',
  points: points,
  exactCount: 10,
  decidedCount: 100,
);

MonthChampionsDto _dto(
  List<MonthChampionDto> champions, [
  List<MonthPodiumDto> podium = const <MonthPodiumDto>[],
]) => MonthChampionsDto(champions: champions, podium: podium);

void main() {
  group('the record of titles', () {
    test('orders players by titles, the earlier first title winning a tie', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '12', userId: 'c'),
          _champion(month: '11', userId: 'a'),
          _champion(month: '10', userId: 'b'),
          _champion(month: '09', userId: 'a'),
        ]),
      );
      expect(hall.holders.map((h) => h.userId), <String>['a', 'b', 'c']);
      expect(hall.holders.first.count, 2);
      expect(hall.holders.first.titles.first.seasonLabel, '11/2026');
    });

    test('groups the champions of one month together, newest month first', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '09', userId: 'a'),
          _champion(month: '10', userId: 'b'),
          _champion(month: '10', userId: 'c'),
        ]),
      );
      expect(hall.months.length, 2);
      expect(hall.months.first.map((c) => c.userId), <String>['b', 'c']);
    });

    test('nothing crowned: an empty hall, no records, no legends', () {
      final HallOfFame hall = buildHallOfFame(_dto(const <MonthChampionDto>[]));
      expect(hall.isEmpty, isTrue);
      expect(hall.records, isEmpty);
      expect(hall.legends, isEmpty);
    });
  });

  group('the records', () {
    test('most points and most exact name the best month, ties share it', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '09', userId: 'a', points: 132, exact: 40),
          _champion(month: '10', userId: 'b', points: 138, exact: 40),
        ]),
      );
      final HallRecord points = hall.records.firstWhere(
        (r) => r.kind == HallRecordKind.mostPoints,
      );
      final HallRecord exact = hall.records.firstWhere(
        (r) => r.kind == HallRecordKind.mostExact,
      );
      expect(points.value, 138);
      expect(points.holders.map((c) => c.userId), <String>['b']);
      expect(exact.value, 40);
      expect(exact.holders.map((c) => c.userId).toSet(), <String>{'a', 'b'});
    });

    test('the widest lead is the champion over the runner-up', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(
          <MonthChampionDto>[
            _champion(month: '09', userId: 'a', points: 132),
            _champion(month: '10', userId: 'b', points: 138),
          ],
          <MonthPodiumDto>[_second('09', 100), _second('10', 130)],
        ),
      );
      final HallRecord margin = hall.records.firstWhere(
        (r) => r.kind == HallRecordKind.biggestMargin,
      );
      expect(margin.value, 32);
      expect(margin.holders.single.userId, 'a');
    });

    test(
      'no runner-up on file, or two champions in a month: no lead record',
      () {
        final HallOfFame none = buildHallOfFame(
          _dto(<MonthChampionDto>[_champion(month: '09', userId: 'a')]),
        );
        expect(
          none.records.any((r) => r.kind == HallRecordKind.biggestMargin),
          isFalse,
        );
        final HallOfFame tied = buildHallOfFame(
          _dto(
            <MonthChampionDto>[
              _champion(month: '09', userId: 'a'),
              _champion(month: '09', userId: 'b'),
            ],
            <MonthPodiumDto>[_second('09', 90)],
          ),
        );
        expect(
          tied.records.any((r) => r.kind == HallRecordKind.biggestMargin),
          isFalse,
        );
      },
    );

    test('a zero is not a record', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '09', userId: 'a', points: 0, exact: 0),
        ]),
      );
      expect(hall.records, isEmpty);
    });
  });

  group('the legends', () {
    test('two crowned months make no legend, whoever holds the records', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '09', userId: 'a', points: 132),
          _champion(month: '10', userId: 'b', points: 138),
        ]),
      );
      expect(hall.legends, isEmpty);
    });

    test('three monthly titles make a legend, with that reason', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '09', userId: 'a', points: 90, exact: 10),
          _champion(month: '10', userId: 'a', points: 91, exact: 11),
          _champion(month: '11', userId: 'a', points: 92, exact: 12),
          _champion(month: '12', userId: 'b', points: 200, exact: 50),
        ]),
      );
      final HallLegend legend = hall.legends.firstWhere(
        (l) => l.holder.userId == 'a',
      );
      expect(legend.byTitles, isTrue);
      expect(legend.holder.count, 3);
    });

    test('with three months crowned a record holder is a legend', () {
      final HallOfFame hall = buildHallOfFame(
        _dto(<MonthChampionDto>[
          _champion(month: '09', userId: 'a', points: 90, exact: 10),
          _champion(month: '10', userId: 'b', points: 91, exact: 11),
          _champion(month: '11', userId: 'c', points: 99, exact: 30),
        ]),
      );
      expect(hall.legends.map((l) => l.holder.userId), <String>['c']);
      expect(hall.legends.single.byTitles, isFalse);
      expect(
        hall.legends.single.records,
        containsAll(<HallRecordKind>[
          HallRecordKind.mostPoints,
          HallRecordKind.mostExact,
        ]),
      );
    });
  });

  group('the sporting season', () {
    test('September opens a season and August still belongs to it', () {
      expect(
        SportingSeasonWindow.at(DateTime.utc(2026, 11, 7)).label,
        '2026/2027',
      );
      expect(
        SportingSeasonWindow.at(DateTime.utc(2027, 8, 31)).label,
        '2026/2027',
      );
      expect(
        SportingSeasonWindow.at(DateTime.utc(2027, 9, 1)).label,
        '2027/2028',
      );
      expect(SportingSeasonWindow.at(DateTime.utc(2027, 1, 5)).endYear, 2027);
    });
  });
}
