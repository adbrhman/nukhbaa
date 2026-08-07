library;

import 'package:flutter/material.dart';

/// Static branding metadata (primary/secondary colors) for known football
/// teams, keyed by team name exactly as entered by an admin
/// (`FixtureSchedule.homeTeam` / `awayTeam` — Axiom 3). Client-only reference
/// data: no server round-trip, no dependency on `domain`/`application` (a
/// pure `core` lookup table, mirrors `TEAMS`/`AR_TEAMS` in the legacy
/// single-file app).
///
/// Scoped to the project's actual competitions (English Premier League +
/// UEFA Champions League clubs) — the legacy app's World Cup national-team
/// entries were dropped; Nukhba has no World Cup competition.
///
/// Team identity travels as free text on the wire (Next-Task decision
/// 2026-07-11, option (a)) — this map is a best-effort visual enrichment,
/// never a source of truth. A team name not present here still renders
/// correctly via [brandingForTeam]'s deterministic fallback and
/// [teamInitials]'s letter fallback (mirrors the legacy `renderLogo`
/// crest/fallback pattern), so an admin-entered team is never blocked or
/// broken by a missing entry — this table can be extended at any time
/// without a migration.
final class TeamBranding {
  /// Creates a branding pair for one team.
  const TeamBranding({required this.primary, required this.secondary});

  /// The team's primary/home color.
  final Color primary;

  /// The team's secondary/away color.
  final Color secondary;
}

/// Looks up [teamName]'s branding in [kTeamBranding] (exact match, as stored
/// by the admin). Falls back to a deterministic color derived from the name's
/// hash when the team isn't in the table, so every team — known or not —
/// renders a stable, distinct pair of colors across app restarts (same input
/// always yields the same fallback color; not randomized per session).
TeamBranding brandingForTeam(String teamName) {
  final known = kTeamBranding[teamName];
  if (known != null) return known;
  final hue = (teamName.hashCode.abs() % 360).toDouble();
  return TeamBranding(
    primary: HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor(),
    secondary: HSLColor.fromAHSL(1, hue, 0.55, 0.85).toColor(),
  );
}

/// The 1-2 letter fallback "logo" shown when no crest asset exists — mirrors
/// the legacy `renderLogo` letter fallback. Single-word names (most national
/// teams) yield the first two characters; multi-word club names yield the
/// first letter of the first two words (e.g. "Manchester United" -> "MU").
String teamInitials(String teamName) {
  final words = teamName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// Known team branding, keyed by exact team name (English and Arabic entries
/// both present, matching whichever form an admin enters — mirrors the
/// legacy app's dual-language `TEAMS`/`AR_TEAMS` tables, merged here into one
/// table since [FixtureSchedule] carries a single free-text name per side).
/// Covers the English Premier League (current 2025-26 roster plus recently
/// relegated sides, so a fixture entered against either season's clubs still
/// resolves) and UEFA Champions League clubs.
const Map<String, TeamBranding> kTeamBranding = {
  'Arsenal': TeamBranding(
    primary: Color(0xFFEF0107),
    secondary: Color(0xFF063672),
  ),
  'Aston Villa': TeamBranding(
    primary: Color(0xFF670E36),
    secondary: Color(0xFF9EC4E7),
  ),
  'Bournemouth': TeamBranding(
    primary: Color(0xFFDA291C),
    secondary: Color(0xFF000000),
  ),
  'Brentford': TeamBranding(
    primary: Color(0xFFE30613),
    secondary: Color(0xFFFFD700),
  ),
  'Brighton': TeamBranding(
    primary: Color(0xFF0057B8),
    secondary: Color(0xFFFFFFFF),
  ),
  'Chelsea': TeamBranding(
    primary: Color(0xFF034694),
    secondary: Color(0xFFFFFFFF),
  ),
  'Crystal Palace': TeamBranding(
    primary: Color(0xFF1B458F),
    secondary: Color(0xFFC4122E),
  ),
  'Everton': TeamBranding(
    primary: Color(0xFF003399),
    secondary: Color(0xFFFFFFFF),
  ),
  'Fulham': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFF000000),
  ),
  'Ipswich Town': TeamBranding(
    primary: Color(0xFF0044A9),
    secondary: Color(0xFFFFFFFF),
  ),
  'Leicester City': TeamBranding(
    primary: Color(0xFF003090),
    secondary: Color(0xFFFDBE11),
  ),
  'Liverpool': TeamBranding(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF00B2A9),
  ),
  'Manchester City': TeamBranding(
    primary: Color(0xFF6CABDD),
    secondary: Color(0xFF1C2C5B),
  ),
  'Manchester United': TeamBranding(
    primary: Color(0xFFDA291C),
    secondary: Color(0xFFFBE122),
  ),
  'Newcastle United': TeamBranding(
    primary: Color(0xFF241F20),
    secondary: Color(0xFFFFFFFF),
  ),
  'Nottingham Forest': TeamBranding(
    primary: Color(0xFFE53233),
    secondary: Color(0xFFFFFFFF),
  ),
  'Southampton': TeamBranding(
    primary: Color(0xFFD71920),
    secondary: Color(0xFF130C0E),
  ),
  'Tottenham Hotspur': TeamBranding(
    primary: Color(0xFF132257),
    secondary: Color(0xFFFFFFFF),
  ),
  'West Ham United': TeamBranding(
    primary: Color(0xFF7A263A),
    secondary: Color(0xFF1BB1E7),
  ),
  'Wolverhampton Wanderers': TeamBranding(
    primary: Color(0xFFFDB913),
    secondary: Color(0xFF231F20),
  ),
  'Leeds United': TeamBranding(
    primary: Color(0xFFFFCD00),
    secondary: Color(0xFF1D428A),
  ),
  'Burnley': TeamBranding(
    primary: Color(0xFF6C1D45),
    secondary: Color(0xFF99D6EA),
  ),
  'Sunderland': TeamBranding(
    primary: Color(0xFFEB172B),
    secondary: Color(0xFF000000),
  ),
  'Real Madrid': TeamBranding(
    primary: Color(0xFF003087),
    secondary: Color(0xFFFFFFFF),
  ),
  'Barcelona': TeamBranding(
    primary: Color(0xFFA50044),
    secondary: Color(0xFF004D98),
  ),
  'Atletico Madrid': TeamBranding(
    primary: Color(0xFFCE3524),
    secondary: Color(0xFF003366),
  ),
  'Real Betis': TeamBranding(
    primary: Color(0xFF00954C),
    secondary: Color(0xFFFFFFFF),
  ),
  'Borussia Dortmund': TeamBranding(
    primary: Color(0xFFFDE100),
    secondary: Color(0xFF000000),
  ),
  'RB Leipzig': TeamBranding(
    primary: Color(0xFFDD0741),
    secondary: Color(0xFF001E62),
  ),
  'Stuttgart': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'Bayer Leverkusen': TeamBranding(
    primary: Color(0xFFE32221),
    secondary: Color(0xFF000000),
  ),
  'Paris Saint-Germain': TeamBranding(
    primary: Color(0xFF004170),
    secondary: Color(0xFFDA291C),
  ),
  'Lens': TeamBranding(
    primary: Color(0xFFFFD700),
    secondary: Color(0xFFCC0000),
  ),
  'Lille': TeamBranding(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF002E62),
  ),
  'Club Brugge': TeamBranding(
    primary: Color(0xFF2A52A2),
    secondary: Color(0xFF000000),
  ),
  'Feyenoord': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'Roma': TeamBranding(
    primary: Color(0xFF8E1F2F),
    secondary: Color(0xFFF5C518),
  ),
  'Inter Milan': TeamBranding(
    primary: Color(0xFF010E80),
    secondary: Color(0xFF000000),
  ),
  'AC Milan': TeamBranding(
    primary: Color(0xFFFB090B),
    secondary: Color(0xFF000000),
  ),
  'Napoli': TeamBranding(
    primary: Color(0xFF0067B1),
    secondary: Color(0xFFFFFFFF),
  ),
  'Bayern Munich': TeamBranding(
    primary: Color(0xFFDC052D),
    secondary: Color(0xFF0066B2),
  ),
  'Como': TeamBranding(
    primary: Color(0xFF004FA3),
    secondary: Color(0xFFFFFFFF),
  ),
  'Sporting Lisbon': TeamBranding(
    primary: Color(0xFF006600),
    secondary: Color(0xFFFFFFFF),
  ),
  'Eindhoven': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'Fenerbahce': TeamBranding(
    primary: Color(0xFF003399),
    secondary: Color(0xFFFFD700),
  ),
  'Galatasaray': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFD700),
  ),
  'Shakhtar Donetsk': TeamBranding(
    primary: Color(0xFFFF6600),
    secondary: Color(0xFF000000),
  ),
  'Slavia Prague': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'Dinamo Zagreb': TeamBranding(
    primary: Color(0xFF005BAC),
    secondary: Color(0xFFFFFFFF),
  ),
  'Red Star Belgrade': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'Slovan Bratislava': TeamBranding(
    primary: Color(0xFF003399),
    secondary: Color(0xFFFFFFFF),
  ),
  'Shamrock Rovers': TeamBranding(
    primary: Color(0xFF1A7A2E),
    secondary: Color(0xFFFFFFFF),
  ),
  'Omonia': TeamBranding(
    primary: Color(0xFF00A650),
    secondary: Color(0xFFFFFFFF),
  ),
  'Ferencvaros': TeamBranding(
    primary: Color(0xFF006633),
    secondary: Color(0xFFFFFFFF),
  ),
  'Bodo Glimt': TeamBranding(
    primary: Color(0xFFFFD700),
    secondary: Color(0xFF000000),
  ),
  'Porto': TeamBranding(
    primary: Color(0xFF00438C),
    secondary: Color(0xFFFFFFFF),
  ),
  'Salzburg': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'ريال مدريد': TeamBranding(
    primary: Color(0xFF003087),
    secondary: Color(0xFFFFFFFF),
  ),
  'برشلونة': TeamBranding(
    primary: Color(0xFFA50044),
    secondary: Color(0xFF004D98),
  ),
  'أتلتيكو مدريد': TeamBranding(
    primary: Color(0xFFCE3524),
    secondary: Color(0xFF003366),
  ),
  'ريال بيتيس': TeamBranding(
    primary: Color(0xFF00954C),
    secondary: Color(0xFFFFFFFF),
  ),
  'بوروسيا دورتموند': TeamBranding(
    primary: Color(0xFFFDE100),
    secondary: Color(0xFF000000),
  ),
  'لايبزيغ': TeamBranding(
    primary: Color(0xFFDD0741),
    secondary: Color(0xFF001E62),
  ),
  'شتوتغارت': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'باير ليفركوزن': TeamBranding(
    primary: Color(0xFFE32221),
    secondary: Color(0xFF000000),
  ),
  'باريس سان جيرمان': TeamBranding(
    primary: Color(0xFF004170),
    secondary: Color(0xFFDA291C),
  ),
  'لانس': TeamBranding(
    primary: Color(0xFFFFD700),
    secondary: Color(0xFFCC0000),
  ),
  'ليل': TeamBranding(primary: Color(0xFFC8102E), secondary: Color(0xFF002E62)),
  'ليفربول': TeamBranding(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF00B2A9),
  ),
  'أرسنال': TeamBranding(
    primary: Color(0xFFEF0107),
    secondary: Color(0xFF063672),
  ),
  'مانشستر سيتي': TeamBranding(
    primary: Color(0xFF6CABDD),
    secondary: Color(0xFF1C2C5B),
  ),
  'مانشستر يونايتد': TeamBranding(
    primary: Color(0xFFDA291C),
    secondary: Color(0xFFFBE122),
  ),
  'أستون فيلا': TeamBranding(
    primary: Color(0xFF670E36),
    secondary: Color(0xFF9EC4E7),
  ),
  'كلوب بروج': TeamBranding(
    primary: Color(0xFF2A52A2),
    secondary: Color(0xFF000000),
  ),
  'فينورد': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'روما': TeamBranding(
    primary: Color(0xFF8E1F2F),
    secondary: Color(0xFFF5C518),
  ),
  'إنتر ميلان': TeamBranding(
    primary: Color(0xFF010E80),
    secondary: Color(0xFF000000),
  ),
  'إنتر': TeamBranding(
    primary: Color(0xFF010E80),
    secondary: Color(0xFF000000),
  ),
  'ميلان': TeamBranding(
    primary: Color(0xFFFB090B),
    secondary: Color(0xFF000000),
  ),
  'نابولي': TeamBranding(
    primary: Color(0xFF0067B1),
    secondary: Color(0xFFFFFFFF),
  ),
  'بايرن ميونخ': TeamBranding(
    primary: Color(0xFFDC052D),
    secondary: Color(0xFF0066B2),
  ),
  'كومو': TeamBranding(
    primary: Color(0xFF004FA3),
    secondary: Color(0xFFFFFFFF),
  ),
  'سبورتينغ لشبونة': TeamBranding(
    primary: Color(0xFF006600),
    secondary: Color(0xFFFFFFFF),
  ),
  'أيندهوفن': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'فنربخشة': TeamBranding(
    primary: Color(0xFF003399),
    secondary: Color(0xFFFFD700),
  ),
  'غلطة سراي': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFD700),
  ),
  'شاختار': TeamBranding(
    primary: Color(0xFFFF6600),
    secondary: Color(0xFF000000),
  ),
  'سلافيا براغ': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'دينامو زغرب': TeamBranding(
    primary: Color(0xFF005BAC),
    secondary: Color(0xFFFFFFFF),
  ),
  'النجم الأحمر بلغراد': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
  'سلوفان براتيسلافا': TeamBranding(
    primary: Color(0xFF003399),
    secondary: Color(0xFFFFFFFF),
  ),
  'شامروك روفرز': TeamBranding(
    primary: Color(0xFF1A7A2E),
    secondary: Color(0xFFFFFFFF),
  ),
  'أومونيا': TeamBranding(
    primary: Color(0xFF00A650),
    secondary: Color(0xFFFFFFFF),
  ),
  'فيرينتسفاروش': TeamBranding(
    primary: Color(0xFF006633),
    secondary: Color(0xFFFFFFFF),
  ),
  'بودو/غليمت': TeamBranding(
    primary: Color(0xFFFFD700),
    secondary: Color(0xFF000000),
  ),
  'بورتو': TeamBranding(
    primary: Color(0xFF00438C),
    secondary: Color(0xFFFFFFFF),
  ),
  'سالزبورغ': TeamBranding(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFFFFFFFF),
  ),
};
