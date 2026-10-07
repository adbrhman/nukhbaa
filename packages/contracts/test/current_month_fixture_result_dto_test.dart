import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

const _card = SeasonFixtureCardDto(
  seasonId: 's-1',
  fixtureId: 'f-1',
  homeTeam: 'Arsenal',
  awayTeam: 'Chelsea',
  kickoffAt: '2026-10-06T14:00:00.000Z',
);

void main() {
  test('the recorded result survives a JSON round trip', () {
    const dto = CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'PL',
      seasonLabel: '10/2026',
      fixture: _card,
      resultHomeGoals: 2,
      resultAwayGoals: 1,
    );

    final back = CurrentMonthFixtureItemDto.fromJson(dto.toJson());
    expect(back, dto);
    expect((back.resultHomeGoals, back.resultAwayGoals), (2, 1));
  });

  test('an older payload without a result decodes it as null', () {
    final dto = CurrentMonthFixtureItemDto.fromJson({
      'schema_version': 3,
      'competition_id': 'c-1',
      'competition_name': 'PL',
      'season_label': '10/2026',
      'fixture': _card.toJson(),
    });

    expect(dto.resultHomeGoals, isNull);
    expect(dto.resultAwayGoals, isNull);
  });
}
