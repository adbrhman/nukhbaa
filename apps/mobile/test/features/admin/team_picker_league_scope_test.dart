/// The clubs the admin's match forms offer for a league
/// (`teamPickerLeagueOptions`, the function both forms' team fields call):
/// a national league its own clubs only; the AFC Champions League Elite
/// (continental, migration 0103) the clubs filed under it plus the ones on
/// its matches this month, by id or by name -- and the whole catalog only
/// when none of those matches what is typed.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/widgets/team_picker_league_scope.dart';

const LeagueDto _premier = LeagueDto(
  id: 'l-pl',
  name: 'الدوري الإنجليزي الممتاز',
  shortName: 'PL',
  logoUrl: null,
);

const LeagueDto _elite = LeagueDto(
  id: 'l-acle',
  name: 'دوري أبطال آسيا للنخبة',
  shortName: 'ACLE',
  logoUrl: null,
  isContinental: true,
);

const LeagueDto _saudi = LeagueDto(
  id: 'l-spl',
  name: 'دوري روشن السعودي',
  shortName: 'SPL',
  logoUrl: null,
);

TeamDto _team(String id, String name, [String? leagueId]) => TeamDto(
  id: id,
  name: name,
  shortName: null,
  crestUrl: null,
  leagueId: leagueId,
);

final List<TeamDto> _catalog = <TeamDto>[
  _team('t-new', 'نيوكاسل', 'l-pl'),
  _team('t-cov', 'كوفنتري سيتي', 'l-pl'),
  _team('t-ahl', 'الأهلي', 'l-spl'),
  _team('t-qad', 'القادسية', 'l-spl'),
  _team('t-was', 'الوصل'),
  _team('t-pak', 'باختاكور'),
  _team('t-sad', 'السد'),
];

SeasonFixtureCardDto _match(
  String id,
  String home,
  String away, {
  String? homeId,
  String? awayId,
  String? league,
}) => SeasonFixtureCardDto(
  seasonId: 'm-10',
  fixtureId: id,
  homeTeam: home,
  awayTeam: away,
  kickoffAt: '2026-10-12T16:00:00Z',
  homeTeamId: homeId,
  awayTeamId: awayId,
  leagueName: league,
);

final List<SeasonFixtureCardDto> _month = <SeasonFixtureCardDto>[
  // Al Wasl by id, Al Ahli only by name (a fixture entered before the id).
  _match(
    'f-1',
    'الوصل',
    'الأهلي',
    homeId: 't-was',
    league: 'دوري أبطال آسيا للنخبة',
  ),
  _match(
    'f-2',
    'باختاكور',
    'القادسية',
    homeId: 't-pak',
    awayId: 't-qad',
    league: 'دوري أبطال آسيا للنخبة',
  ),
  _match(
    'f-3',
    'كوفنتري سيتي',
    'نيوكاسل',
    homeId: 't-cov',
    awayId: 't-new',
    league: 'الدوري الإنجليزي الممتاز',
  ),
];

List<String> _options(
  String query,
  LeagueDto league, {
  bool fallback = false,
}) => teamPickerLeagueOptions(
  query,
  catalog: _catalog,
  league: league,
  monthFixtures: _month,
  fallbackToCatalog: fallback,
);

void main() {
  test('a national league offers its own clubs only', () {
    expect(_options('', _premier).toSet(), <String>{'نيوكاسل', 'كوفنتري سيتي'});
    expect(_options('', _saudi).toSet(), <String>{'الأهلي', 'القادسية'});
    expect(_options('الوصل', _premier), isEmpty);
  });

  test('the elite league offers the clubs on its matches, not the whole '
      'catalog', () {
    expect(_options('', _elite, fallback: true).toSet(), <String>{
      'الوصل',
      'الأهلي',
      'باختاكور',
      'القادسية',
    });
  });

  test('typing narrows the elite clubs', () {
    expect(_options('باخ', _elite, fallback: true), <String>['باختاكور']);
  });

  test('a club before its first elite match is still found by name', () {
    expect(_options('السد', _elite, fallback: true), <String>['السد']);
    expect(_options('السد', _elite), isEmpty);
  });

  test('a club on a match of another league is not an elite club', () {
    final TeamDto newcastle = _catalog.first;
    expect(
      teamPlaysInLeague(newcastle, league: _elite, monthFixtures: _month),
      isFalse,
    );
    expect(
      teamPlaysInLeague(newcastle, league: _premier, monthFixtures: _month),
      isTrue,
    );
  });

  test('each name is offered once', () {
    final List<TeamDto> twice = <TeamDto>[
      ..._catalog,
      _team('t-new-2', 'نيوكاسل', 'l-pl'),
    ];
    expect(
      teamPickerLeagueOptions(
        'نيو',
        catalog: twice,
        league: _premier,
        monthFixtures: _month,
        fallbackToCatalog: false,
      ),
      <String>['نيوكاسل'],
    );
  });
}
