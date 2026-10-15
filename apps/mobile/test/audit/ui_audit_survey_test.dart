/// UI audit survey -- docs/reviews/ui-audit-2026-10.md, section 3.
///
/// Opens every screen the existing harnesses reach, through the real widgets
/// and providers, in the dark and the light theme, and measures:
///   * Flutter's own guidelines at normal text size: textContrastGuideline,
///     androidTapTargetGuideline and labeledTapTargetGuideline;
///   * every framework error (an overflow above all) while the screen lays
///     out at text scale 1.0, 1.3 and 2.0.
///
/// Each finding is written to build/ui_audit/findings.md, one line each. The
/// counts are a ratchet held in test/audit/ui_audit_baseline.json, measured
/// on the device: a screen may lose findings, never gain one. A fix that
/// removes findings is followed by measuring the baseline again:
///
///   flutter test test/audit/ui_audit_survey_test.dart \
///     --dart-define=UI_AUDIT_WRITE_BASELINE=true
///
/// Two limits, both covered elsewhere: a MergeSemantics card speaks one
/// joined label that textContrastGuideline cannot match to a Text widget
/// (test/core/theme/app_tokens_pairs_contrast_test.dart measures those
/// pairs), and text shrunk by a FittedBox never overflows
/// (ui_known_defects_test.dart, UI-17).
library;

import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/biometric_unlock.dart';
import 'package:mobile/core/auth/install_id.dart';
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/theme/theme_controller.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/auth/account_settings_screen.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/password_reset_screen.dart';
import 'package:mobile/features/auth/rules_screen.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/competition/team_catalog_index.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/duels/duels_screen.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/gamification/insights_screen.dart';
import 'package:mobile/features/gamification/invite_friends_screen.dart';
import 'package:mobile/features/gamification/my_badges_screen.dart';
import 'package:mobile/features/h2h/h2h_round_screen.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/features/history/prediction_history_providers.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/features/leaderboards/champions_providers.dart';
import 'package:mobile/features/leaderboards/champions_record_screen.dart';
import 'package:mobile/features/leaderboards/leaderboards_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_screen.dart';
import 'package:mobile/features/leaderboards/season_leaderboard_screen.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/features/notifications/favorite_teams_screen.dart';
import 'package:mobile/features/notifications/notification_settings_screen.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/features/record/elite_card_screen.dart';
import 'package:mobile/features/record/my_points_screen.dart';
import 'package:mobile/features/record/my_seasons_screen.dart';
import 'package:mobile/features/record/season_record_providers.dart';
import 'package:mobile/features/record/season_record_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../support/auth_harness.dart' as auth;
import '../support/current_month_fixtures_harness.dart' as feed;
import '../support/leaderboards_harness.dart' as boards;
import '../support/prediction_harness.dart' as predictions;

const bool _writeBaseline = bool.fromEnvironment('UI_AUDIT_WRITE_BASELINE');
const String _baselinePath = 'test/audit/ui_audit_baseline.json';
const String _findingsPath = 'build/ui_audit/findings.md';

/// A phone in portrait, and a desktop browser window for the admin panel.
const Size _phone = Size(360, 780);
const Size _desktop = Size(1280, 800);

/// What is measured, in report order.
enum _Check {
  contrast('textContrastGuideline'),
  tapTarget('androidTapTargetGuideline'),
  label('labeledTapTargetGuideline'),
  layout10('layout at x1.0'),
  layout13('layout at x1.3'),
  layout20('layout at x2.0');

  const _Check(this.title);

  final String title;
}

/// Pumps one screen at [scale] in [theme]; it builds and owns its harness.
typedef _Pump =
    Future<void> Function(WidgetTester tester, ThemeData theme, double scale);

class _Screen {
  const _Screen(this.id, this.pump, {this.size = _phone});

  final String id;
  final _Pump pump;
  final Size size;
}

final Map<String, Map<_Check, List<String>>> _measured =
    <String, Map<_Check, List<String>>>{};
Map<String, Map<String, int>> _baseline = <String, Map<String, int>>{};

// ---------------------------------------------------------------------------
// The screens.
// ---------------------------------------------------------------------------

final List<_Screen> _screens = <_Screen>[
  const _Screen('sign-in', _signIn),
  // The whole shell behind SessionGate, every read answered with the
  // signed-in user's /me body: what each tab shows when the server sends
  // something it cannot read -- its error state.
  _Screen('shell.home', _shell(null)),
  _Screen('shell.matches', _shell('nav.item.fixtures')),
  _Screen('shell.h2h', _shell('nav.item.h2h')),
  _Screen('shell.leaderboards', _shell('nav.item.leaders')),
  _Screen('shell.account', _shell('nav.item.account')),
  _Screen('shell.notifications', _shell('home.notifications')),
  // Each tab with real content.
  const _Screen('home.data', _homeWithData),
  const _Screen('matches.open', _matchesOpen),
  const _Screen('matches.live', _matchesLive),
  const _Screen('predictions.data', _predictionsWithData),
  const _Screen('leaderboards.month', _leaderboardsMonth),
  const _Screen('board.widget', _boardWidget),
  // The head-to-head tab with a seated month, each of its sections.
  _Screen('h2h.next', _h2hMonth(0)),
  _Screen('h2h.table', _h2hMonth(1)),
  _Screen('h2h.rounds', _h2hMonth(2)),
  _Screen('h2h.matches', _h2hMatches()),
  const _Screen('bottom-nav', _bottomNav),
  const _Screen('admin.phone', _admin),
  const _Screen('admin.desktop', _admin, size: _desktop),
  // The screens a player opens from these (colour audit of 2026-10-15,
  // CA-09): signing in and its recovery, the account's pages, the records,
  // the badges and the rest of the game.
  const _Screen('sign-in.fingerprint', _signInFingerprint),
  _Screen('password-reset.email', _served(const PasswordResetScreen())),
  _Screen(
    'password-reset.new',
    _served(const PasswordResetScreen(recoveryToken: 'recovery-token')),
  ),
  const _Screen('name-setup', _nameSetup),
  _Screen('rules', _served(const RulesScreen())),
  _Screen('settings', _served(const AccountSettingsScreen())),
  _Screen(
    'notification-settings',
    _served(
      const NotificationSettingsScreen(),
      answers: const <String, Object>{
        '/me/notification-preferences': <String, Object?>{
          'schema_version': 1,
          'prediction_reminder': true,
          'pre_match': false,
          'overtaken': true,
        },
      },
    ),
  ),
  _Screen(
    'favorite-teams',
    _served(const FavoriteTeamsScreen(), answers: _favoriteTeams),
  ),
  _Screen('my-points', _served(const MyPointsScreen(), overrides: _records)),
  _Screen('my-seasons', _served(const MySeasonsScreen(), overrides: _records)),
  _Screen(
    'season-record',
    _served(const SeasonRecordScreen(), overrides: _records),
  ),
  _Screen(
    'elite-card',
    _served(const EliteCardScreen(user: _player), overrides: _records),
  ),
  _Screen('badges', _served(const MyBadgesScreen(), answers: _badges)),
  _Screen('insights', _served(const InsightsScreen(), answers: _insights)),
  _Screen(
    'invite',
    _served(
      const InviteFriendsScreen(),
      answers: const <String, Object>{
        '/me/referral': <String, Object?>{
          'schema_version': 1,
          'code': 'ABCDEFGH',
          'month_points': 3,
          'season_points': 7,
          'invited_count': 5,
          'pending_count': 2,
          'month_cap': 20,
        },
      },
      overrides: <Override>[
        installIdStoreProvider.overrideWithValue(
          const FixedInstallIdStore('inst-12345678'),
        ),
      ],
    ),
  ),
  _Screen(
    'champions-record',
    _served(
      const ChampionsRecordScreen(),
      overrides: <Override>[
        monthChampionsProvider.overrideWith((ref) async => _champions),
      ],
    ),
  ),
  _Screen(
    'season-leaderboard',
    _served(
      const SeasonLeaderboardScreen(seasonId: 's-10', seasonLabel: '10/2026'),
      answers: <String, Object>{
        '/seasons/s-10/fixture-leaderboard': _monthBoard('s-10').toJson(),
        '/champions': _champions.toJson(),
      },
    ),
  ),
  _Screen('duels', _served(const DuelsScreen(), answers: _duels)),
  _Screen(
    'h2h.round',
    _served(
      const H2hRoundScreen(round: 3),
      answers: <String, Object>{
        '/me/h2h-league': _h2hLeague.toJson(),
        '/me/h2h-league/rounds/3': _h2hRound.toJson(),
      },
    ),
  ),
];

Widget _app(ThemeData theme, double scale, Widget home) => MaterialApp(
  theme: theme,
  debugShowCheckedModeBanner: false,
  locale: const Locale('ar'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child ?? const SizedBox.shrink(),
  ),
  home: home,
);

/// The theme preference lives in secure storage, a plugin tests do not have.
Override _themeStore() => themePreferenceStoreProvider.overrideWithValue(
  InMemoryThemePreferenceStore(ThemeMode.dark),
);

Future<void> _signIn(WidgetTester tester, ThemeData theme, double scale) async {
  final auth.AuthHarness harness = auth.buildAuthHarness(
    (http.Request request) async => auth.okMe(auth.sampleUser),
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    SessionScope(
      overrides: <Override>[...harness.overrides, _themeStore()],
      child: _app(theme, scale, const SessionGate()),
    ),
  );
}

_Pump _shell(String? tapKey) =>
    (WidgetTester tester, ThemeData theme, double scale) async {
      final auth.AuthHarness harness = auth.buildAuthHarness(
        (http.Request request) async => auth.okMe(auth.sampleUser),
        seedToken: 'saved-jwt',
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        SessionScope(
          overrides: <Override>[...harness.overrides, _themeStore()],
          child: _app(theme, scale, const SessionGate()),
        ),
      );
      final String? key = tapKey;
      if (key == null) return;
      await _settle(tester);
      await tester.tap(find.byKey(Key(key)));
    };

Future<void> _homeWithData(
  WidgetTester tester,
  ThemeData theme,
  double scale,
) async {
  final auth.AuthHarness harness = auth.buildAuthHarness((
    http.Request request,
  ) async {
    if (request.url.path == '/me/daily-challenge') {
      return _json(
        const MyDailyChallengeDto(
          day: '2026-10-03',
          total: 10,
          predicted: 10,
          complete: true,
        ).toJson(),
      );
    }
    if (request.url.path == '/me/streak') {
      return _json(const MyStreakDto(current: 1, longest: 11).toJson());
    }
    return http.Response('not found', 404);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...harness.overrides,
        currentMonthFixturesProvider.overrideWithValue(
          AsyncData<List<CurrentMonthFixtureItemDto>>(
            <CurrentMonthFixtureItemDto>[feed.sampleFeedItem],
          ),
        ),
        teamCatalogByIdProvider.overrideWithValue(null),
        activeSeasonsProvider.overrideWithValue(
          const AsyncData<List<ActiveSeasonDto>>(<ActiveSeasonDto>[
            ActiveSeasonDto(
              competitionId: 'c-1',
              competitionName: 'شهر 10',
              seasonId: 's-10',
              seasonLabel: '10/2026',
              startAt: '2026-09-30T21:00:00.000Z',
              endAt: '2026-10-31T21:00:00.000Z',
            ),
          ]),
        ),
        myFixturePredictionsByFixtureProvider.overrideWithValue(
          const AsyncData<Map<String, FixturePredictionDto>>(
            <String, FixturePredictionDto>{},
          ),
        ),
        // A two-digit count: the badge the screenshots show over the bell.
        unreadCountProvider.overrideWithValue(const AsyncData<int>(19)),
      ],
      retry: (retryCount, error) => null,
      child: _app(
        theme,
        scale,
        HomeScreen(
          user: const AuthenticatedUserDto(
            userId: 'u-1',
            role: 'user',
            status: 'active',
            displayName: 'عبدالرحمن المغربي',
          ),
          onOpenMatches: () {},
          onOpenAccount: () {},
        ),
      ),
    ),
  );
}

Future<void> _pumpMatches(
  WidgetTester tester,
  ThemeData theme,
  double scale,
  CurrentMonthFixtureItemDto item,
) async {
  final feed.CurrentMonthFixturesHarness harness = feed
      .buildCurrentMonthFixturesHarness((http.Request request) async {
        final String path = request.url.path;
        if (path == '/feed/current-month-fixtures') {
          return feed.okJsonList(<Object?>[item.toJson()]);
        }
        if (path.endsWith('/prediction-distribution')) {
          return feed.okJsonObject(const <String, Object?>{
            'schema_version': 1,
            'home_win_percentage': 86,
            'away_win_percentage': 14,
          });
        }
        return feed.okJsonList(const <Object?>[]);
      });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: _app(theme, scale, const CurrentMonthFixturesScreen()),
    ),
  );
}

/// A match still open: the steppers, the double button, the win shares.
Future<void> _matchesOpen(WidgetTester tester, ThemeData theme, double scale) =>
    _pumpMatches(tester, theme, scale, feed.sampleFeedItem);

/// A match that kicked off half an hour ago: the live score in the middle
/// slot and the "everyone's predictions" button in place of the double.
Future<void> _matchesLive(WidgetTester tester, ThemeData theme, double scale) =>
    _pumpMatches(
      tester,
      theme,
      scale,
      CurrentMonthFixtureItemDto(
        competitionId: 'c-1',
        competitionName: 'الدوري السعودي',
        seasonLabel: '2026/27',
        liveHomeGoals: 1,
        liveAwayGoals: 0,
        liveMinute: 30,
        fixture: SeasonFixtureCardDto(
          seasonId: 's-1',
          fixtureId: 'f-2',
          homeTeam: 'Al Ittihad',
          awayTeam: 'Al Ahli',
          kickoffAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 30))
              .toIso8601String(),
        ),
      ),
    );

/// A finished prediction that scored three points, with its final score.
Future<void> _predictionsWithData(
  WidgetTester tester,
  ThemeData theme,
  double scale,
) async {
  const FixturePredictionDto call = FixturePredictionDto(
    id: 'fp-9',
    participantId: 'part-9',
    fixtureId: 'f-9',
    submittedAt: '2026-09-02T10:00:00.000Z',
    homeGoals: 2,
    awayGoals: 1,
    seasonId: 's-9',
  );
  final predictions.PredictionHarness harness = predictions
      .buildPredictionHarness((http.Request request) async {
        final String path = request.url.path;
        if (path == '/me/fixture-predictions') {
          return predictions.okJsonList(<Object?>[call.toJson()]);
        }
        if (path == '/seasons/s-9/fixtures') {
          return predictions.okJsonList(<Object?>[
            const SeasonFixtureCardDto(
              seasonId: 's-9',
              fixtureId: 'f-9',
              homeTeam: 'Al Hilal',
              awayTeam: 'Al Nassr',
              kickoffAt: '2026-09-03T18:00:00.000Z',
            ).toJson(),
          ]);
        }
        if (path == '/me/fixture-scores') {
          return predictions.okJsonList(<Object?>[
            const MyFixtureScoreDto(
              participantId: 'part-9',
              fixtureId: 'f-9',
              grade: 'exact_scoreline',
              points: 3,
              resultHomeGoals: 2,
              resultAwayGoals: 1,
            ).toJson(),
          ]);
        }
        return predictions.okJsonList(const <Object?>[]);
      });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: _app(theme, scale, const PredictionHistoryScreen()),
    ),
  );
}

/// The month's board with a three-way tie on top, as on 2026-10-03.
Future<void> _leaderboardsMonth(
  WidgetTester tester,
  ThemeData theme,
  double scale,
) async {
  const List<String> names = <String>[
    'وليد العريقي (عاشق النخبة)',
    'ابو الياس',
    'المستشار',
    'حذيفه عبدالخالق حميد المجيدي',
    'Ahmed Alyateem',
    'سارة',
  ];
  final boards.LeaderboardsHarness harness = boards.buildLeaderboardsHarness((
    http.Request request,
  ) async {
    final String path = request.url.path;
    if (path == '/champions') {
      return boards.okJsonObject(const <String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[],
      });
    }
    if (path == '/seasons/s-10/fixture-leaderboard') {
      return boards.okJsonObject(
        FixtureLeaderboardDto(
          seasonId: 's-10',
          entries: <FixtureLeaderboardEntryDto>[
            for (int i = 0; i < names.length; i++)
              FixtureLeaderboardEntryDto(
                rank: i < 3 ? 1 : i + 1,
                participantId: 'u-$i',
                displayName: names[i],
                totalPoints: i < 3 ? 12 : 12 - i,
                fixturesScored: 17 - i,
                exactCount: 3,
                decidedCount: 16,
              ),
          ],
        ).toJson(),
      );
    }
    return http.Response('not found', 404);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...harness.overrides,
        activeSeasonsProvider.overrideWith(
          (ref) async => const <ActiveSeasonDto>[
            ActiveSeasonDto(
              competitionId: 'c-1',
              competitionName: 'شهر 10',
              seasonId: 's-10',
              seasonLabel: '10/2026',
              startAt: '2026-09-30T21:00:00Z',
              endAt: '2026-10-31T21:00:00Z',
            ),
          ],
        ),
        // A fixture of the month's own season: without one the tab shows
        // "the month has not started" instead of the board.
        currentMonthFixturesProvider.overrideWith(
          (ref) async => <CurrentMonthFixtureItemDto>[
            CurrentMonthFixtureItemDto(
              competitionId: 'c-1',
              competitionName: 'Monthly',
              seasonLabel: '10/2026',
              fixture: SeasonFixtureCardDto(
                seasonId: 's-10',
                fixtureId: 'f-10',
                homeTeam: 'Al Hilal',
                awayTeam: 'Al Nassr',
                kickoffAt: feed.futureIso(),
              ),
            ),
          ],
        ),
      ],
      retry: (retryCount, error) => null,
      child: _app(theme, scale, const LeaderboardsScreen(userId: 'u-me')),
    ),
  );
}

Future<void> _boardWidget(WidgetTester tester, ThemeData theme, double scale) =>
    tester.pumpWidget(
      ProviderScope(
        child: _app(
          theme,
          scale,
          Scaffold(
            body: LeaderboardBoard(
              keyPrefix: 'audit',
              myParticipantId: 'p-4',
              showHeader: true,
              entries: <BoardEntry>[
                for (int i = 0; i < 8; i++)
                  BoardEntry(
                    participantId: 'p-$i',
                    rank: i + 1,
                    displayName: 'لاعب رقم ${i + 1}',
                    points: 120 - i * 7,
                    pointsLabel: '${120 - i * 7}',
                    matchesCount: 40 - i,
                    accuracyPercent: 30 + i,
                    movement: i.isEven ? 12 : -3,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> _bottomNav(WidgetTester tester, ThemeData theme, double scale) =>
    tester.pumpWidget(
      _app(
        theme,
        scale,
        Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: NukhbaaBottomNav(
            index: 0,
            onChanged: (int index) {},
          ),
        ),
      ),
    );

Future<void> _admin(WidgetTester tester, ThemeData theme, double scale) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminDashboardProvider.overrideWith(
            (ref) async => const AdminDashboardSnapshot(
              stats: UserStatsDto(total: 120, active: 117, suspended: 3),
              auditLog: AuditLogDto(entries: <AuditEntryDto>[]),
              competitions: <CompetitionDto>[],
              currentMonthFixtures: <CurrentMonthFixtureItemDto>[],
            ),
          ),
          adminAttentionProvider.overrideWith(
            (ref) async =>
                const AdminAttention(heldReferrals: 0, freshErrors: 0),
          ),
          adminMonthPulseProvider.overrideWith(
            (ref) async => const AdminMonthPulse(
              current: null,
              board: null,
              uncrowned: [],
            ),
          ),
          adminRetentionProvider.overrideWith(
            (ref) async => const AdminRetentionDto(
              today: '2026-10-03',
              weeks: <RetentionWeekDto>[
                RetentionWeekDto(
                  weekStart: '2026-09-28',
                  complete: false,
                  activeUsers: 80,
                  active3Plus: 41,
                  leagueActive: 60,
                  leagueActive3Plus: 30,
                  leagueMembers: 90,
                  leagueReturned: null,
                ),
              ],
              cohorts: <RetentionCohortDto>[],
            ),
          ),
        ],
        child: _app(theme, scale, const AdminHubScreen()),
      ),
    );

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const <String, String>{'content-type': 'application/json'},
);

// ---------------------------------------------------------------------------
// Measuring.
// ---------------------------------------------------------------------------

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  } on FlutterError {
    // Endless motion -- a skeleton's shimmer, the live dot's pulse -- never
    // settles; the frames pumped so far are what gets measured.
  }
}

final RegExp _nodeId = RegExp(r'SemanticsNode#\d+');
final RegExp _seeAlso = RegExp(r'See also:\s*\S+');
final RegExp _space = RegExp(r'\s+');
final RegExp _ourCode = RegExp(
  r'(?:package:mobile/|mobile/lib/)([A-Za-z0-9_/]+\.dart):(\d+)',
);

String _tidy(String text) {
  String line = text
      .replaceAll(_nodeId, 'node')
      .replaceAll(_seeAlso, '')
      .replaceAll(_space, ' ')
      .trim();
  if (line.length > 300) line = '${line.substring(0, 300)}...';
  return line.replaceAll('|', r'\|');
}

/// One finding per failing node: a guideline's reason joins every failure,
/// and each failure starts with the node it is about.
List<String> _findingsIn(String? reason, String marker) {
  final String text = reason ?? '';
  if (text.trim().isEmpty) return const <String>[];
  final List<RegExpMatch> starts = _nodeId.allMatches(text).toList();
  final List<String> found = <String>[];
  for (int i = 0; i < starts.length; i++) {
    final int end = i + 1 < starts.length ? starts[i + 1].start : text.length;
    final String record = text.substring(starts[i].start, end);
    if (record.contains(marker)) found.add(_tidy(record));
  }
  // A failure the parser could not split still counts, once.
  if (found.isEmpty) found.add(_tidy(text));
  return found;
}

Future<List<String>> _evaluate(
  WidgetTester tester,
  AccessibilityGuideline guideline,
  String marker,
) async {
  try {
    final Evaluation result = await guideline.evaluate(tester);
    return result.passed
        ? const <String>[]
        : _findingsIn(result.reason, marker);
  } on Object catch (error) {
    return <String>[_tidy('guideline could not run: $error')];
  }
}

/// The error's first line and, when the framework names it, the widget of
/// ours that caused it (`lib/...dart:line`).
String _describe(FlutterErrorDetails details) {
  final String first = details.exceptionAsString().split('\n').first;
  final RegExpMatch? where = _ourCode.firstMatch(details.toString());
  return _tidy(
    where == null ? first : '$first (lib/${where.group(1)}:${where.group(2)})',
  );
}

/// Lays the screen out from scratch at [scale], collecting every framework
/// error instead of failing on the first.
Future<List<String>> _layOut(
  WidgetTester tester,
  _Screen screen,
  ThemeData theme,
  double scale,
) async {
  final List<String> errors = <String>[];
  final void Function(FlutterErrorDetails details)? previous =
      FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    errors.add(_describe(details));
  };
  try {
    await tester.pumpWidget(const SizedBox.shrink());
    await screen.pump(tester, theme, scale);
    await _settle(tester);
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

Future<Map<_Check, List<String>>> _measure(
  WidgetTester tester,
  _Screen screen,
  ThemeData theme,
) async {
  tester.view.physicalSize = screen.size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final Map<_Check, List<String>> found = <_Check, List<String>>{};
  final SemanticsHandle semantics = tester.ensureSemantics();
  try {
    found[_Check.layout10] = await _layOut(tester, screen, theme, 1.0);
    found[_Check.contrast] = await _evaluate(
      tester,
      textContrastGuideline,
      'Expected contrast ratio',
    );
    found[_Check.tapTarget] = await _evaluate(
      tester,
      androidTapTargetGuideline,
      'expected tap target size',
    );
    found[_Check.label] = await _evaluate(
      tester,
      labeledTapTargetGuideline,
      'expected tappable node to have semantic label',
    );
    found[_Check.layout13] = await _layOut(tester, screen, theme, 1.3);
    found[_Check.layout20] = await _layOut(tester, screen, theme, 2.0);
  } finally {
    semantics.dispose();
  }
  return found;
}

// ---------------------------------------------------------------------------
// The ratchet and the findings file.
// ---------------------------------------------------------------------------

Map<String, Map<String, int>> _readBaseline() {
  final File file = File(_baselinePath);
  if (!file.existsSync()) return <String, Map<String, int>>{};
  final Object? decoded = jsonDecode(file.readAsStringSync());
  final Map<String, Map<String, int>> result = <String, Map<String, int>>{};
  if (decoded is! Map<String, Object?>) return result;
  for (final MapEntry<String, Object?> screen in decoded.entries) {
    final Object? counts = screen.value;
    if (counts is! Map<String, Object?>) continue;
    result[screen.key] = <String, int>{
      for (final MapEntry<String, Object?> count in counts.entries)
        if (count.value is int) count.key: count.value as int,
    };
  }
  return result;
}

void _writeFiles() {
  final List<String> keys = _measured.keys.toList()..sort();
  final StringBuffer out = StringBuffer()
    ..writeln('# UI audit -- measured findings')
    ..writeln()
    ..writeln(
      'Generated by `apps/mobile/test/audit/ui_audit_survey_test.dart` '
      'through the real screens (docs/reviews/ui-audit-2026-10.md, '
      'section 3). One line per finding; the counts are the ratchet in '
      '`apps/mobile/test/audit/ui_audit_baseline.json`.',
    )
    ..writeln()
    ..writeln(
      '| screen/theme | ${_Check.values.map((_Check c) => c.name).join(' | ')} |',
    )
    ..writeln(
      '|---|${List<String>.filled(_Check.values.length, '---:').join('|')}|',
    );
  for (final String key in keys) {
    final Map<_Check, List<String>> found = _measured[key]!;
    final String counts = _Check.values
        .map((_Check c) => '${found[c]?.length ?? 0}')
        .join(' | ');
    out.writeln('| $key | $counts |');
  }
  for (final String key in keys) {
    final Map<_Check, List<String>> found = _measured[key]!;
    if (found.values.every((List<String> lines) => lines.isEmpty)) continue;
    out
      ..writeln()
      ..writeln('## $key');
    for (final _Check check in _Check.values) {
      final List<String> lines = found[check] ?? const <String>[];
      if (lines.isEmpty) continue;
      out
        ..writeln()
        ..writeln('**${check.title}** (${lines.length})')
        ..writeln();
      for (final String line in lines) {
        out.writeln('- $line');
      }
    }
  }
  File(_findingsPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(out.toString());

  if (!_writeBaseline) return;
  final Map<String, Map<String, int>> counts = <String, Map<String, int>>{
    for (final String key in keys)
      key: <String, int>{
        for (final _Check check in _Check.values)
          check.name: _measured[key]![check]?.length ?? 0,
      },
  };
  File(_baselinePath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(counts)}\n',
  );
}

void main() {
  setUpAll(() {
    _baseline = _readBaseline();
  });
  tearDownAll(_writeFiles);

  for (final _Screen screen in _screens) {
    for (final (String themeName, ThemeData theme) in <(String, ThemeData)>[
      ('dark', AppTheme.dark),
      ('light', AppTheme.light),
    ]) {
      final String key = '${screen.id}/$themeName';
      testWidgets('survey: $key', (WidgetTester tester) async {
        final Map<_Check, List<String>> found = await _measure(
          tester,
          screen,
          theme,
        );
        _measured[key] = found;
        if (_writeBaseline) return;

        final Map<String, int>? base = _baseline[key];
        expect(
          base,
          isNotNull,
          reason:
              'no baseline for $key: measure it with '
              '--dart-define=UI_AUDIT_WRITE_BASELINE=true',
        );
        for (final _Check check in _Check.values) {
          final List<String> lines = found[check] ?? const <String>[];
          expect(
            lines.length,
            lessThanOrEqualTo(base![check.name] ?? 0),
            reason: '$key gained ${check.title} findings:\n${lines.join('\n')}',
          );
        }
      });
    }
  }
}

/// A seated head-to-head month: a live round, a settled one, a void one,
/// the next one open with its first kickoff, and a group of six.
H2hStandingDto _h2hLine(int rank, String name, {bool me = false}) =>
    H2hStandingDto(
      rank: rank,
      userId: 'u-$rank',
      displayName: name,
      played: 2,
      won: rank <= 2 ? 1 : 0,
      drawn: 1,
      lost: rank <= 2 ? 0 : 1,
      leaguePoints: rank <= 2 ? 4 : 1,
      pointsFor: 120 - rank * 9,
      exactCount: 1,
      form: const <String>['win', 'draw'],
      isMe: me,
    );

final MyH2hLeagueDto _h2hLeague = MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-10-01',
  startsOn: '2026-11-01',
  isPilot: true,
  division: 1,
  groupIndex: 0,
  myRank: 2,
  promotionZone: 0,
  relegationZone: 3,
  daysLeft: 21,
  standings: <H2hStandingDto>[
    _h2hLine(1, 'عبدالرحمن المغربي'),
    _h2hLine(2, 'سليمان الرفاعي', me: true),
    _h2hLine(3, 'ناصر هيثم'),
    _h2hLine(4, 'شادي الصرمي'),
    _h2hLine(5, 'عبدالكريم أبو يحيى'),
    _h2hLine(6, ''),
  ],
  rounds: const <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 1,
      day: '2026-10-10',
      status: 'settled',
      fixtureCount: 22,
      opponentUserId: 'u-5',
      opponentName: 'عبدالكريم أبو يحيى',
      myPoints: 31,
      opponentPoints: 24,
      result: 'win',
    ),
    H2hRoundViewDto(
      round: 2,
      day: '2026-10-11',
      status: 'voided',
      fixtureCount: 0,
    ),
    H2hRoundViewDto(
      round: 3,
      day: '2026-10-13',
      status: 'live',
      fixtureCount: 9,
      opponentUserId: 'u-1',
      opponentName: 'عبدالرحمن المغربي',
      myPoints: 12,
      opponentPoints: 15,
      result: 'loss',
    ),
    H2hRoundViewDto(
      round: 4,
      day: '2026-10-17',
      status: 'open',
      fixtureCount: 7,
      firstKickoff: '2026-10-17T15:00:00.000Z',
    ),
  ],
);

_Pump _h2hMonth(int section) =>
    (WidgetTester tester, ThemeData theme, double scale) async {
      final auth.AuthHarness harness = auth.buildAuthHarness((
        http.Request request,
      ) async {
        if (request.url.path == '/me/h2h-league') {
          return _json(_h2hLeague.toJson());
        }
        return http.Response('not found', 404);
      }, seedToken: 'saved-jwt');
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          retry: (retryCount, error) => null,
          child: _app(
            theme,
            scale,
            H2hScreen(
              initialSection: section,
              onOpenMatches: () {},
              now: () => DateTime.utc(2026, 10, 13, 11, 39, 30),
            ),
          ),
        ),
      );
    };

/// The live round of [_h2hLeague] as its group plays it: three pairs, the
/// caller's first.
const H2hGroupRoundDto _h2hGroup = H2hGroupRoundDto(
  round: 3,
  day: '2026-10-13',
  status: 'live',
  matches: <H2hGroupMatchDto>[
    H2hGroupMatchDto(
      homeUserId: 'u-2',
      homeName: 'سليمان الرفاعي',
      homeIsMe: true,
      homePoints: 12,
      awayUserId: 'u-1',
      awayName: 'عبدالرحمن المغربي',
      awayPoints: 15,
      winner: 'away',
    ),
    H2hGroupMatchDto(
      homeUserId: 'u-3',
      homeName: 'ناصر هيثم',
      homePoints: 9,
      awayUserId: 'u-6',
      awayName: '',
      awayPoints: 9,
      winner: 'draw',
    ),
    H2hGroupMatchDto(
      homeUserId: 'u-4',
      homeName: 'شادي الصرمي',
      homePoints: 21,
      awayPoints: 11.5,
      winner: 'home',
    ),
  ],
);

_Pump _h2hMatches() =>
    (WidgetTester tester, ThemeData theme, double scale) async {
      final auth.AuthHarness harness = auth.buildAuthHarness((
        http.Request request,
      ) async {
        if (request.url.path == '/me/h2h-league') {
          return _json(_h2hLeague.toJson());
        }
        if (request.url.path == '/me/h2h-league/rounds/3/matches') {
          return _json(_h2hGroup.toJson());
        }
        return http.Response('not found', 404);
      }, seedToken: 'saved-jwt');
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          retry: (retryCount, error) => null,
          child: _app(
            theme,
            scale,
            H2hScreen(
              initialSection: 3,
              onOpenMatches: () {},
              now: () => DateTime.utc(2026, 10, 13, 11, 39, 30),
            ),
          ),
        ),
      );
    };

// ---------------------------------------------------------------------------
// The screens a player opens from the tabs (colour audit of 2026-10-15,
// CA-09), each through its real providers over the real transport.
// ---------------------------------------------------------------------------

/// [home] over the real transport: each path in [answers] is answered with
/// its JSON body, any other with 404; [overrides] go after the harness's.
_Pump _served(
  Widget home, {
  Map<String, Object> answers = const <String, Object>{},
  List<Override> overrides = const <Override>[],
}) => (WidgetTester tester, ThemeData theme, double scale) async {
  final auth.AuthHarness harness = auth.buildAuthHarness((
    http.Request request,
  ) async {
    final Object? body = answers[request.url.path];
    if (body == null) return http.Response('not found', 404);
    return http.Response(
      jsonEncode(body),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }, seedToken: 'saved-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[...harness.overrides, ...overrides],
      retry: (retryCount, error) => null,
      child: _app(theme, scale, home),
    ),
  );
};

/// A sensor that is there and would pass; the survey never taps it.
final class _Sensor implements BiometricAuthenticator {
  const _Sensor();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async => true;
}

/// The sign-in screen after a sign-out with fingerprint unlock on: the
/// fingerprint button over the password form.
Future<void> _signInFingerprint(
  WidgetTester tester,
  ThemeData theme,
  double scale,
) async {
  final InMemoryBiometricPreferenceStore prefs =
      InMemoryBiometricPreferenceStore(enabled: true, offered: true);
  await prefs.saveRefreshToken('r1');
  final auth.AuthHarness harness = auth.buildAuthHarness(
    (http.Request request) async => auth.okMe(auth.sampleUser),
    biometricStore: prefs,
    biometricAuthenticator: const _Sensor(),
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    SessionScope(
      overrides: <Override>[...harness.overrides, _themeStore()],
      child: _app(theme, scale, const SessionGate()),
    ),
  );
}

/// A first Google sign-in: the account still carries the automatic name,
/// and the gate asks for one before the app opens.
Future<void> _nameSetup(
  WidgetTester tester,
  ThemeData theme,
  double scale,
) async {
  final auth.AuthHarness harness = auth.buildAuthHarness(
    (http.Request request) async => auth.okMe(
      const AuthenticatedUserDto(
        userId: 'u-1',
        role: 'user',
        status: 'active',
        email: 'n72914939@gmail.com',
        displayName: 'n72914939',
      ),
    ),
    seedToken: 'saved-jwt',
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    SessionScope(
      overrides: <Override>[...harness.overrides, _themeStore()],
      child: _app(theme, scale, const SessionGate()),
    ),
  );
}

const AuthenticatedUserDto _player = AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  displayName: 'عبدالرحمن المغربي',
);

const List<String> _boardNames = <String>[
  'وليد العريقي (عاشق النخبة)',
  'ابو الياس',
  'المستشار',
  'حذيفه عبدالخالق حميد المجيدي',
  'Ahmed Alyateem',
  'عبدالرحمن المغربي',
];

/// A month's board: a three-way tie on top, the caller sixth.
FixtureLeaderboardDto _monthBoard(String seasonId) => FixtureLeaderboardDto(
  seasonId: seasonId,
  entries: <FixtureLeaderboardEntryDto>[
    for (int i = 0; i < _boardNames.length; i++)
      FixtureLeaderboardEntryDto(
        rank: i < 3 ? 1 : i + 1,
        participantId: i == _boardNames.length - 1 ? 'p-me' : 'p-$i',
        displayName: _boardNames[i],
        totalPoints: i < 3 ? 60 : 60 - i * 3,
        fixturesScored: 115 - i,
        exactCount: 14 - i,
        decidedCount: 110 - i,
      ),
  ],
);

/// Two finished months and the current one, for the record pages.
const List<MySeasonRecordDto> _seasonRecords = <MySeasonRecordDto>[
  MySeasonRecordDto(
    competitionId: 'c-1',
    competitionName: 'شهر 10',
    seasonId: 's-10',
    seasonLabel: '10/2026',
    startAt: '2026-09-30T21:00:00.000Z',
    endAt: '2026-10-31T21:00:00.000Z',
    rank: 6,
    totalPoints: 45,
    entryCount: 111,
    exactCount: 14,
    settledCount: 110,
  ),
  MySeasonRecordDto(
    competitionId: 'c-1',
    competitionName: 'شهر 9',
    seasonId: 's-9',
    seasonLabel: '09/2026',
    startAt: '2026-08-31T21:00:00.000Z',
    endAt: '2026-09-30T21:00:00.000Z',
    rank: 1,
    totalPoints: 128,
    entryCount: 240,
    exactCount: 31,
    settledCount: 236,
  ),
  MySeasonRecordDto(
    competitionId: 'c-1',
    competitionName: 'شهر 8',
    seasonId: 's-8',
    seasonLabel: '08/2026',
    startAt: '2026-07-31T21:00:00.000Z',
    endAt: '2026-08-31T21:00:00.000Z',
    rank: 23,
    totalPoints: 71,
  ),
];

/// The records, each month's board and one prediction, as the record pages
/// read them.
final List<Override> _records = <Override>[
  mySeasonRecordsProvider.overrideWith((ref) async => _seasonRecords),
  for (final MySeasonRecordDto record in _seasonRecords)
    fixtureLeaderboardProvider(
      record.seasonId,
    ).overrideWith((ref) async => _monthBoard(record.seasonId)),
  myFixturePredictionsProvider.overrideWith(
    (ref) async => const <FixturePredictionDto>[
      FixturePredictionDto(
        id: 'fp-1',
        participantId: 'p-me',
        fixtureId: 'f-1',
        seasonId: 's-10',
        submittedAt: '2026-10-02T10:00:00.000Z',
        homeGoals: 1,
        awayGoals: 0,
        isDouble: false,
      ),
    ],
  ),
];

/// Two crowned months: a shared crown, then a single champion.
const MonthChampionsDto _champions = MonthChampionsDto(
  champions: <MonthChampionDto>[
    MonthChampionDto(
      seasonId: 's-9',
      seasonLabel: '09/2026',
      userId: 'u-2',
      displayName: 'وليد العريقي (عاشق النخبة)',
      points: 128,
      exactCount: 31,
      decidedCount: 236,
      referralPoints: 4,
      crownedAt: '2026-10-01T09:00:00.000Z',
      celebrateUntil: '2026-10-04T09:00:00.000Z',
      prize: 'اشتراك شهري',
    ),
    MonthChampionDto(
      seasonId: 's-9',
      seasonLabel: '09/2026',
      userId: 'u-3',
      displayName: 'ابو الياس',
      points: 128,
      exactCount: 29,
      decidedCount: 236,
      referralPoints: 0,
      crownedAt: '2026-10-01T09:00:00.000Z',
      celebrateUntil: '2026-10-04T09:00:00.000Z',
    ),
    MonthChampionDto(
      seasonId: 's-8',
      seasonLabel: '08/2026',
      userId: 'u-4',
      displayName: 'حذيفه عبدالخالق حميد المجيدي',
      points: 97,
      exactCount: 22,
      decidedCount: 180,
      referralPoints: 2,
      crownedAt: '2026-09-01T09:00:00.000Z',
      celebrateUntil: '2026-09-04T09:00:00.000Z',
    ),
  ],
);

const List<String> _badgeCodes = <String>[
  'first_prediction',
  'predictions_25',
  'predictions_100',
  'first_perfect_day',
  'perfect_days_7',
  'perfect_days_30',
  'league_first_week',
  'league_promoted',
  'league_champion',
  'league_elite',
];

/// The whole wall: one badge held, two on their way, the rest locked.
final Map<String, Object> _badges = <String, Object>{
  '/me/badges': <String, Object?>{
    'schema_version': 1,
    'badges': <Map<String, Object?>>[
      for (final String code in _badgeCodes)
        <String, Object?>{
          'code': code,
          'current': switch (code) {
            'first_prediction' => 1,
            'predictions_25' || 'predictions_100' => 7,
            _ => 0,
          },
          'target': switch (code) {
            'predictions_25' => 25,
            'predictions_100' => 100,
            'perfect_days_7' => 7,
            'perfect_days_30' => 30,
            _ => 1,
          },
          'unlocked_at': code == 'first_prediction'
              ? '2026-09-20T08:00:00.000Z'
              : null,
        },
    ],
  },
};

const List<String> _weekStarts = <String>[
  '2026-08-10',
  '2026-08-17',
  '2026-08-24',
  '2026-08-31',
  '2026-09-07',
  '2026-09-14',
  '2026-09-21',
  '2026-09-28',
];

/// The month, the recap of last week and eight weeks of accuracy.
final Map<String, Object> _insights = <String, Object>{
  '/me/insights': <String, Object?>{
    'schema_version': 1,
    'month': <String, Object?>{
      'decided': 40,
      'correct': 23,
      'exact': 6,
      'percent': 58,
    },
    'community_percent': 51,
    'leagues': <Object?>[],
    'best_league': 'دوري روشن السعودي',
    'longest_correct_run': 5,
    'weeks': <Object?>[
      for (int i = 0; i < _weekStarts.length; i++)
        <String, Object?>{
          'week_start': _weekStarts[i],
          'decided': 10 + i,
          'correct': 5,
          'exact': 1,
          'percent': i == 0 ? null : 40 + i * 4,
        },
    ],
    'last_week': <String, Object?>{
      'week_start': '2026-10-05',
      'decided': 12,
      'correct': 8,
      'exact': 2,
      'percent': 67,
      'points': 14,
      'best': <String, Object?>{
        'home_team': 'الهلال',
        'away_team': 'النصر',
        'points': 6,
        'exact': true,
      },
    },
  },
};

Map<String, Object?> _team(String id, String name) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'name': name,
  'short_name': null,
  'crest_url': null,
  'league_id': null,
};

/// Four teams, two of them chosen.
final Map<String, Object> _favoriteTeams = <String, Object>{
  '/teams': <Object?>[
    _team('11111111-1111-4111-8111-111111111111', 'Al Hilal'),
    _team('22222222-2222-4222-8222-222222222222', 'Al Nassr'),
    _team('33333333-3333-4333-8333-333333333333', 'Al Ittihad'),
    _team('44444444-4444-4444-8444-444444444444', 'Al Ahli'),
  ],
  '/me/favorite-teams': <String, Object?>{
    'schema_version': 1,
    'team_ids': <String>[
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
    ],
  },
};

Map<String, Object?> _challenge({
  required String id,
  required String code,
  bool isMine = false,
  bool isForMe = false,
}) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'code': code,
  'season_id': 's-1',
  'fixture_id': 'f-1',
  'home_team': 'الهلال',
  'away_team': 'النصر',
  'kickoff_at': '2099-01-01T18:00:00.000Z',
  'challenger_user_id': isMine ? 'me' : 'rival',
  'challenger_name': isMine ? 'عبدالرحمن المغربي' : 'سليمان الرفاعي',
  'is_private': isForMe,
  'capacity': isForMe ? 1 : 5,
  'accepted_count': 0,
  'state': 'open',
  'is_mine': isMine,
  'is_for_me': isForMe,
};

Map<String, Object?> _duel({
  required String id,
  required String state,
  required String kickoffAt,
  int? myPoints,
  int? opponentPoints,
  String? outcome,
}) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'challenge_id': 'c-$id',
  'fixture_id': 'f-$id',
  'home_team': 'الاتحاد',
  'away_team': 'الأهلي',
  'kickoff_at': kickoffAt,
  'accepted_at': '2026-10-05T12:00:00.000Z',
  'is_challenger': state == 'upcoming',
  'opponent_user_id': 'rival',
  'opponent_name': 'حذيفه عبدالخالق حميد المجيدي',
  'my_home_goals': 2,
  'my_away_goals': 1,
  'my_is_double': state == 'settled',
  'opponent_home_goals': state == 'settled' ? 0 : null,
  'opponent_away_goals': state == 'settled' ? 0 : null,
  'opponent_is_double': state == 'settled' ? false : null,
  'state': state,
  'my_points': myPoints,
  'opponent_points': opponentPoints,
  'outcome': outcome,
};

/// An invitation for the caller, the caller's own open challenge, a duel
/// still to play and one won.
final Map<String, Object> _duels = <String, Object>{
  '/me/duels': <String, Object?>{
    'schema_version': 1,
    'challenges': <Object?>[
      _challenge(id: 'c-in', code: 'INVITEDCODE2', isForMe: true),
      _challenge(id: 'c-own', code: 'MYOWNCODE234', isMine: true),
    ],
    'duels': <Object?>[
      _duel(id: 'up', state: 'upcoming', kickoffAt: '2099-01-01T18:00:00.000Z'),
      _duel(
        id: 'done',
        state: 'settled',
        kickoffAt: '2026-10-01T18:00:00.000Z',
        myPoints: 6,
        opponentPoints: 0,
        outcome: 'won',
      ),
    ],
  },
  '/me/fixture-predictions': <Object?>[
    <String, Object?>{
      'schema_version': 1,
      'id': 'fp-1',
      'participant_id': 'p-1',
      'fixture_id': 'f-1',
      'submitted_at': '2026-10-05T10:00:00.000Z',
      'home_goals': 3,
      'away_goals': 2,
      'is_double': true,
    },
  ],
};

/// The live round of [_h2hLeague] in detail: a finished match with both
/// picks, one not started with the opponent's hidden, one moved off.
final MyH2hRoundDto _h2hRound = MyH2hRoundDto(
  round: 3,
  day: '2026-10-13',
  status: 'live',
  fixtureCount: 3,
  firstKickoff: '2026-10-13T12:00:00.000Z',
  opponentUserId: 'u-1',
  opponentName: 'عبدالرحمن المغربي',
  myPoints: 12,
  opponentPoints: 15,
  result: 'loss',
  mine: const H2hSideTotalsDto(predicted: 2, exact: 1, doubles: 1),
  theirs: const H2hSideTotalsDto(predicted: 3, exact: 1, doubles: 0),
  fixtures: <H2hRoundFixtureDto>[
    H2hRoundFixtureDto(
      fixtureId: 'f1',
      homeTeam: 'الهلال',
      awayTeam: 'النصر',
      kickoffAt: '2026-10-13T12:00:00.000Z',
      state: 'finished',
      homeGoals: 2,
      awayGoals: 1,
      mine: const H2hPickDto(
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
        points: 6,
        exact: true,
      ),
      theirs: const H2hPickDto(
        homeGoals: 0,
        awayGoals: 3,
        isDouble: false,
        points: 0,
      ),
      theirsHidden: false,
    ),
    H2hRoundFixtureDto(
      fixtureId: 'f2',
      homeTeam: 'الاتحاد',
      awayTeam: 'الأهلي',
      kickoffAt: '2026-10-13T15:00:00.000Z',
      state: 'not_started',
      mine: const H2hPickDto(homeGoals: 1, awayGoals: 0, isDouble: false),
      theirsHidden: true,
    ),
    H2hRoundFixtureDto(
      fixtureId: 'f3',
      homeTeam: 'الشباب',
      awayTeam: 'الفتح',
      kickoffAt: '2026-10-14T18:00:00.000Z',
      state: 'void',
      theirsHidden: true,
    ),
  ],
);
