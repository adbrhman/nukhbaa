import 'package:application/application.dart';
import 'package:server/provider_sync/phase_one_rules.dart';
import 'package:test/test.dart';

PendingMatchDetails _match(String league, Set<String> home, Set<String> away) =>
    PendingMatchDetails(
      fixtureId: 'f-1',
      kickoffAt: DateTime.utc(2026, 11, 1, 20),
      leagueName: league,
      homeGoals: 1,
      awayGoals: 1,
      homeTeamRefs: home,
      awayTeamRefs: away,
    );

void main() {
  test('every Premier League match is read', () {
    expect(
      matchDetailsScope.covers(
        _match('الدوري الإنجليزي الممتاز', {'football-data:57'}, {}),
      ),
      isTrue,
    );
  });

  test('the Clasico is read in the league and the Champions League alike, '
      'an ordinary Real Madrid match is not', () {
    for (final league in ['الدوري الإسباني', 'دوري أبطال أوروبا']) {
      expect(
        matchDetailsScope
            .derbyOf(
              _match(
                league,
                {'football-data:81'},
                {'football-data:86', 'highlightly:461175'},
              ),
            )
            ?.name,
        'الكلاسيكو',
      );
    }
    expect(
      matchDetailsScope.covers(
        _match('الدوري الإسباني', {'football-data:86'}, {'football-data:92'}),
      ),
      isFalse,
    );
  });

  test('the Riyadh and Jeddah derbies are read by their Highlightly ids', () {
    expect(
      matchDetailsScope
          .derbyOf(
            _match(
              'دوري روشن السعودي',
              {'highlightly:2501873'},
              {'highlightly:2495916'},
            ),
          )
          ?.name,
      'ديربي الرياض',
    );
    expect(
      matchDetailsScope.covers(
        _match(
          'دوري روشن السعودي',
          {'highlightly:2501022'},
          {'highlightly:2493363'},
        ),
      ),
      isTrue,
    );
  });

  test('eleven derbies, no club against itself', () {
    expect(matchDetailsScope.derbies, hasLength(11));
    for (final derby in matchDetailsScope.derbies) {
      expect(derby.first.intersection(derby.second), isEmpty);
    }
  });
}
