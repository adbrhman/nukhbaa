import 'package:application/application.dart';

/// The identity-map source name of the Highlightly provider.
const String highlightlySource = 'highlightly';

/// The identity-map source name of the football-data.org provider.
const String footballDataSource = 'football-data';

/// Phase 1 of automatic fixtures (decided 2026-09-16, providers split
/// 2026-09-17). League names are the rows of `football_data.leagues`; club
/// ids are the serving provider's team ids (their app teams are mapped in
/// `supabase/seed/highlightly_team_map_2026_27.sql` and
/// `supabase/seed/football_data_team_map_2026_27.sql`).
///
/// * football-data.org: Premier League, Champions League, La Liga and
///   Ligue 1 (every match), Bundesliga and Serie A (any match of a listed
///   club).
/// * Highlightly: Roshan League and Europa League (any match of a listed
///   club), League Cup (only ties between two Premier League clubs).
const List<ProviderLeagueRule> phaseOneRules = [
  ProviderLeagueRule(
    source: footballDataSource,
    externalLeagueId: 'PL',
    leagueName: 'الدوري الإنجليزي الممتاز',
  ),
  ProviderLeagueRule(
    source: footballDataSource,
    externalLeagueId: 'CL',
    leagueName: 'دوري أبطال أوروبا',
  ),
  ProviderLeagueRule(
    source: footballDataSource,
    externalLeagueId: 'BL1',
    leagueName: 'الدوري الألماني',
    clubs: {
      '5', // Bayern Munich
      '4', // Borussia Dortmund
      '3', // Bayer Leverkusen
      '721', // RB Leipzig
      '2', // Hoffenheim
      '6', // Schalke 04
    },
  ),
  ProviderLeagueRule(
    source: footballDataSource,
    externalLeagueId: 'PD',
    leagueName: 'الدوري الإسباني',
  ),
  ProviderLeagueRule(
    source: footballDataSource,
    externalLeagueId: 'SA',
    leagueName: 'الدوري الإيطالي',
    clubs: {
      '100', // Roma
      '108', // Inter
      '110', // Lazio
      '98', // AC Milan
      '7397', // Como
      '102', // Atalanta
      '113', // Napoli
      '109', // Juventus
    },
  ),
  ProviderLeagueRule(
    source: footballDataSource,
    externalLeagueId: 'FL1',
    leagueName: 'الدوري الفرنسي',
  ),
  ProviderLeagueRule(
    source: highlightlySource,
    externalLeagueId: '262041',
    leagueName: 'دوري روشن السعودي',
    clubs: {
      '2495916', // Al Hilal
      '2501022', // Al Ittihad
      '2501873', // Al Nassr
      '2496767', // Al Qadsiah
      '2493363', // Al Ahli
    },
  ),
  ProviderLeagueRule(
    source: highlightlySource,
    externalLeagueId: '3337',
    leagueName: 'الدوري الأوروبي',
  ),
  ProviderLeagueRule(
    source: highlightlySource,
    externalLeagueId: '41632',
    leagueName: 'كأس الرابطة الإنجليزية',
    bothFromLeagueName: 'الدوري الإنجليزي الممتاز',
  ),
];

/// Highlightly's league ids for the match details page (script 118), by the
/// league's name in `football_data.leagues`: the five football-data.org
/// leagues and the Champions League read by the probe of 2026-10-19
/// (script 117), and the three Highlightly already serves. A fixture of any
/// other league gets no details.
const Map<String, String> matchDetailsLeagueIds = <String, String>{
  'الدوري الإنجليزي الممتاز': '33973',
  'الدوري الإسباني': '119924',
  'الدوري الإيطالي': '115669',
  'الدوري الألماني': '67162',
  'الدوري الفرنسي': '52695',
  'دوري أبطال أوروبا': '2486',
  'دوري روشن السعودي': '262041',
  'الدوري الأوروبي': '3337',
  'كأس الرابطة الإنجليزية': '41632',
};
