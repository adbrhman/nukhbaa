import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// ديربيات كبرى (migration 0104): every club the derbies added, and the
/// two catalog names that had no crest before (بشكتاش, استقلال طهران),
/// resolve by their catalog name to their crest in the owner's list.
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
      expect(teamCrestSlug(club.key), club.value, reason: club.key);
    }
  });

  test('every crest is on the owner list, never in the bundle', () {
    for (final String slug in crests.values) {
      expect(kTeamMarkSlugs, contains(slug), reason: slug);
      expect(kFlagSlugs, isNot(contains(slug)), reason: slug);
    }
  });

  test('the Saudi Al-Faisaly keeps its own crest', () {
    expect(teamCrestSlug('الفيصلي'), 'al-faisaly');
  });
}
