/// Which clubs a league's team field offers in the admin's match forms.
///
/// A national league's clubs carry its id (migration 0035). A continental
/// league draws clubs whose row stays with their own league: the AFC
/// Champions League Elite reuses the Saudi rows and leaves the others
/// without a league (migration 0103). Its clubs are therefore the rows
/// filed under it plus every club already playing one of its matches in
/// the month. Until a club has played there, typing its name still finds
/// it in the whole catalog, so a continental field never comes up empty
/// for a real club (requested 2026-10-11: typing in a league offers that
/// league's clubs first).
library;

import 'package:contracts/contracts.dart';

import 'team_picker_aliases.dart';

/// Whether [team] plays in [league]: filed under it, or -- for a
/// continental league -- already on one of [monthFixtures] of that league.
bool teamPlaysInLeague(
  TeamDto team, {
  required LeagueDto league,
  required List<SeasonFixtureCardDto> monthFixtures,
}) {
  if (team.leagueId == league.id) return true;
  if (!league.isContinental) return false;
  final String leagueName = league.name.trim();
  for (final SeasonFixtureCardDto fixture in monthFixtures) {
    if ((fixture.leagueName ?? '').trim() != leagueName) continue;
    if (fixture.homeTeamId == team.id || fixture.awayTeamId == team.id) {
      return true;
    }
    for (final String? name in <String?>[fixture.homeTeam, fixture.awayTeam]) {
      if (name != null && teamPickerExactMatch(name, team.name)) return true;
    }
  }
  return false;
}

/// The club names a team field for [league] offers for [query], sorted,
/// each name once.
///
/// The league's own clubs come first and alone. When none of them matches
/// [query] and [fallbackToCatalog] is set, the whole catalog is searched
/// instead: a continental league's clubs before their first match there,
/// or a corrected fixture whose clubs predate any league.
List<String> teamPickerLeagueOptions(
  String query, {
  required List<TeamDto> catalog,
  required LeagueDto league,
  required List<SeasonFixtureCardDto> monthFixtures,
  required bool fallbackToCatalog,
}) {
  final List<String> inLeague = _names(query, <TeamDto>[
    for (final TeamDto team in catalog)
      if (teamPlaysInLeague(team, league: league, monthFixtures: monthFixtures))
        team,
  ]);
  if (inLeague.isNotEmpty || !fallbackToCatalog) return inLeague;
  return _names(query, catalog);
}

List<String> _names(String query, List<TeamDto> teams) {
  final Set<String> seen = <String>{};
  return <String>[
    for (final TeamDto team in teams)
      if (teamPickerMatchesQuery(query, team.name) &&
          seen.add(team.name.trim().toLowerCase()))
        team.name,
  ]..sort();
}
