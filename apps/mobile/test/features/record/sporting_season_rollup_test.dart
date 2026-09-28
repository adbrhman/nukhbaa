/// Pins which sporting season a month rolls into now that a month opens at
/// 00:00 Riyadh, 21:00 UTC the evening before (migration 0076).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/record/my_seasons_screen.dart';

MySeasonRecordDto _month(
  String label,
  String startAt,
  String endAt,
  int points,
) => MySeasonRecordDto(
  competitionId: 'c7600000-0000-4000-8000-000000000001',
  competitionName: 'Monthly',
  seasonId: 'season-$label',
  seasonLabel: label,
  startAt: startAt,
  endAt: endAt,
  rank: 1,
  totalPoints: points,
);

void main() {
  test('a month opening at midnight Riyadh stays in the season it names', () {
    final List<SportingSeasonTotal> totals = rollUpSeasons(<MySeasonRecordDto>[
      _month(
        '07/2027',
        '2027-06-30T21:00:00.000Z',
        '2027-07-31T21:00:00.000Z',
        5,
      ),
      _month(
        '08/2027',
        '2027-07-31T21:00:00.000Z',
        '2027-08-31T21:00:00.000Z',
        7,
      ),
    ]);

    expect(
      totals.map((SportingSeasonTotal t) => t.cycleLabel).toList(),
      <String>['2027/28', '2026/27'],
    );
    expect(totals.first.totalPoints, 7);
    expect(totals.last.totalPoints, 5);
  });

  test('a month stored at 00:00 UTC before the change rolls up as before', () {
    final List<SportingSeasonTotal> totals = rollUpSeasons(<MySeasonRecordDto>[
      _month(
        '09/2026',
        '2026-09-01T00:00:00.000Z',
        '2026-09-30T21:00:00.000Z',
        3,
      ),
      _month(
        '10/2026',
        '2026-09-30T21:00:00.000Z',
        '2026-10-31T21:00:00.000Z',
        4,
      ),
    ]);

    expect(totals, hasLength(1));
    expect(totals.single.cycleLabel, '2026/27');
    expect(totals.single.totalPoints, 7);
  });
}
