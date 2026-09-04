library;

import 'package:flutter/material.dart';

/// One competition's optional logo asset + brand color, keyed by
/// `CompetitionDto.id`/`CurrentMonthFixtureItemDto.competitionId` (a UUID
/// string) — mirrors `team_logo_assets.dart`'s local-catalog pattern, but a
/// competition is looked up by its stable id rather than a name slug (a
/// competition's display name has no equivalent of a team's short/legacy
/// naming drift).
///
/// **Deliberately empty for now.** League/competition crests are registered
/// trademarks (see `laliga_2026_27.sql`'s identical note for team crests,
/// and this session's own verified finding that Wikipedia-hosted club
/// crests are "non-free/fair-use, English Wikipedia articles only"): no
/// cleared, redistributable source has been verified for any competition's
/// official logo, so none is shipped rather than fabricated or hot-linked
/// without a license. Every competition therefore renders through the
/// letter-fallback in `fotmob_match_card.dart` (mirrors `TeamLogo`'s own
/// initials fallback) — this is the intended behavior for "no logo on
/// file", not a placeholder. Populate [kCompetitionLogoAssets] once a
/// legitimately licensed source is identified; no other file needs to
/// change (`competitionLogoAsset`/`competitionLogoBrandColor` already
/// degrade to `null` for an absent entry).
@immutable
class CompetitionLogoAsset {
  /// Creates a competition logo asset entry.
  const CompetitionLogoAsset({required this.assetPath, this.brandColor});

  /// The bundled asset path (registered under `pubspec.yaml`'s `assets:`).
  final String assetPath;

  /// The competition's brand color, or `null` to use the neutral token
  /// fallback wherever a brand color would otherwise tint a background.
  final Color? brandColor;
}

/// The competition-logo catalog, keyed by competition id (UUID string).
/// Empty today — see this file's doc for why.
const Map<String, CompetitionLogoAsset> kCompetitionLogoAssets =
    <String, CompetitionLogoAsset>{};

/// The bundled asset path for [competitionId]'s logo, or `null` when none is
/// on file (a legitimate, expected state right now — see this file's doc).
String? competitionLogoAsset(String? competitionId) {
  if (competitionId == null) return null;
  return kCompetitionLogoAssets[competitionId]?.assetPath;
}

/// [competitionId]'s brand color, or `null` when none is on file.
Color? competitionLogoBrandColor(String? competitionId) {
  if (competitionId == null) return null;
  return kCompetitionLogoAssets[competitionId]?.brandColor;
}
