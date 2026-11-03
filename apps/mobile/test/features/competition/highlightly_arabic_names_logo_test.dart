import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_identity.dart';

/// The names the Highlightly seed stores for the clubs it creates with no
/// crest. The match card draws them through [resolveTeamIdentity]; a name the
/// bundled-crest alias map does not know falls back to the initials circle.
const Map<String, String> _seededNames = <String, String>{
  '\u0623\u064a\u0643 \u0623\u062b\u064a\u0646\u0627': 'aek-athens',
  '\u0628\u0648\u062f\u0648 \u063a\u0644\u064a\u0645\u062a': 'bodo-glimt',
  '\u0641\u0646\u0631\u0628\u062e\u0634\u0629': 'fenerbahce',
  '\u0644\u0627\u0633\u0643 \u0644\u064a\u0646\u0632': 'lask',
  '\u0644\u064a\u0644': 'lille',
  '\u0635\u0628\u0627\u062d': 'sabah',
  '\u0633\u0644\u0648\u0641\u0627\u0646 \u0628\u0631\u0627\u062a\u064a\u0633\u0644\u0627\u0641\u0627':
      's-bratislava',
  '\u0641\u0627\u064a\u0643\u0646\u063a': 'viking',
  '\u0623\u0646\u062f\u0631\u0644\u062e\u062a': 'anderlecht',
  '\u0623\u0631\u0627\u0631\u0627\u062a \u0623\u0631\u0645\u064a\u0646\u064a\u0627':
      'ararat-armenia',
  '\u0628\u0646\u0641\u064a\u0643\u0627': 'benfica',
  '\u0628\u0634\u0643\u062a\u0627\u0634': 'besiktas',
  '\u0641\u064a\u0631\u064a\u0646\u0643\u0641\u0627\u0631\u0648\u0633':
      'ferencvaros',
  '\u064a\u0627\u063a\u064a\u0644\u0648\u0646\u064a\u0627': 'jagiellonia',
  '\u0644\u064a\u062e \u0628\u0648\u0632\u0646\u0627\u0646': 'lech-poznan',
  '\u0644\u064a\u0644\u064a\u0633\u062a\u0631\u0648\u0645': 'lillestrom',
  '\u0623\u0648\u0641\u064a \u0643\u0631\u064a\u062a': 'ofi',
  '\u0623\u0648\u0645\u0648\u0646\u064a\u0627 \u0646\u064a\u0642\u0648\u0633\u064a\u0627':
      'omonoia',
  '\u0641\u064a\u0643\u062a\u0648\u0631\u064a\u0627 \u0628\u0644\u0632\u0646':
      'viktoria-plzen',
  '\u0631\u064a\u062f \u0628\u0648\u0644 \u0633\u0627\u0644\u0632\u0628\u0648\u0631\u063a':
      'salzburg',
};

void main() {
  group('crest for the clubs the Highlightly seed creates', () {
    for (final MapEntry<String, String> e in _seededNames.entries) {
      test('${e.key} resolves to its bundled crest', () {
        final ResolvedTeamIdentity identity = resolveTeamIdentity(
          catalog: <TeamDto>[
            TeamDto(id: 't-1', name: e.key, shortName: null, crestUrl: null),
          ],
          teamId: 't-1',
          teamName: e.key,
        );

        expect(identity.crestUrl, isNull);
        expect(identity.assetPath, 'assets/team_logos/${e.value}.png');
      });
    }
  });
}
