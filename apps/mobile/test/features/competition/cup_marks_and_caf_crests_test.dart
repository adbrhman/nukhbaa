import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/competition_logo_assets.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// The super cups, the FA Cup and the CAF Champions League (0045, 0105)
/// resolve by their catalog name to a bundled mark, and the five CAF clubs
/// of 0105 and Bayer Leverkusen to their crests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, String> marks = <String, String>{
    'كأس السوبر الإسباني': 'supercopa-de-espana',
    'كأس السوبر الإيطالي': 'supercoppa-italiana',
    'كأس السوبر الفرنسي': 'trophee-des-champions',
    'كأس السوبر الألماني': 'dfl-supercup',
    'دوري أبطال إفريقيا': 'caf-champions-league',
    'كأس الاتحاد الإنجليزي': 'fa-cup',
  };

  const Map<String, String> crests = <String, String>{
    'بيراميدز': 'pyramids',
    'نهضة بركان': 'rs-berkane',
    'أورلاندو بايرتس': 'orlando-pirates',
    'يانغ أفريكانز': 'young-africans',
    'سيمبا': 'simba',
    'باير ليفركوزن': 'bayer-leverkusen',
  };

  test('each competition resolves by its catalog name', () {
    for (final MapEntry<String, String> mark in marks.entries) {
      expect(
        competitionLogoAsset(null, mark.key),
        'assets/league_logos/${mark.value}.png',
        reason: mark.key,
      );
    }
  });

  test('each club resolves by its catalog name', () {
    for (final MapEntry<String, String> club in crests.entries) {
      expect(
        teamLogoAssetPath(club.key),
        'assets/team_logos/${club.value}.png',
        reason: club.key,
      );
    }
  });

  test('every mark and crest loads from the bundle', () async {
    final List<String> paths = <String>[
      for (final String slug in marks.values) 'assets/league_logos/$slug.png',
      for (final String slug in crests.values) 'assets/team_logos/$slug.png',
    ];
    for (final String path in paths) {
      final ByteData data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });
}
