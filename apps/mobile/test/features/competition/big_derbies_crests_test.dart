import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// ديربيات كبرى (migration 0104): every club the derbies added, and the
/// two catalog names that had no crest before (بشكتاش, استقلال طهران),
/// resolve by their catalog name to a bundled crest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, String> crests = <String, String>{
    'الزمالك': 'zamalek',
    'الرجاء': 'raja-casablanca',
    'النادي الإفريقي': 'club-africain',
    'الهلال السوداني': 'al-hilal-omdurman',
    'المريخ': 'al-merrikh',
    'مولودية الجزائر': 'mc-alger',
    'اتحاد العاصمة': 'usm-alger',
    'الفيصلي الأردني': 'al-faisaly-amman',
    'الوحدات': 'al-wehdat',
    'الزوراء': 'al-zawraa',
    'برسبوليس': 'persepolis',
    'استقلال طهران': 'esteghlal',
    'رينجرز': 'rangers',
    'باناثينايكوس': 'panathinaikos',
    'أياكس': 'ajax',
    'بشكتاش': 'besiktas',
  };

  test('each club resolves by its catalog name', () {
    for (final MapEntry<String, String> club in crests.entries) {
      expect(
        teamLogoAssetPath(club.key),
        'assets/team_logos/${club.value}.png',
        reason: club.key,
      );
    }
  });

  test('every crest loads from the bundle', () async {
    for (final String slug in crests.values) {
      final ByteData data = await rootBundle.load(
        'assets/team_logos/$slug.png',
      );
      expect(data.lengthInBytes, greaterThan(0), reason: slug);
    }
  });

  test('the Saudi Al-Faisaly keeps its own crest', () {
    expect(teamLogoAssetPath('الفيصلي'), 'assets/team_logos/al-faisaly.png');
  });
}
