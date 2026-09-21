import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/competition_logo_assets.dart';
import 'package:mobile/features/competition/team_identity.dart';

/// كأس الخليج: the eight Gulf sides and the tournament mark, resolved through
/// the same entry points the fixture card uses (`resolveTeamIdentity` for a
/// side, `competitionLogoAsset` for the league header).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // football_data.teams.name exactly as migration 0046 seeds it -> the slug
  // of the bundled crest under assets/team_logos/.
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
    test(
      'each side resolves through its catalog row to a bundled crest',
      () async {
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
          final String path = 'assets/team_logos/${side.value}.png';
          final ResolvedTeamIdentity identity = resolveTeamIdentity(
            catalog: catalog,
            teamId: 'id-${side.value}',
            teamName: null,
          );
          expect(identity.assetPath, path, reason: side.key);
          final ByteData data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(0), reason: side.key);
        }
      },
    );

    test('each side also resolves by name alone, without a team id', () {
      for (final MapEntry<String, String> side in gulfSides.entries) {
        final ResolvedTeamIdentity identity = resolveTeamIdentity(
          catalog: null,
          teamId: null,
          teamName: side.key,
        );
        expect(
          identity.assetPath,
          'assets/team_logos/${side.value}.png',
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
      expect(plain.assetPath, 'assets/team_logos/united-arab-emirates.png');
    });

    test('the Al-Khaleej club keeps its own crest, not the cup mark', () {
      final ResolvedTeamIdentity club = resolveTeamIdentity(
        catalog: null,
        teamId: null,
        teamName: 'الخليج',
      );
      expect(club.assetPath, 'assets/team_logos/al-khaleej.png');
      expect(competitionLogoAsset(null, 'الخليج'), isNull);
    });
  });

  test('the Gulf Cup resolves to its tournament mark by league name', () async {
    for (final String name in <String>[
      'كأس الخليج',
      'Arabian Gulf Cup',
      'Gulf Cup',
    ]) {
      expect(
        competitionLogoAsset(null, name),
        'assets/league_logos/arabian-gulf-cup.png',
        reason: name,
      );
    }
    final ByteData data = await rootBundle.load(
      'assets/league_logos/arabian-gulf-cup.png',
    );
    expect(data.lengthInBytes, greaterThan(0));
  });
}
