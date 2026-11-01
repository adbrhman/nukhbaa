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

/// What the match details page is read for (decided by the owner on
/// 2026-11-01, script 188): every Premier League match, and elsewhere the
/// derbies only, in whatever competition they meet (league, Champions
/// League, Europa League). Clubs are named by their football-data.org ids
/// (`supabase/seed/football_data_team_map_2026_27.sql`,
/// `supabase/seed/ligue1_2026_27.sql`), the Roshan clubs by their
/// Highlightly ids (`supabase/seed/highlightly_team_map_2026_27.sql`); a
/// club's catalog team carries both refs where both exist. Any other match
/// is closed without a request.
const MatchDetailsScope matchDetailsScope = MatchDetailsScope(
  fullLeagues: {'الدوري الإنجليزي الممتاز'},
  derbies: [
    MatchDetailsDerby('الكلاسيكو', _realMadrid, _barcelona),
    MatchDetailsDerby('ديربي مدريد', _realMadrid, _atletico),
    MatchDetailsDerby('ديربي برشلونة', _barcelona, _espanyol),
    MatchDetailsDerby('ديربي إشبيلية', _sevilla, _betis),
    MatchDetailsDerby('ديربي ميلانو', _inter, _milan),
    MatchDetailsDerby('ديربي روما', _roma, _lazio),
    MatchDetailsDerby('ديربي إيطاليا', _juventus, _inter),
    MatchDetailsDerby('الكلاسيكر', _bayern, _dortmund),
    MatchDetailsDerby('الكلاسيكو الفرنسي', _paris, _marseille),
    MatchDetailsDerby('ديربي الرياض', _hilal, _nassr),
    MatchDetailsDerby('ديربي جدة', _ittihad, _ahli),
  ],
);

const Set<String> _realMadrid = {'$footballDataSource:86'};
const Set<String> _barcelona = {'$footballDataSource:81'};
const Set<String> _atletico = {'$footballDataSource:78'};
const Set<String> _espanyol = {'$footballDataSource:80'};
const Set<String> _sevilla = {'$footballDataSource:559'};
const Set<String> _betis = {'$footballDataSource:90'};
const Set<String> _inter = {'$footballDataSource:108'};
const Set<String> _milan = {'$footballDataSource:98'};
const Set<String> _juventus = {'$footballDataSource:109'};
const Set<String> _roma = {'$footballDataSource:100'};
const Set<String> _lazio = {'$footballDataSource:110'};
const Set<String> _bayern = {'$footballDataSource:5'};
const Set<String> _dortmund = {'$footballDataSource:4'};
const Set<String> _paris = {'$footballDataSource:524'};
const Set<String> _marseille = {'$footballDataSource:516'};
const Set<String> _hilal = {'$highlightlySource:2495916'};
const Set<String> _nassr = {'$highlightlySource:2501873'};
const Set<String> _ittihad = {'$highlightlySource:2501022'};
const Set<String> _ahli = {'$highlightlySource:2493363'};
const Set<String> _leverkusen = {'$footballDataSource:3'};
const Set<String> _napoli = {'$footballDataSource:113'};

/// The seven leagues the daily selection chooses from (decided by the owner
/// on 2026-11-01, scripts 189-190), in his order of preference: the
/// Premier League and the Champions League keep every match by their own
/// rule. Each league is scored by its own table; the League Cup by the
/// Premier League's, a club from below it placed last. The Roshan League's
/// best match is taken first on a day it plays.
const List<DailySelectionLeague> dailySelectionLeagues = [
  DailySelectionLeague(
    leagueName: 'الدوري الإسباني',
    standings: StandingsRef(source: footballDataSource, leagueRef: 'PD'),
  ),
  DailySelectionLeague(
    leagueName: 'الدوري الألماني',
    standings: StandingsRef(source: footballDataSource, leagueRef: 'BL1'),
  ),
  DailySelectionLeague(
    leagueName: 'الدوري الإيطالي',
    standings: StandingsRef(source: footballDataSource, leagueRef: 'SA'),
  ),
  DailySelectionLeague(
    leagueName: 'الدوري الأوروبي',
    standings: StandingsRef(source: highlightlySource, leagueRef: '3337'),
  ),
  DailySelectionLeague(
    leagueName: 'الدوري الفرنسي',
    standings: StandingsRef(source: footballDataSource, leagueRef: 'FL1'),
  ),
  DailySelectionLeague(
    leagueName: 'كأس الرابطة الإنجليزية',
    standings: StandingsRef(source: footballDataSource, leagueRef: 'PL'),
    outsideTableIsLast: true,
  ),
  DailySelectionLeague(
    leagueName: 'دوري روشن السعودي',
    standings: StandingsRef(source: highlightlySource, leagueRef: '262041'),
    guaranteed: true,
  ),
];

/// The day's numbers (decided by the owner on 2026-11-01): at least 10,
/// up to 15, up to 20 on a day all four of these leagues play.
const DailySelectionPolicy dailySelectionPolicy = DailySelectionPolicy(
  busyLeagues: {
    'الدوري الإسباني',
    'الدوري الألماني',
    'الدوري الإيطالي',
    'الدوري الفرنسي',
  },
);

/// The big clubs (script 190): each adds to a match's score whatever its
/// place, so a strong club having a poor season still counts. Kept by hand,
/// reviewed by the owner once a season or when needed.
const Set<String> dailySelectionBigClubs = {
  ..._realMadrid,
  ..._barcelona,
  ..._atletico,
  ..._bayern,
  ..._dortmund,
  ..._leverkusen,
  ..._inter,
  ..._milan,
  ..._juventus,
  ..._napoli,
  ..._roma,
  ..._paris,
  ..._marseille,
  ..._hilal,
  ..._nassr,
  ..._ittihad,
  ..._ahli,
};

/// The only account told about a day short of matches (decided by the
/// owner on 2026-11-01): his own, never every admin.
const String dailyShortfallRecipient = 'adbrhmanm@gmail.com';
