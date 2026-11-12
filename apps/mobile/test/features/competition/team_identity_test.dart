import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_identity.dart';

void main() {
  const catalog = <TeamDto>[
    TeamDto(
      id: 't-1',
      name: 'Real Madrid',
      shortName: 'RMA',
      crestUrl: 'https://example.com/rma.svg',
    ),
    TeamDto(id: 't-2', name: 'Barcelona', shortName: null, crestUrl: null),
  ];

  group('resolveTeamIdentity', () {
    test('a resolved team id wins over the legacy name lookup', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: 't-1',
        teamName: 'some other free-text name',
      );

      expect(identity.displayName, 'Real Madrid');
      // The catalog's crest_url is a third party's copy, never drawn: the
      // crest is the owner's, by name (script 266).
      expect(identity.crestSlug, 'real-madrid');
    });

    test('a catalog team with no crest of its own falls back by name', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: 't-2',
        teamName: 'Barcelona',
      );

      expect(identity.displayName, 'Barcelona');
      expect(identity.crestSlug, 'barcelona');
    });

    test('an unresolved id falls back to the legacy name-based lookup', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: 'not-in-catalog',
        teamName: 'Liverpool',
      );

      expect(identity.displayName, 'ليفربول');
      expect(identity.crestSlug, 'liverpool');
    });

    test('a null id falls back to the legacy name-based lookup', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: null,
        teamName: 'Liverpool',
      );

      expect(identity.displayName, 'ليفربول');
    });

    test('an unrecognized name with no id degrades to a clean fallback', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: null,
        teamName: 'Some Unknown FC',
      );

      expect(identity.displayName, 'Some Unknown FC');
      expect(identity.crestSlug, isNull);
      expect(identity.assetPath, isNull);
    });

    test('a null name with no id degrades to the "unknown" placeholder', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: null,
        teamName: null,
      );

      expect(identity.displayName, '؟');
    });

    test('a null catalog (still loading) falls back cleanly, never throws', () {
      final identity = resolveTeamIdentity(
        catalog: null,
        teamId: 't-1',
        teamName: 'Liverpool',
      );

      expect(identity.displayName, 'ليفربول');
    });
  });
}
