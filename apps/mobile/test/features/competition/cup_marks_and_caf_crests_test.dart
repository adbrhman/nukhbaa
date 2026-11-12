import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// The five CAF clubs of 0105 and Bayer Leverkusen resolve by their catalog
/// name to their crests in the owner's list. The competitions' marks are no
/// longer drawn (script 266).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, String> crests = <String, String>{
    'بيراميدز': 'pyramids',
    'نهضة بركان': 'rs-berkane',
    'أورلاندو بايرتس': 'orlando-pirates',
    'يانغ أفريكانز': 'young-africans',
    'سيمبا': 'simba',
    'باير ليفركوزن': 'bayer-leverkusen',
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
}
