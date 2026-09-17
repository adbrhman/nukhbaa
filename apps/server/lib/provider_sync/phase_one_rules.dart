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
/// * football-data.org: Premier League and Champions League (every match),
///   Bundesliga, La Liga, Serie A (any match of a listed club).
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
