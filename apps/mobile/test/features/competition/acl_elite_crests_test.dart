import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// دوري أبطال آسيا للنخبة (migration 0103): the clubs whose crests the
/// owner supplied resolve by their catalog name to a bundled crest.
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

  test('a club without a crest yet keeps its initials', () {
    expect(teamLogoAssetPath('استقلال طهران'), isNull);
  });
}
