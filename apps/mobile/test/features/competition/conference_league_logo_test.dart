/// دوري المؤتمر الأوروبي (migration 0180): a fixture filed under it shows
/// the bundled mark on the league header of the real matches screen, fed by
/// a fake server, and the name's English aliases resolve to the same mark.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/competition_logo_assets.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const String _leagueName = 'دوري المؤتمر الأوروبي';
const String _markPath = 'assets/league_logos/conference-league.png';

Map<String, Object?> _item() => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'شهر 10',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Crystal Palace',
    awayTeam: 'Fiorentina',
    kickoffAt: futureIso(),
    leagueName: _leagueName,
  ),
  homeWinPercentage: 50,
  awayWinPercentage: 50,
).toJson();

Future<void> _pump(WidgetTester tester) async {
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
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('the league header shows the Conference League mark', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(_leagueName), findsWidgets);
    final Finder plate = find.byKey(const Key('competitionLogo.plate'));
    expect(plate, findsOneWidget);
    final Image logo = tester.widget<Image>(
      find.descendant(of: plate, matching: find.byType(Image)),
    );
    expect(logo.image, isA<AssetImage>());
    expect((logo.image as AssetImage).assetName, _markPath);
  });

  test('the catalog name and its English aliases resolve to the mark', () {
    for (final String name in <String>[
      _leagueName,
      ' دوري  المؤتمر الأوروبي ',
      'UEFA Conference League',
      'Conference League',
    ]) {
      expect(competitionLogoAsset(null, name), _markPath, reason: name);
    }
    expect(
      competitionLogoAsset(null, 'الدوري الأوروبي'),
      'assets/league_logos/europa-league.png',
    );
  });

  test('the mark loads from the bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final ByteData data = await rootBundle.load(_markPath);
    expect(data.lengthInBytes, greaterThan(0));
  });
}
