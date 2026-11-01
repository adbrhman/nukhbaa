import 'package:application/src/football_data/ports/match_details.dart';

/// One derby: two clubs, each named by its provider team refs
/// (`'<source>:<team id>'`, as `football_data.external_identity_map` keeps
/// them). Either may play at home.
final class MatchDetailsDerby {
  /// Creates the derby.
  const MatchDetailsDerby(this.name, this.first, this.second);

  /// What it is called, for the log and the tests.
  final String name;

  /// The refs of one club.
  final Set<String> first;

  /// The refs of the other club.
  final Set<String> second;

  /// Whether [home] against [away] is this derby, in either order.
  bool between(Set<String> home, Set<String> away) =>
      (_isClub(home, first) && _isClub(away, second)) ||
      (_isClub(home, second) && _isClub(away, first));

  static bool _isClub(Set<String> refs, Set<String> club) =>
      refs.any(club.contains);
}

/// Which finished matches get their details read (decided by the owner on
/// 2026-11-01, script 188): every match of [fullLeagues], and elsewhere a
/// derby only. Any other match is closed without a provider request, so it
/// costs nothing from the daily quota and its page says there are none.
final class MatchDetailsScope {
  /// Creates the scope.
  const MatchDetailsScope({required this.fullLeagues, required this.derbies});

  /// League names (`football_data.leagues.name`) read in full.
  final Set<String> fullLeagues;

  /// The derbies read in any league.
  final List<MatchDetailsDerby> derbies;

  /// Whether the details of [fixture] are read.
  bool covers(PendingMatchDetails fixture) =>
      fullLeagues.contains(fixture.leagueName.trim()) ||
      derbyOf(fixture) != null;

  /// The derby [fixture] is, if any.
  MatchDetailsDerby? derbyOf(PendingMatchDetails fixture) {
    for (final derby in derbies) {
      if (derby.between(fixture.homeTeamRefs, fixture.awayTeamRefs)) {
        return derby;
      }
    }
    return null;
  }
}
