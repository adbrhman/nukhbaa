/// The English names the providers write for the Conference League clubs
/// (accents, ampersands, club prefixes) resolve to the bundled crest of the
/// club, through the fixture card's own lookup (`teamLogoAssetPath`).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

const Map<String, String> _names = <String, String>{
  'Kauno Žalgiris': 'kauno-zalgiris',
  'Mjällby AIF': 'mjallby',
  'Nordsjælland': 'nordsjaelland',
  'FC Nordsjælland': 'nordsjaelland',
  'Sint-Truiden': 'sint-truidense',
  'SC Freiburg': 'freiburg',
  'Brighton & Hove Albion': 'brighton',
  'Inter Club d\'Escaldes': 'inter-escaldes',
  'Iberia 1999': 'iberia',
  'Heart of Midlothian': 'hearts',
  'Red Star Belgrade': 'crvena-zvezda',
  'Universitatea Craiova': 'u-craiova',
  'Borac Banja Luka': 'borac',
  'Kairat Almaty': 'kairat',
  'KuPS': 'kups',
  'AGF': 'agf',
  'Hajduk Split': 'hajduk-split',
  'Lincoln Red Imps': 'lincoln-red-imps',
  'Midtjylland': 'midtjylland',
  'FC Copenhagen': 'copenhagen',
  'Sporting Braga': 'sc-braga',
  'FC Twente': 'twente',
};

void main() {
  test('each English spelling resolves to its club\'s crest', () {
    for (final MapEntry<String, String> name in _names.entries) {
      expect(
        teamLogoAssetPath(name.key),
        'assets/team_logos/${name.value}.png',
        reason: name.key,
      );
    }
  });

  test('and that crest is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final String slug in _names.values.toSet()) {
      final ByteData data = await rootBundle.load(
        'assets/team_logos/$slug.png',
      );
      expect(data.lengthInBytes, greaterThan(0), reason: slug);
    }
  });

  test('a club with no crest on file still has none', () {
    expect(teamLogoAssetPath('Oxford City'), isNull);
    expect(teamLogoAssetPath('  '), isNull);
    expect(teamLogoAssetPath(null), isNull);
  });
}
