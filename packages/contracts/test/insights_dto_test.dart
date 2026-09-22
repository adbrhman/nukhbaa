import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('InsightsDto round-trips through encoded JSON', () {
    const dto = InsightsDto(
      month: AccuracyDto(decided: 4, correct: 3, exact: 1, percent: 75),
      communityPercent: 58,
      leagues: [
        LeagueAccuracyDto(
          name: 'L1',
          accuracy: AccuracyDto(decided: 4, correct: 3, exact: 1, percent: 75),
        ),
      ],
      longestCorrectRun: 3,
      weeks: [
        WeekAccuracyDto(
          weekStart: '2026-09-14',
          accuracy: AccuracyDto(decided: 0, correct: 0, exact: 0),
        ),
      ],
      lastWeek: WeekRecapDto(
        weekStart: '2026-09-14',
        accuracy: AccuracyDto(decided: 2, correct: 2, exact: 1, percent: 100),
        points: 4,
        best: BestPredictionDto(
          homeTeam: 'home',
          awayTeam: 'away',
          points: 3,
          exact: true,
        ),
      ),
    );

    final decoded = InsightsDto.fromJson(
      jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>,
    );

    expect(decoded.month.percent, 75);
    expect(decoded.communityPercent, 58);
    expect(decoded.leagues.single.name, 'L1');
    expect(decoded.weeks.single.accuracy.percent, isNull);
    expect(decoded.lastWeek!.best!.exact, isTrue);
    expect(decoded.toJson(), dto.toJson());
  });

  test('an empty body reads as nothing, not zeros', () {
    final dto = InsightsDto.fromJson(const {});

    expect(dto.month.percent, isNull);
    expect(dto.lastWeek, isNull);
    expect(dto.leagues, isEmpty);
  });
}
