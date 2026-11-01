import 'package:application/application.dart';
import 'package:server/provider_sync/phase_one_rules.dart';
import 'package:test/test.dart';

// Script 190: the owner's daily selection, as configured.
void main() {
  test('the seven leagues, in the owner order, each with a provider rule', () {
    expect(
      [for (final league in dailySelectionLeagues) league.leagueName],
      [
        'الدوري الإسباني',
        'الدوري الألماني',
        'الدوري الإيطالي',
        'الدوري الأوروبي',
        'الدوري الفرنسي',
        'كأس الرابطة الإنجليزية',
        'دوري روشن السعودي',
      ],
    );
    final ruled = {for (final rule in phaseOneRules) rule.leagueName};
    for (final league in dailySelectionLeagues) {
      expect(ruled, contains(league.leagueName));
    }
  });

  test('the Premier League and the Champions League are never chosen', () {
    final chosen = {
      for (final league in dailySelectionLeagues) league.leagueName,
    };
    expect(chosen, isNot(contains('الدوري الإنجليزي الممتاز')));
    expect(chosen, isNot(contains('دوري أبطال أوروبا')));
  });

  test('the Roshan League alone is guaranteed; the League Cup is scored '
      'by the Premier League table', () {
    expect(
      [
        for (final league in dailySelectionLeagues)
          if (league.guaranteed) league.leagueName,
      ],
      ['دوري روشن السعودي'],
    );
    final cup = dailySelectionLeagues.firstWhere(
      (league) => league.leagueName == 'كأس الرابطة الإنجليزية',
    );
    expect(cup.standings.key, 'football-data:PL');
    expect(cup.outsideTableIsLast, isTrue);
  });

  test('the numbers decided on 2026-11-01', () {
    expect(dailySelectionPolicy.minimum, 10);
    expect(dailySelectionPolicy.target, 15);
    expect(dailySelectionPolicy.busyTarget, 20);
    expect(dailySelectionPolicy.busyLeagues, hasLength(4));
    expect(dailyShortfallRecipient, 'adbrhmanm@gmail.com');
  });

  test('every big club is a provider team ref', () {
    expect(dailySelectionBigClubs, isNotEmpty);
    for (final ref in dailySelectionBigClubs) {
      expect(ref, matches(RegExp(r'^(football-data|highlightly):\d+$')));
    }
    expect(dailySelectionBigClubs, contains('highlightly:2495916'));
  });

  test('a variable left unset starts the trial', () {
    expect(DailySelectionMode.parse(null), DailySelectionMode.shadow);
    expect(DailySelectionMode.parse(' ON '), DailySelectionMode.on);
    expect(DailySelectionMode.parse('off'), DailySelectionMode.off);
  });
}
