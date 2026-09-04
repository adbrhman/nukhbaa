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
      expect(identity.crestUrl, 'https://example.com/rma.svg');
    });

    test('a catalog team with no crest_url yields a null crest, not blank', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: 't-2',
        teamName: 'Barcelona',
      );

      expect(identity.displayName, 'Barcelona');
      expect(identity.crestUrl, isNull);
    });

    test('an unresolved id falls back to the legacy name-based lookup', () {
      final identity = resolveTeamIdentity(
        catalog: catalog,
        teamId: 'not-in-catalog',
        teamName: 'Liverpool',
      );

      expect(identity.displayName, 'ليفربول');
      expect(identity.crestUrl, isNotNull);
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
      expect(identity.crestUrl, isNull);
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
