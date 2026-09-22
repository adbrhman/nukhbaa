import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const Map<String, String> expectedCafAssets = <String, String>{
    'الجزائر': 'algeria',
    'أنغولا': 'angola',
    'بنين': 'benin',
    'بوتسوانا': 'botswana',
    'بوركينا فاسو': 'burkina-faso',
    'بوروندي': 'burundi',
    'الكاميرون': 'cameroon',
    'الرأس الأخضر': 'cape-verde',
    'أفريقيا الوسطى': 'central-african-republic',
    'تشاد': 'chad',
    'جزر القمر': 'comoros',
    'الكونغو': 'congo',
    'الكونغو الديمقراطية': 'democratic-republic-of-congo',
    'جيبوتي': 'djibouti',
    'مصر': 'egypt',
    'غينيا الاستوائية': 'equatorial-guinea',
    'إريتريا': 'eritrea',
    'إسواتيني': 'eswatini',
    'إثيوبيا': 'ethiopia',
    'الغابون': 'gabon',
    'غامبيا': 'gambia',
    'غانا': 'ghana',
    'غينيا': 'guinea',
    'غينيا بيساو': 'guinea-bissau',
    'ساحل العاج': 'ivory-coast',
    'كينيا': 'kenya',
    'ليسوتو': 'lesotho',
    'ليبيريا': 'liberia',
    'ليبيا': 'libya',
    'مدغشقر': 'madagascar',
    'مالاوي': 'malawi',
    'مالي': 'mali',
    'موريتانيا': 'mauritania',
    'موريشيوس': 'mauritius',
    'المغرب': 'morocco',
    'موزمبيق': 'mozambique',
    'ناميبيا': 'namibia',
    'النيجر': 'niger',
    'نيجيريا': 'nigeria',
    'رواندا': 'rwanda',
    'ساو تومي وبرينسيبي': 'sao-tome-and-principe',
    'السنغال': 'senegal',
    'سيشل': 'seychelles',
    'سيراليون': 'sierra-leone',
    'الصومال': 'somalia',
    'جنوب أفريقيا': 'south-africa',
    'جنوب السودان': 'south-sudan',
    'السودان': 'sudan',
    'تنزانيا': 'tanzania',
    'توغو': 'togo',
    'تونس': 'tunisia',
    'أوغندا': 'uganda',
    'زامبيا': 'zambia',
    'زيمبابوي': 'zimbabwe',
  };

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

  test('resolves the added Arabic team names to their crests', () {
    const Map<String, String> expected = <String, String>{
      'أنجيه': 'angers',
      'موناكو': 'monaco',
      'أوكسير': 'auxerre',
      'بريست': 'brest',
      'لوهافر': 'le-havre',
      'لومان': 'le-mans',
      'لوريان': 'lorient',
      'نيس': 'nice',
      'باريس إف سي': 'paris-fc',
      'ستراسبورغ': 'strasbourg',
      'تولوز': 'toulouse',
      'تروا': 'troyes',
      'ألبانيا': 'albania',
      'أندورا': 'andorra',
      'أرمينيا': 'armenia',
      'النمسا': 'austria',
      'أذربيجان': 'azerbaijan',
      'بيلاروسيا': 'belarus',
      'بلجيكا': 'belgium',
      'البوسنة والهرسك': 'bosnia-herzegovina',
      'بلغاريا': 'bulgaria',
      'كرواتيا': 'croatia',
      'قبرص': 'cyprus',
      'التشيك': 'czech-republic',
      'الدنمارك': 'denmark',
      'هولندا': 'netherlands',
      'إنجلترا': 'england',
      'إستونيا': 'estonia',
      'جزر فارو': 'faroe-islands',
      'فنلندا': 'finland',
      'فرنسا': 'france',
      'جورجيا': 'georgia',
      'ألمانيا': 'germany',
      'جبل طارق': 'gibraltar',
      'اليونان': 'greece',
      'المجر': 'hungary',
      'آيسلندا': 'iceland',
      'إسرائيل': 'israel',
      'إيطاليا': 'italy',
      'كازاخستان': 'kazakhstan',
      'كوسوفو': 'kosovo',
      'لاتفيا': 'latvia',
      'ليختنشتاين': 'liechtenstein',
      'ليتوانيا': 'lithuania',
      'لوكسمبورغ': 'luxembourg',
      'مالطا': 'malta',
      'مولدوفا': 'moldova',
      'الجبل الأسود': 'montenegro',
      'مقدونيا الشمالية': 'north-macedonia',
      'أيرلندا الشمالية': 'northern-ireland',
      'النرويج': 'norway',
      'بولندا': 'poland',
      'البرتغال': 'portugal',
      'جمهورية أيرلندا': 'ireland',
      'رومانيا': 'romania',
      'سان مارينو': 'san-marino',
      'إسكتلندا': 'scotland',
      'صربيا': 'serbia',
      'سلوفاكيا': 'slovakia',
      'سلوفينيا': 'slovenia',
      'إسبانيا': 'spain',
      'السويد': 'sweden',
      'سويسرا': 'switzerland',
      'تركيا': 'turkey',
      'أوكرانيا': 'ukraine',
      'ويلز': 'wales',
    };
    for (final MapEntry<String, String> entry in expected.entries) {
      expect(
        teamLogoAssetPath(entry.key),
        'assets/team_logos/${entry.value}.png',
        reason: entry.key,
      );
    }
  });

  test('every added Ligue 1 club crest loads from assets', () async {
    for (final String slug in <String>[
      'angers',
      'monaco',
      'auxerre',
      'brest',
      'le-havre',
      'le-mans',
      'lorient',
      'nice',
      'paris-fc',
      'strasbourg',
      'toulouse',
      'troyes',
    ]) {
      await rootBundle.load('assets/team_logos/$slug.png');
    }
  });

  test('resolves CAF national sides through the fixture identity resolver', () {
    for (final MapEntry<String, String> entry in expectedCafAssets.entries) {
      final ResolvedTeamIdentity identity = resolveTeamIdentity(
        catalog: null,
        teamId: null,
        teamName: entry.key,
      );
      expect(
        identity.assetPath,
        'assets/team_logos/${entry.value}.png',
        reason: entry.key,
      );
    }
  });

  test('every CAF national-team flag loads from bundled assets', () async {
    for (final String slug in expectedCafAssets.values) {
      await rootBundle.load('assets/team_logos/$slug.png');
    }
  });

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
