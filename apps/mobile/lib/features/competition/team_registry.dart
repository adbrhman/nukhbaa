/// A local presentation layer for team identity (Arabic display name, brand
/// colors, and an ESPN crest id) keyed by the English team name the server
/// currently returns on [RoundFixtureCardDto.homeTeam] /
/// [RoundFixtureCardDto.awayTeam].
///
/// Context: the fixture DTO's `home_team` / `away_team` / `kickoff_at` fields
/// are nullable by design — a fixture aggregate carries no competition ref
/// (Axiom 3) and today's server payload does not resolve a crest URL at all
/// (`football_data.teams.crest_url` exists in the schema but is not yet
/// projected through `RoundFixtureCardDto`). This registry is a *view-layer*
/// stopgap that lets the client render a real crest + Arabic name the moment
/// the server starts returning a recognized English team name, without
/// waiting on that DTO change. It never blocks or hides a fixture: an
/// unrecognized or missing name always falls back cleanly (see
/// [teamDisplayName]).
///
/// TODO(server): once `RoundFixtureCardDto` projects `home_crest_url` /
/// `away_crest_url` from `football_data.teams.crest_url`, prefer that field
/// over [TeamBrand.logoUrl] and retire the ESPN id table below — the server
/// becomes the single source of truth for crest artwork.
library;

import 'package:flutter/material.dart';

/// Immutable brand identity for a single team: Arabic display name, a
/// two-color palette (primary / secondary), and the ESPN team id used to
/// build a crest URL.
@immutable
class TeamBrand {
  /// Creates a team brand.
  const TeamBrand({
    required this.ar,
    required this.c1,
    required this.c2,
    required this.espnId,
  });

  /// The Arabic display name.
  final String ar;

  /// The primary brand color.
  final Color c1;

  /// The secondary brand color.
  final Color c2;

  /// The ESPN team id used to resolve [logoUrl].
  final int espnId;

  /// The team's crest, served as a transparent PNG by ESPN's CDN.
  String get logoUrl =>
      'https://a.espncdn.com/i/teamlogos/soccer/500/$espnId.png';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeamBrand &&
          other.ar == ar &&
          other.c1 == c1 &&
          other.c2 == c2 &&
          other.espnId == espnId);

  @override
  int get hashCode => Object.hash(ar, c1, c2, espnId);
}

Color _hex(String value) =>
    Color(int.parse('FF${value.substring(1)}', radix: 16));

/// English Premier League teams (2025/26 season roster), keyed by the exact
/// English name expected in `home_team` / `away_team`.
final Map<String, TeamBrand> kEplTeams = <String, TeamBrand>{
  'Arsenal': TeamBrand(
    ar: 'أرسنال',
    c1: _hex('#EF0107'),
    c2: _hex('#063672'),
    espnId: 359,
  ),
  'Aston Villa': TeamBrand(
    ar: 'أستون فيلا',
    c1: _hex('#670E36'),
    c2: _hex('#9EC4E7'),
    espnId: 362,
  ),
  'Ipswich Town': TeamBrand(
    ar: 'إبسويتش تاون',
    c1: _hex('#0044A9'),
    c2: _hex('#FFFFFF'),
    espnId: 373,
  ),
  'Everton': TeamBrand(
    ar: 'إيفرتون',
    c1: _hex('#003399'),
    c2: _hex('#FFFFFF'),
    espnId: 368,
  ),
  'Brighton': TeamBrand(
    ar: 'برايتون',
    c1: _hex('#0057B8'),
    c2: _hex('#FFFFFF'),
    espnId: 331,
  ),
  'Brentford': TeamBrand(
    ar: 'برينتفورد',
    c1: _hex('#E30613'),
    c2: _hex('#FFD700'),
    espnId: 337,
  ),
  'Bournemouth': TeamBrand(
    ar: 'بورنموث',
    c1: _hex('#DA291C'),
    c2: _hex('#000000'),
    espnId: 349,
  ),
  'Chelsea': TeamBrand(
    ar: 'تشيلسي',
    c1: _hex('#034694'),
    c2: _hex('#FFFFFF'),
    espnId: 363,
  ),
  'Tottenham Hotspur': TeamBrand(
    ar: 'توتنهام',
    c1: _hex('#132257'),
    c2: _hex('#FFFFFF'),
    espnId: 367,
  ),
  'Sunderland': TeamBrand(
    ar: 'سندرلاند',
    c1: _hex('#EB172B'),
    c2: _hex('#000000'),
    espnId: 3916,
  ),
  'Fulham': TeamBrand(
    ar: 'فولهام',
    c1: _hex('#CC0000'),
    c2: _hex('#000000'),
    espnId: 370,
  ),
  'Crystal Palace': TeamBrand(
    ar: 'كريستال بالاس',
    c1: _hex('#1B458F'),
    c2: _hex('#C4122E'),
    espnId: 384,
  ),
  'Coventry City': TeamBrand(
    ar: 'كوفنتري سيتي',
    c1: _hex('#059DD9'),
    c2: _hex('#FFFFFF'),
    espnId: 388,
  ),
  'Leeds United': TeamBrand(
    ar: 'ليدز يونايتد',
    c1: _hex('#FFCD00'),
    c2: _hex('#1D428A'),
    espnId: 357,
  ),
  'Liverpool': TeamBrand(
    ar: 'ليفربول',
    c1: _hex('#C8102E'),
    c2: _hex('#00B2A9'),
    espnId: 364,
  ),
  'Manchester City': TeamBrand(
    ar: 'مانشستر سيتي',
    c1: _hex('#6CABDD'),
    c2: _hex('#1C2C5B'),
    espnId: 382,
  ),
  'Manchester United': TeamBrand(
    ar: 'مانشستر يونايتد',
    c1: _hex('#DA291C'),
    c2: _hex('#FBE122'),
    espnId: 360,
  ),
  'Nottingham Forest': TeamBrand(
    ar: 'نوتينغهام فورست',
    c1: _hex('#E53233'),
    c2: _hex('#FFFFFF'),
    espnId: 393,
  ),
  'Newcastle United': TeamBrand(
    ar: 'نيوكاسل',
    c1: _hex('#241F20'),
    c2: _hex('#FFFFFF'),
    espnId: 361,
  ),
  'Hull City': TeamBrand(
    ar: 'هال سيتي',
    c1: _hex('#F18A01'),
    c2: _hex('#000000'),
    espnId: 306,
  ),
};

/// Saudi Roshn League teams, keyed by the exact English name expected in
/// `home_team` / `away_team`.
final Map<String, TeamBrand> kSaudiTeams = <String, TeamBrand>{
  'Al Nassr': TeamBrand(
    ar: 'النصر',
    c1: _hex('#F7D000'),
    c2: _hex('#013B7D'),
    espnId: 3872,
  ),
  'Al Hilal': TeamBrand(
    ar: 'الهلال',
    c1: _hex('#005DA8'),
    c2: _hex('#FFFFFF'),
    espnId: 3870,
  ),
  'Al Ahli': TeamBrand(
    ar: 'الأهلي',
    c1: _hex('#006633'),
    c2: _hex('#FFFFFF'),
    espnId: 3873,
  ),
  'Al Qadsiah': TeamBrand(
    ar: 'القادسية',
    c1: _hex('#FF0000'),
    c2: _hex('#FFFFFF'),
    espnId: 3882,
  ),
  'Al Ittihad': TeamBrand(
    ar: 'الاتحاد',
    c1: _hex('#F7D000'),
    c2: _hex('#000000'),
    espnId: 3868,
  ),
  'Al Taawoun': TeamBrand(
    ar: 'التعاون',
    c1: _hex('#F7D000'),
    c2: _hex('#000000'),
    espnId: 3887,
  ),
  'Al Ettifaq': TeamBrand(
    ar: 'الاتفاق',
    c1: _hex('#FFD700'),
    c2: _hex('#000000'),
    espnId: 3878,
  ),
  'NEOM': TeamBrand(
    ar: 'نيوم',
    c1: _hex('#00A550'),
    c2: _hex('#FFFFFF'),
    espnId: 19784,
  ),
  'Al Hazem': TeamBrand(
    ar: 'الحزم',
    c1: _hex('#00529B'),
    c2: _hex('#FFFFFF'),
    espnId: 3879,
  ),
  'Al Fayha': TeamBrand(
    ar: 'الفيحاء',
    c1: _hex('#FF6600'),
    c2: _hex('#FFFFFF'),
    espnId: 3888,
  ),
  'Al Fateh': TeamBrand(
    ar: 'الفتح',
    c1: _hex('#006633'),
    c2: _hex('#FFCC00'),
    espnId: 3877,
  ),
  'Al Khaleej': TeamBrand(
    ar: 'الخليج',
    c1: _hex('#006633'),
    c2: _hex('#FFFFFF'),
    espnId: 3889,
  ),
  'Al Shabab': TeamBrand(
    ar: 'الشباب',
    c1: _hex('#000000'),
    c2: _hex('#FFFFFF'),
    espnId: 3871,
  ),
  'Al Kholood': TeamBrand(
    ar: 'الخلود',
    c1: _hex('#000000'),
    c2: _hex('#FFFFFF'),
    espnId: 3891,
  ),
  'Al Riyadh': TeamBrand(
    ar: 'الرياض',
    c1: _hex('#CC0000'),
    c2: _hex('#FFFFFF'),
    espnId: 3886,
  ),
  'Abha': TeamBrand(
    ar: 'أبها',
    c1: _hex('#FF0000'),
    c2: _hex('#FFFFFF'),
    espnId: 3890,
  ),
  'Al Faisaly': TeamBrand(
    ar: 'الفيصلي',
    c1: _hex('#FF6600'),
    c2: _hex('#000000'),
    espnId: 3884,
  ),
  'Al Diriyah': TeamBrand(
    ar: 'الدرعية',
    c1: _hex('#006400'),
    c2: _hex('#FFD700'),
    espnId: 38500,
  ),
};

/// The merged registry over all known leagues, for lookup by English name.
final Map<String, TeamBrand> _allTeams = <String, TeamBrand>{
  ...kEplTeams,
  ...kSaudiTeams,
};

/// Other spellings of a registry team, written as [_normalize] leaves
/// them, each pointing at its registry key. Only names known to mean that
/// team: a name not listed is not guessed at (audit L-08).
const Map<String, String> _aliases = <String, String>{
  'man united': 'Manchester United',
  'man utd': 'Manchester United',
  'manchester utd': 'Manchester United',
  'man city': 'Manchester City',
  'tottenham': 'Tottenham Hotspur',
  'spurs': 'Tottenham Hotspur',
  'brighton and hove albion': 'Brighton',
  'brighton hove albion': 'Brighton',
  'nottm forest': 'Nottingham Forest',
  'nott m forest': 'Nottingham Forest',
  'newcastle': 'Newcastle United',
  'leeds': 'Leeds United',
  'ipswich': 'Ipswich Town',
  'coventry': 'Coventry City',
  'hull': 'Hull City',
  'al qadisiyah': 'Al Qadsiah',
  'al qadisiya': 'Al Qadsiah',
  'al ittifaq': 'Al Ettifaq',
  'al taawon': 'Al Taawoun',
  'al feiha': 'Al Fayha',
  'al hazm': 'Al Hazem',
  'al ittihad jeddah': 'Al Ittihad',
};

/// Club-form words a feed puts before or after a name ("Arsenal FC",
/// "Al Hilal SFC", "Al Ahli Saudi", "AFC Bournemouth").
const Set<String> _clubWords = <String>{
  'fc',
  'afc',
  'cf',
  'sc',
  'sfc',
  'club',
  'saudi',
};

/// [name] lower-cased, with hyphens, dots and apostrophes as spaces, "&" as
/// "and", and the club-form words at either end dropped.
String _normalize(String name) {
  final List<String> words = name
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r"[-_.'’]+"), ' ')
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  while (words.length > 1 && _clubWords.contains(words.first)) {
    words.removeAt(0);
  }
  while (words.length > 1 && _clubWords.contains(words.last)) {
    words.removeLast();
  }
  return words.join(' ');
}

/// The registry by [_normalize]d name, and every alias.
final Map<String, TeamBrand> _byNormalName = <String, TeamBrand>{
  for (final MapEntry<String, TeamBrand> entry in _allTeams.entries)
    _normalize(entry.key): entry.value,
  for (final MapEntry<String, String> alias in _aliases.entries)
    alias.key: _allTeams[alias.value]!,
};

/// Looks up a team's brand identity by its English name as returned by the
/// server: the name itself, then its [_normalize]d form against the
/// registry and a short list of known other spellings ("Man United",
/// "Al-Hilal", "Arsenal FC"). Never a partial match: "Al Hilal Omdurman"
/// is not Al Hilal and "Shabab Al Ahli" is not Al Ahli (audit L-08).
/// Returns `null` when [name] is `null`, empty, or not recognized --
/// callers must handle that as a clean fallback, never as an error.
TeamBrand? lookupTeam(String? name) {
  if (name == null) return null;
  final String trimmed = name.trim();
  if (trimmed.isEmpty) return null;

  final TeamBrand? exact = _allTeams[trimmed];
  if (exact != null) return exact;
  return _byNormalName[_normalize(trimmed)];
}

/// The best available display name for a team: the Arabic brand name when
/// [englishName] is recognized, otherwise the raw server value, otherwise a
/// clean "unknown" placeholder — never a raw fixture/team id.
String teamDisplayName(String? englishName) {
  final TeamBrand? brand = lookupTeam(englishName);
  if (brand != null) return brand.ar;
  final String? trimmed = englishName?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return '؟';
}
