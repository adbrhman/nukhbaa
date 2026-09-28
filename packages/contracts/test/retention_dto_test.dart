import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  const dto = AdminRetentionDto(
    today: '2026-09-29',
    weeks: [
      RetentionWeekDto(
        weekStart: '2026-09-28',
        complete: false,
        activeUsers: 10,
        active3Plus: 4,
        leagueActive: 5,
        leagueActive3Plus: 3,
        leagueMembers: 6,
        leagueReturned: null,
      ),
      RetentionWeekDto(
        weekStart: '2026-09-21',
        complete: true,
        activeUsers: 8,
        active3Plus: 2,
        leagueActive: 4,
        leagueActive3Plus: 2,
        leagueMembers: 5,
        leagueReturned: 4,
      ),
    ],
    cohorts: [
      RetentionCohortDto(
        weekStart: '2026-09-21',
        users: 7,
        day1: RetentionRateDto(eligible: 6, retained: 3),
        day7: RetentionRateDto(eligible: 2, retained: 1),
        day14: RetentionRateDto(eligible: 0, retained: 0),
        week4: RetentionRateDto(eligible: 0, retained: 0),
      ),
    ],
  );

  test('AdminRetentionDto round-trips through JSON', () {
    final back = AdminRetentionDto.fromJson(
      jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>,
    );

    expect(back.toJson(), dto.toJson());
    expect(back.weeks.first.leagueReturned, isNull);
  });

  test('shares are of the players a figure could judge', () {
    final RetentionWeekDto now = dto.weeks.first;
    final RetentionWeekDto last = dto.weeks.last;
    final RetentionCohortDto cohort = dto.cohorts.single;

    expect(now.active3PlusPercent, 40);
    expect(now.league3PlusPercent, 60);
    expect(now.others3PlusPercent, 20);
    expect(now.leagueRetentionPercent, isNull, reason: 'not known yet');
    expect(last.leagueRetentionPercent, 80);
    expect(cohort.day1.percent, 50);
    expect(cohort.day7.percent, 50);
    expect(cohort.day14.percent, isNull, reason: 'nobody judged yet');
  });

  test('a body missing keys reads as empty, not as a crash', () {
    final back = AdminRetentionDto.fromJson(const {});

    expect(back.weeks, isEmpty);
    expect(back.cohorts, isEmpty);
    expect(back.schemaVersion, 1);
  });
}
