import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// دوري أبطال آسيا للنخبة (migration 0103): the clubs whose crests the
/// owner supplied resolve by their catalog name to their crest in the
/// owner's list (script 266: no crest ships in the app).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, String> crests = <String, String>{
    'فيسيل كوبي': 'vissel-kobe',
    'السد': 'al-sadd',
    'تراكتور': 'tractor',
    'الغرافة': 'al-gharafa',
    'جوهور دار التعظيم': 'johor-darul-tazim',
    'شنغهاي بورت': 'shanghai-port',
    'الوصل': 'al-wasl',
    'شباب الأهلي': 'shabab-al-ahli',
    'الشمال': 'al-shamal',
    'باختاكور': 'pakhtakor',
    'نفتشي فرغانة': 'neftchi-fergana',
    'القوة الجوية': 'al-quwa-al-jawiya',
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

  test('a club without a crest yet keeps its initials', () {
    expect(teamCrestSlug('غامبا أوساكا'), isNull);
  });
}
