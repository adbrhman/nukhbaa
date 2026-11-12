/// No club crest and no league logo ships with the app (script 266, the
/// owner's decision of 2026-11-11, before the Google Play release): they are
/// their owners' marks. The crests come from the owner's list on the
/// server, and nowhere else. This test is the rule, in CI:
///
/// * the only bundled marks are the countries' flags, exactly [kFlagSlugs];
/// * no folder of crests or league logos is back, nor listed in pubspec;
/// * no code reads a crest from the bundle or from a third party's address;
/// * every club the app can name has its row in the server's list
///   (migration 0210), and every row a club the app can name.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

void main() {
  test('the only bundled marks are the flags', () {
    final Set<String> files = <String>{
      for (final FileSystemEntity entity in Directory(
        'assets/flags',
      ).listSync())
        if (entity is File) entity.uri.pathSegments.last,
    };
    expect(files, <String>{for (final String slug in kFlagSlugs) '$slug.png'});
    expect(Directory('assets/team_logos').existsSync(), isFalse);
    expect(Directory('assets/league_logos').existsSync(), isFalse);
  });

  test('pubspec bundles the flags and no crest folder', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/flags/'));
    expect(pubspec, isNot(contains('team_logos')));
    expect(pubspec, isNot(contains('league_logos')));
  });

  test('no code reads a crest from the bundle or a third party', () {
    final List<String> found = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      final String text = entity.readAsStringSync();
      for (final String banned in <String>[
        'assets/team_logos',
        'league_logos',
        'espncdn',
        'crestUrl',
        'leagueLogoUrl',
      ]) {
        if (text.contains(banned)) found.add('${entity.path}: $banned');
      }
    }
    expect(found, isEmpty);
  });

  test('every club the app names is on the server list, and back', () {
    final String seed = File(
      '../../supabase/migrations/0210_club_crests.sql',
    ).readAsStringSync();
    final Set<String> listed = <String>{
      for (final RegExpMatch m in RegExp(
        r"\('([a-z0-9-]+)', 'clubs/\1\.[0-9a-f]{8}\.png'\)",
      ).allMatches(seed))
        m.group(1)!,
    };
    final Set<String> named = kTeamMarkSlugs.difference(kFlagSlugs);
    expect(listed.length, 235);
    expect(named.difference(listed), isEmpty);
    expect(listed.difference(named), isEmpty);
    expect(kFlagSlugs.intersection(listed), isEmpty);
  });
}
