/// Resolves one side of a fixture's team identity (display name + crest) —
/// the single place every screen goes through instead of choosing between
/// the model-backed [TeamDto] catalog and the legacy `team_registry.dart`
/// lookup table itself.
///
/// Precedence: a resolved `team_id` against the real
/// `football_data.teams` catalog (`teamCatalogProvider`) always wins — it is
/// the model-backed source (items 4/7 of the football-data wiring). A
/// fixture with no team id yet (an older schedule row, or a league with no
/// seeded catalog) falls back to `team_registry.dart`'s name-based lookup,
/// then to the raw server-supplied name, then to a clean "unknown"
/// placeholder — never a blank space (item 6).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../core/branding/team_branding.dart';
import 'team_logo_assets.dart';
import 'team_registry.dart';

/// One side's resolved display identity, ready for `TeamLogo`/branding.
@immutable
class ResolvedTeamIdentity {
  const ResolvedTeamIdentity({
    required this.displayName,
    this.crestUrl,
    this.assetPath,
    this.brandColor,
  });

  /// The best available display name — never blank.
  final String displayName;

  /// A crest image URL, or `null` to fall back to the initials circle.
  final String? crestUrl;

  /// A bundled crest asset path, when one ships with the app. Preferred
  /// over [crestUrl] because it needs no network at all.
  final String? assetPath;

  /// A brand color for the initials-circle fallback, or `null` for the
  /// neutral token color.
  final Color? brandColor;
}

/// Resolves [teamId] (a fixture's `home_team_id`/`away_team_id`, when
/// present) against [catalog], falling back to [teamName]-based lookup.
/// [catalogById] is the same catalog already indexed by id
/// (`teamCatalogByIdProvider`) and is preferred when given: a screen drawing
/// many fixtures at once should not pay a linear scan per team per rebuild.
/// [catalog] remains for callers that only hold the plain list.
ResolvedTeamIdentity resolveTeamIdentity({
  required List<TeamDto>? catalog,
  Map<String, TeamDto>? catalogById,
  String? teamId,
  String? teamName,
}) {
  final TeamDto? matched = _matchById(
    catalog: catalog,
    catalogById: catalogById,
    teamId: teamId,
  );
  if (matched != null) {
    return ResolvedTeamIdentity(
      displayName: matched.name,
      crestUrl: matched.crestUrl,
      assetPath: teamLogoAssetPath(matched.name) ?? teamLogoAssetPath(teamName),
      brandColor: brandingForTeam(matched.name).primary,
    );
  }
  final TeamBrand? brand = lookupTeam(teamName);
  final String fallbackName = teamName?.trim().isNotEmpty == true
      ? teamName!.trim()
      : teamDisplayName(teamName);
  return ResolvedTeamIdentity(
    displayName: teamDisplayName(teamName),
    crestUrl: brand?.logoUrl,
    assetPath: teamLogoAssetPath(teamName),
    brandColor: brand?.c1 ?? brandingForTeam(fallbackName).primary,
  );
}

/// The catalog entry for [teamId], from the indexed catalog when one was
/// supplied and from a scan of the plain list otherwise.
TeamDto? _matchById({
  required List<TeamDto>? catalog,
  required Map<String, TeamDto>? catalogById,
  required String? teamId,
}) {
  if (teamId == null) return null;
  if (catalogById != null) return catalogById[teamId];
  if (catalog == null) return null;
  for (final TeamDto team in catalog) {
    if (team.id == teamId) return team;
  }
  return null;
}
