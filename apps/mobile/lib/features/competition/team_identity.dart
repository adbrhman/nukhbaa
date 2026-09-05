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
ResolvedTeamIdentity resolveTeamIdentity({
  required List<TeamDto>? catalog,
  String? teamId,
  String? teamName,
}) {
  if (teamId != null && catalog != null) {
    for (final TeamDto team in catalog) {
      if (team.id == teamId) {
        return ResolvedTeamIdentity(
          displayName: team.name,
          crestUrl: team.crestUrl,
          assetPath: teamLogoAssetPath(team.name),
        );
      }
    }
  }
  final TeamBrand? brand = lookupTeam(teamName);
  return ResolvedTeamIdentity(
    displayName: teamDisplayName(teamName),
    crestUrl: brand?.logoUrl,
    assetPath: teamLogoAssetPath(teamName),
    brandColor: brand?.c1,
  );
}
