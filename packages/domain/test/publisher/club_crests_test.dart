import 'dart:io';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

const Map<String, String> _english = <String, String>{
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
  'Ajax': 'ajax',
  'Atalanta': 'atalanta',
  'AS Monaco': 'monaco',
  'Brann': 'brann',
};

const Map<String, String> _arabic = <String, String>{
  'النجم الأحمر': 'crvena-zvezda',
  'النجم الاحمر': 'crvena-zvezda',
  'كوبنهاغن': 'copenhagen',
  'هارتس': 'hearts',
  'إيبيريا تبليسي': 'iberia',
};

/// The app's own lookup, where the tables come from.
const String _mobileSource =
    '../../apps/mobile/lib/features/competition/team_logo_assets.dart';

void main() {
  group('ClubCrests.slugFor', () {
    test('an Arabic name, or another spelling of it, gives the crest', () {
      for (final MapEntry<String, String> name in _arabic.entries) {
        expect(ClubCrests.slugFor(name.key), name.value, reason: name.key);
      }
    });

    test('an English provider name gives the crest, accents and all', () {
      for (final MapEntry<String, String> name in _english.entries) {
        expect(ClubCrests.slugFor(name.key), name.value, reason: name.key);
      }
    });

    test('a club with no crest on file, or no name, gives null', () {
      expect(ClubCrests.slugFor('Oxford City'), isNull);
      expect(ClubCrests.slugFor('  '), isNull);
      expect(ClubCrests.slugFor(''), isNull);
      expect(ClubCrests.slugFor(null), isNull);
    });

    test('every slug it can give is a crest on file', () {
      for (final String name in <String>[..._english.keys, ..._arabic.keys]) {
        final String? slug = ClubCrests.slugFor(name);
        expect(slug == null || ClubCrests.hasSlug(slug), isTrue, reason: name);
      }
      expect(ClubCrests.slugs, hasLength(greaterThan(300)));
    });
  });

  test('slugOf folds accents and drops apostrophes', () {
    expect(ClubCrests.slugOf('Kauno \u017dalgiris'), 'kauno-zalgiris');
    expect(ClubCrests.slugOf("Inter Club d'Escaldes"), 'inter-escaldes');
    expect(ClubCrests.slugOf('Nordsj\u00e6lland'), 'nordsjaelland');
  });

  test('the tables equal the app\'s own (team_logo_assets.dart)', () {
    final File source = File(_mobileSource);
    if (!source.existsSync()) {
      markTestSkipped('the app is not beside this package');
      return;
    }
    final String text = source.readAsStringSync();
    final String aliases = RegExp(
      r'_arabicTeamLogoAliases = <String, String>\{(.*?)\n\};',
      dotAll: true,
    ).firstMatch(text)!.group(1)!;
    final Iterable<RegExpMatch> pairs = RegExp(
      r"^\s*'([^']+)':\s*'([^']+)',\s*$",
      multiLine: true,
    ).allMatches(aliases);
    expect(pairs.length, greaterThan(300));
    for (final RegExpMatch pair in pairs) {
      expect(
        ClubCrests.slugFor(pair.group(1)),
        pair.group(2),
        reason: pair.group(1),
      );
    }
    final String slugBlock = RegExp(
      r'_monthlyLogoSlugs = <String>\{(.*?)\n\};',
      dotAll: true,
    ).firstMatch(text)!.group(1)!;
    final Iterable<RegExpMatch> slugs = RegExp(
      r"^\s*'([a-z0-9-]+)',\s*$",
      multiLine: true,
    ).allMatches(slugBlock);
    expect(slugs.length, ClubCrests.slugs.length);
    for (final RegExpMatch slug in slugs) {
      expect(ClubCrests.hasSlug(slug.group(1)!), isTrue, reason: slug.group(1));
    }
  });
}
