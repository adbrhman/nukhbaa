/// دوري المؤتمر الأوروبي (migration 0181): each of its 36 clubs, by the
/// name the catalog stores, resolves through the fixture card's own entry
/// point (`resolveTeamIdentity`) to its crest in the owner's list (script
/// 266); the other spellings 0181 reuses a club by resolve too; and on the
/// real matches screen, fed by a fake server, a Conference League fixture
/// draws both crests once the phone holds their files.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/crests/club_crests.dart';
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';
import '../../support/team_marks.dart';

/// `football_data.teams.name` as 0181 writes it (or finds it) -> the slug of
/// its crest in the owner's list.
const Map<String, String> _clubs = <String, String>{
  'آرهوس': 'agf',
  'أياكس': 'ajax',
  'موناكو': 'monaco',
  'أتالانتا': 'atalanta',
  'بوراتس بانيا لوكا': 'borac',
  'بران': 'brann',
  'برايتون': 'brighton',
  'كوبنهاغن': 'copenhagen',
  'النجم الأحمر': 'crvena-zvezda',
  'سسكا صوفيا': 'cska-sofia',
  'إغناتيا': 'egnatia',
  'فرايبورغ': 'freiburg',
  'غينت': 'gent',
  'خيتافي': 'getafe',
  'هايدوك سبليت': 'hajduk-split',
  'هارتس': 'hearts',
  'إيبيريا تبليسي': 'iberia',
  'إنتر إسكالديس': 'inter-escaldes',
  'يابلونتس': 'jablonec',
  'كايرات ألماتي': 'kairat',
  'كاونو جالغيريس': 'kauno-zalgiris',
  'كوبس': 'kups',
  'لينكولن ريد إمبس': 'lincoln-red-imps',
  'لوغانو': 'lugano',
  'ميتيلاند': 'midtjylland',
  'ميالبي': 'mjallby',
  'نوردشيلاند': 'nordsjaelland',
  'بافوس': 'pafos',
  'باناثينايكوس': 'panathinaikos',
  'ريغا': 'riga',
  'براغا': 'sc-braga',
  'سانت تروند': 'sint-truidense',
  'تون': 'thun',
  'طرابزون سبور': 'trabzonspor',
  'تفينتي': 'twente',
  'أونيفيرسيتاتيا كرايوفا': 'u-craiova',
};

/// The other spellings 0181 matches a club by.
const Map<String, String> _spellings = <String, String>{
  'أرهوس': 'agf',
  'أغف آرهوس': 'agf',
  'أياكس أمستردام': 'ajax',
  'بوراتس': 'borac',
  'بران بيرغن': 'brann',
  'برايتون آند هوف ألبيون': 'brighton',
  'كوبنهاجن': 'copenhagen',
  'إف سي كوبنهاغن': 'copenhagen',
  'النجم الأحمر بلغراد': 'crvena-zvezda',
  'ريد ستار': 'crvena-zvezda',
  'ريد ستار بلغراد': 'crvena-zvezda',
  'تسرفينا زفيزدا': 'crvena-zvezda',
  'زسكا صوفيا': 'cska-sofia',
  'إيغناتيا': 'egnatia',
  'جنت': 'gent',
  'خنت': 'gent',
  'هايدوك': 'hajduk-split',
  'هارتس أوف ميدلوثيان': 'hearts',
  'إيبيريا 1999': 'iberia',
  'إيبيريا': 'iberia',
  'إنتر كلوب إسكالديس': 'inter-escaldes',
  'يابلونيتس': 'jablonec',
  'كايرات': 'kairat',
  'جالغيريس كاوناس': 'kauno-zalgiris',
  'كوبس كوبيو': 'kups',
  'لينكولن': 'lincoln-red-imps',
  'ميدتيلاند': 'midtjylland',
  'نوردسيلاند': 'nordsjaelland',
  'ريغا إف سي': 'riga',
  'سبورتينغ براغا': 'sc-braga',
  'سينت ترويدن': 'sint-truidense',
  'إف سي تون': 'thun',
  'طرابزونسبور': 'trabzonspor',
  'توينتي': 'twente',
  'يونيفرسيتاتيا كرايوفا': 'u-craiova',
  'كرايوفا': 'u-craiova',
};

Map<String, Object?> _item() => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'شهر 10',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'النجم الأحمر',
    awayTeam: 'كوبنهاغن',
    kickoffAt: futureIso(),
    leagueName: 'دوري المؤتمر الأوروبي',
  ),
  homeWinPercentage: 50,
  awayWinPercentage: 50,
).toJson();

Future<void> _pump(WidgetTester tester, ClubCrests crests) async {
  final harness = buildCurrentMonthFixturesHarness((request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([_item()]);
      case '/me/fixture-predictions':
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        builder: (context, child) =>
            ClubCrestScope(crests: crests, child: child!),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  test('each club resolves through its catalog row to a crest', () {
    final List<TeamDto> catalog = <TeamDto>[
      for (final MapEntry<String, String> club in _clubs.entries)
        TeamDto(
          id: 'id-${club.value}',
          name: club.key,
          shortName: null,
          crestUrl: null,
        ),
    ];
    expect(_clubs.length, 36);
    for (final MapEntry<String, String> club in _clubs.entries) {
      final ResolvedTeamIdentity identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: 'id-${club.value}',
        teamName: null,
      );
      expect(identity.crestSlug, club.value, reason: club.key);
      expect(kTeamMarkSlugs, contains(club.value), reason: club.key);
    }
  });

  test('the other spellings resolve by name alone', () {
    for (final MapEntry<String, String> name in _spellings.entries) {
      final ResolvedTeamIdentity identity = resolveTeamIdentity(
        catalog: null,
        teamId: null,
        teamName: name.key,
      );
      expect(identity.crestSlug, name.value, reason: name.key);
    }
  });

  testWidgets('a Conference League fixture draws both crests', (tester) async {
    final ClubCrests crests = await crestsHolding(<String>[
      'crvena-zvezda',
      'copenhagen',
    ]);
    addTearDown(crests.dispose);
    await _pump(tester, crests);

    for (final String slug in <String>['crvena-zvezda', 'copenhagen']) {
      expect(
        find.byKey(ValueKey<String>('teamLogo.crest.$slug')),
        findsWidgets,
        reason: slug,
      );
    }
  });

  testWidgets('without their files the cards draw the discs', (tester) async {
    final ClubCrests crests = ClubCrests.inert();
    addTearDown(crests.dispose);
    await _pump(tester, crests);

    expect(
      find.byKey(const ValueKey<String>('teamLogo.crest.crvena-zvezda')),
      findsNothing,
    );
    expect(find.text('النجم الأحمر'), findsWidgets);
  });
}
