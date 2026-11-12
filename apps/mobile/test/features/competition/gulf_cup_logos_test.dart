import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_identity.dart';

/// كأس الخليج: the eight Gulf sides resolve to their flags, shipped with the
/// app, through the entry point the fixture card uses
/// (`resolveTeamIdentity`). The tournament's own mark is no longer drawn
/// (script 266).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // football_data.teams.name exactly as migration 0046 seeds it -> the slug
  // of the flag under assets/flags/.
  const Map<String, String> gulfSides = <String, String>{
    'البحرين': 'bahrain',
    'قطر': 'qatar',
    'اليمن': 'yemen',
    'الإمارات': 'united-arab-emirates',
    'السعودية': 'saudi-arabia',
    'سلطنة عمان': 'oman',
    'العراق': 'iraq',
    'الكويت': 'kuwait',
  };

  group('Gulf Cup crests', () {
    test('each side resolves through its catalog row to its flag', () async {
      final List<TeamDto> catalog = <TeamDto>[
        for (final MapEntry<String, String> side in gulfSides.entries)
          TeamDto(
            id: 'id-${side.value}',
            name: side.key,
            shortName: null,
            crestUrl: null,
          ),
      ];
      for (final MapEntry<String, String> side in gulfSides.entries) {
        final String path = 'assets/flags/${side.value}.png';
        final ResolvedTeamIdentity identity = resolveTeamIdentity(
          catalog: catalog,
          teamId: 'id-${side.value}',
          teamName: null,
        );
        expect(identity.assetPath, path, reason: side.key);
        final ByteData data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(0), reason: side.key);
      }
    });

    test('each side also resolves by name alone, without a team id', () {
      for (final MapEntry<String, String> side in gulfSides.entries) {
        final ResolvedTeamIdentity identity = resolveTeamIdentity(
          catalog: null,
          teamId: null,
          teamName: side.key,
        );
        expect(
          identity.assetPath,
          'assets/flags/${side.value}.png',
          reason: side.key,
        );
      }
    });

    test('the Emirates resolves with or without the hamza', () {
      final ResolvedTeamIdentity plain = resolveTeamIdentity(
        catalog: null,
        teamId: null,
        teamName: 'الامارات',
      );
      expect(plain.assetPath, 'assets/flags/united-arab-emirates.png');
    });

    test('the Al-Khaleej club keeps its own crest, not a flag', () {
      final ResolvedTeamIdentity club = resolveTeamIdentity(
        catalog: null,
        teamId: null,
        teamName: 'الخليج',
      );
      expect(club.crestSlug, 'al-khaleej');
      expect(club.assetPath, isNull);
    });
  });
}
