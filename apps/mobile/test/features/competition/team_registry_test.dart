/// The name lookup behind every crest and Arabic team name (audit L-08):
/// a feed's spelling of a known team still finds it, and a different team
/// whose name merely contains a known one is never taken for it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_registry.dart';

void main() {
  test("a feed's spelling of a known team finds it", () {
    expect(teamDisplayName('Al Hilal'), 'الهلال');
    expect(teamDisplayName('Al-Hilal'), 'الهلال');
    expect(teamDisplayName('Al Hilal SFC'), 'الهلال');
    expect(teamDisplayName('Al Ahli Saudi FC'), 'الأهلي');
    expect(teamDisplayName('Arsenal FC'), kEplTeams['Arsenal']!.ar);
    expect(teamDisplayName('man united'), kEplTeams['Manchester United']!.ar);
    expect(
      teamDisplayName('Brighton & Hove Albion'),
      kEplTeams['Brighton']!.ar,
    );
    expect(teamDisplayName('AFC Bournemouth'), kEplTeams['Bournemouth']!.ar);
  });

  test('a team whose name contains a known one is not that team', () {
    expect(lookupTeam('Al Hilal Omdurman'), isNull);
    expect(lookupTeam('Shabab Al Ahli'), isNull);
    expect(lookupTeam('Al Ahly SC'), isNull, reason: 'Egypt, not Saudi');
    expect(lookupTeam('United'), isNull);
    expect(lookupTeam('Hilal'), isNull);
    expect(teamDisplayName('Al Hilal Omdurman'), 'Al Hilal Omdurman');
  });

  test('nothing known, nothing guessed', () {
    expect(lookupTeam(null), isNull);
    expect(lookupTeam('  '), isNull);
    expect(teamDisplayName(null), '؟');
    expect(teamDisplayName('Some Unknown FC'), 'Some Unknown FC');
  });
}
