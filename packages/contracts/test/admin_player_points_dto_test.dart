import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// A player's month on the wire (batch 146b).
void main() {
  test('a month survives the wire', () {
    const PlayerMonthPointsDto month = PlayerMonthPointsDto(
      played: true,
      monthPoints: 3,
      streakBonus: 2,
      entries: <PlayerPointEntryDto>[
        PlayerPointEntryDto(
          id: 'e1',
          fixtureId: 'f1',
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          kind: 'fixture_score',
          amount: 3,
          occurredAt: '2026-10-10T21:00:00.000Z',
        ),
        PlayerPointEntryDto(
          id: 'e2',
          fixtureId: 'f2',
          kind: 'correction',
          amount: -1,
          occurredAt: '2026-10-12T09:00:00.000Z',
        ),
      ],
    );

    final PlayerMonthPointsDto back = PlayerMonthPointsDto.fromJson(
      month.toJson(),
    );

    expect(back.toJson(), month.toJson());
    expect(back.entries.last.homeTeam, isNull);
    expect(back.entries.last.amount, -1);
  });

  test('a month never played', () {
    final PlayerMonthPointsDto back =
        PlayerMonthPointsDto.fromJson(const <String, Object?>{
          'schema_version': 1,
          'played': false,
          'month_points': 0,
          'streak_bonus': 0,
          'entries': <Object?>[],
        });

    expect(back.played, isFalse);
    expect(back.entries, isEmpty);
  });
}
