import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

const _card = SeasonFixtureCardDto(
  seasonId: 's-1',
  fixtureId: 'f-1',
  homeTeam: 'Arsenal',
  awayTeam: 'Chelsea',
  kickoffAt: '2026-09-19T14:00:00.000Z',
);

void main() {
  test('the live score survives a JSON round trip', () {
    const dto = CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'PL',
      seasonLabel: '09/2026',
      fixture: _card,
      liveHomeGoals: 2,
      liveAwayGoals: 1,
      liveMinute: 67,
      liveFinished: false,
    );

    expect(CurrentMonthFixtureItemDto.fromJson(dto.toJson()), dto);
  });

  test('an older payload without live fields decodes them as null', () {
    final dto = CurrentMonthFixtureItemDto.fromJson({
      'schema_version': 2,
      'competition_id': 'c-1',
      'competition_name': 'PL',
      'season_label': '09/2026',
      'fixture': _card.toJson(),
    });

    expect(dto.liveHomeGoals, isNull);
    expect(dto.liveFinished, isNull);
  });
}
