import 'package:application/application.dart';

/// The identity-map source name of the Highlightly provider.
const String highlightlySource = 'highlightly';

/// Phase 1 of automatic fixtures (decided 2026-09-16). League names are the
/// rows of `football_data.leagues`; club ids are Highlightly team ids (their
/// app teams are mapped in `supabase/seed/highlightly_team_map_2026_27.sql`).
///
/// * Premier League, Champions League: every match.
/// * League Cup: only ties between two Premier League clubs.
/// * Bundesliga, La Liga, Serie A, Roshan League, Europa League: any match of
///   one of the listed clubs.
const List<ProviderLeagueRule> phaseOneRules = [
  ProviderLeagueRule(
    externalLeagueId: '33973',
    leagueName: 'الدوري الإنجليزي الممتاز',
  ),
  ProviderLeagueRule(externalLeagueId: '2486', leagueName: 'دوري أبطال أوروبا'),
  ProviderLeagueRule(
    externalLeagueId: '67162',
    leagueName: 'الدوري الألماني',
    clubs: {
      '134391', // Bayern Munich
      '141199', // Borussia Dortmund
      '143752', // Bayer Leverkusen
      '148007', // RB Leipzig
      '142901', // Hoffenheim
      '148858', // Schalke 04
    },
  ),
  ProviderLeagueRule(
    externalLeagueId: '119924',
    leagueName: 'الدوري الإسباني',
    clubs: {
      '460324', // Espanyol
      '461175', // Real Madrid
      '451814', // Atletico Madrid
      '456920', // Sevilla
      '450963', // Barcelona
      '462877', // Real Betis
      '462026', // Alaves
      '452665', // Athletic Club
    },
  ),
  ProviderLeagueRule(
    externalLeagueId: '115669',
    leagueName: 'الدوري الإيطالي',
    clubs: {
      '423731', // Roma
      '430539', // Inter
      '415221', // Lazio
      '416923', // AC Milan
      '762429', // Como
      '425433', // Atalanta
      '419476', // Napoli
      '422880', // Juventus
    },
  ),
  ProviderLeagueRule(
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
    externalLeagueId: '3337',
    leagueName: 'الدوري الأوروبي',
    clubs: {
      '68864', // Lyon
      '180345', // Benfica
      '416923', // AC Milan
      '143752', // Bayer Leverkusen
      '69715', // Marseille
      '142901', // Hoffenheim
      '422880', // Juventus
      '635630', // Sunderland
      '171835', // AZ Alkmaar
      '45036', // Crystal Palace
      '30569', // Bournemouth
      '467132', // Real Sociedad
    },
  ),
  ProviderLeagueRule(
    externalLeagueId: '41632',
    leagueName: 'كأس الرابطة الإنجليزية',
    bothFromLeagueName: 'الدوري الإنجليزي الممتاز',
  ),
];
