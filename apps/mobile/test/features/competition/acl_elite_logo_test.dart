import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/competition_logo_assets.dart';

/// دوري أبطال آسيا للنخبة (migration 0103): the league header resolves to
/// the bundled trophy mark by the catalog name and its English aliases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the AFC Champions League Elite resolves to its mark by name', () async {
    for (final String name in <String>[
      'دوري أبطال آسيا للنخبة',
      ' دوري  أبطال آسيا للنخبة ',
      'AFC Champions League Elite',
      'دوري أبطال آسيا',
    ]) {
      expect(
        competitionLogoAsset(null, name),
        'assets/league_logos/afc-champions-league-elite.png',
        reason: name,
      );
    }
    final ByteData data = await rootBundle.load(
      'assets/league_logos/afc-champions-league-elite.png',
    );
    expect(data.lengthInBytes, greaterThan(0));
  });

  test('the European Champions League keeps its own mark', () {
    expect(
      competitionLogoAsset(null, 'دوري أبطال أوروبا'),
      'assets/league_logos/champions-league.png',
    );
  });
}
