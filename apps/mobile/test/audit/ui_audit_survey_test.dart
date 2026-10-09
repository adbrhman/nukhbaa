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
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/theme/theme_controller.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/competition/team_catalog_index.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_screen.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
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
  const _Screen('bottom-nav', _bottomNav),
  const _Screen('admin.phone', _admin),
  const _Screen('admin.desktop', _admin, size: _desktop),
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
        if (path == '/seasons/s-9/fixtures/f-9/scores') {
          return predictions.okJsonObject(
            const FixtureScoresDto(
              fixtureId: 'f-9',
              resultHomeGoals: 2,
              resultAwayGoals: 1,
              scores: <ParticipantFixtureScoreDto>[
                ParticipantFixtureScoreDto(
                  fixtureId: 'f-9',
                  participantId: 'part-9',
                  rulesetVersion: 1,
                  grade: 'exact_scoreline',
                  points: 3,
                ),
              ],
            ).toJson(),
          );
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
