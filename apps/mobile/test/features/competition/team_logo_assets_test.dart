import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, String> expectedAssets = <String, String>{
    'Juventus': 'juventus',
    'Auckland FC': 'auckland-fc',
    'Paris Saint-Germain': 'paris-saint-germain',
    'PSG': 'paris-saint-germain',
    'Manchester City': 'manchester-city',
    'Al Ain': 'al-ain',
    'Al Ain FC': 'al-ain',
    'Mamelodi Sundowns': 'mamelodi-sundowns',
    'Chelsea': 'chelsea',
    'Seattle Sounders FC': 'seattle-sounders-fc',
    'Al Hilal': 'al-hilal',
    'FC Porto': 'fc-porto',
    'Inter Miami': 'inter-miami-cf',
    'Inter Miami CF': 'inter-miami-cf',
    'Espérance': 'esperance',
    'Espérance Tunis': 'esperance',
    'Espérance de Tunis': 'esperance',
    'Pachuca': 'pachuca',
    'Borussia Dortmund': 'borussia-dortmund',
    'Palmeiras': 'palmeiras',
    'Wydad AC': 'wydad-ac',
    'Boca Juniors': 'boca-juniors',
    'Urawa Reds': 'urawa-reds',
    'Urawa Red Diamonds': 'urawa-reds',
    'Los Angeles FC': 'los-angeles-fc',
    'Botafogo': 'botafogo',
    'Ulsan HD FC': 'ulsan-hd-fc',
    'Fluminense': 'fluminense',
    'RB Salzburg': 'salzburg',
    'Red Bull Salzburg': 'salzburg',
    'Flamengo': 'flamengo',
    'Auckland City FC': 'auckland-city-fc',
    'Al Ahli': 'al-ahli',
    'Bayern Munich': 'bayern-munchen',
    'Benfica': 'benfica',
    'Monterrey': 'monterrey',
    'River Plate': 'river-plate',
    'Atletico Atlanta': 'atletico-atlanta',
    'Atlético Atlanta': 'atletico-atlanta',
    'Real Madrid': 'real-madrid',
  };

  test('resolves supplied Club World Cup team names to local assets', () {
    for (final MapEntry<String, String> entry in expectedAssets.entries) {
      expect(
        teamLogoAssetPath(entry.key),
        'assets/team_logos/${entry.value}.png',
        reason: entry.key,
      );
    }
  });

  test(
    'every supplied new crest and the competition logo load from assets',
    () async {
      for (final String slug in <String>[
        'auckland-fc',
        'al-ain',
        'mamelodi-sundowns',
        'seattle-sounders-fc',
        'inter-miami-cf',
        'esperance',
        'pachuca',
        'palmeiras',
        'wydad-ac',
        'boca-juniors',
        'urawa-reds',
        'los-angeles-fc',
        'botafogo',
        'ulsan-hd-fc',
        'fluminense',
        'flamengo',
        'auckland-city-fc',
        'monterrey',
        'river-plate',
        'atletico-atlanta',
      ]) {
        await rootBundle.load('assets/team_logos/$slug.png');
      }
      await rootBundle.load('assets/league_logos/fifa-club-world-cup.png');
    },
  );

  test('every UEFA national side crest loads from assets', () async {
    for (final String slug in <String>[
      'albania',
      'andorra',
      'armenia',
      'austria',
      'azerbaijan',
      'belarus',
      'belgium',
      'bosnia-herzegovina',
      'bulgaria',
      'croatia',
      'cyprus',
      'czech-republic',
      'denmark',
      'netherlands',
      'england',
      'estonia',
      'faroe-islands',
      'finland',
      'france',
      'georgia',
      'germany',
      'gibraltar',
      'greece',
      'hungary',
      'iceland',
      'israel',
      'italy',
      'kazakhstan',
      'kosovo',
      'latvia',
      'liechtenstein',
      'lithuania',
      'luxembourg',
      'malta',
      'moldova',
      'montenegro',
      'north-macedonia',
      'northern-ireland',
      'norway',
      'poland',
      'portugal',
      'ireland',
      'romania',
      'san-marino',
      'scotland',
      'serbia',
      'slovakia',
      'slovenia',
      'spain',
      'sweden',
      'switzerland',
      'turkey',
      'ukraine',
      'wales',
    ]) {
      await rootBundle.load('assets/team_logos/$slug.png');
    }
  });
}
