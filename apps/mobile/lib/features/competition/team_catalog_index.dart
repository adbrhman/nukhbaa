/// The team catalog indexed by team id.
///
/// `resolveTeamIdentity` used to scan the whole catalog for every side of
/// every fixture on every rebuild -- on a twenty-match day against a
/// hundred-team catalog that is four thousand comparisons per frame, for an
/// answer that does not change between reads. Indexing once per catalog read
/// makes each lookup O(1).
///
/// `null` while the catalog is loading or failed, exactly like `.value` on
/// the read itself, so every caller keeps its name-based fallback unchanged.
///
/// It lives beside `teams_providers.dart` rather than inside it because that
/// file is generator-backed (`part 'teams_providers.g.dart'`) and this needs
/// no build_runner output.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'teams_providers.dart';

/// The catalog from [teamCatalogProvider], keyed by `TeamDto.id`.
final teamCatalogByIdProvider = Provider<Map<String, TeamDto>?>((ref) {
  final List<TeamDto>? catalog = ref.watch(teamCatalogProvider).value;
  if (catalog == null) return null;
  return Map<String, TeamDto>.unmodifiable(<String, TeamDto>{
    for (final TeamDto team in catalog) team.id: team,
  });
});
