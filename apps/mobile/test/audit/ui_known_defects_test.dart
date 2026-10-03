/// The known UI defects of docs/reviews/ui-audit-2026-10.md, one focused
/// test each, through the real widgets. Every test states what the screen
/// should do once the finding is fixed, so each group is skipped with its
/// finding id and reason until the fix lands; the fix removes the skip in
/// the same commit, and the test then holds the line.
library;

import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/app_badge.dart';
import 'package:mobile/core/ui/segmented_pills.dart';
import 'package:mobile/core/ui/team_logo.dart';
import 'package:mobile/core/ui/user_avatar.dart';
import 'package:mobile/features/admin/widgets/admin_ui_kit.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/competition/team_catalog_index.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixtures_date_bar.dart';
import 'package:mobile/features/fixture_prediction/widgets/live_matches_chip.dart';
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

final AppLocalizations _ar = lookupAppLocalizations(const Locale('ar'));
final AppTokens _dark = AppTheme.dark.extension<AppTokens>()!;
final AppTokens _light = AppTheme.light.extension<AppTokens>()!;

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A finding that is known and not fixed yet: skipped with its id and
/// reason, so `flutter test` lists it on every run.
void _known(
  String id,
  String reason,
  String description,
  WidgetTesterCallback body,
) {
  group(id, () {
    testWidgets(description, body);
  }, skip: '$id: $reason');
}

Widget _app(ThemeData theme, Widget home, {double scale = 1.0}) => MaterialApp(
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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// What actually sits behind [of]: every coloured box above it, outermost
/// first, composited onto [base].
Color _backdrop(Finder of, Color base) {
  final List<Color> layers = <Color>[];
  for (final Element element
      in find
          .ancestor(of: of, matching: find.byType(DecoratedBox))
          .evaluate()) {
    final Decoration decoration = (element.widget as DecoratedBox).decoration;
    final Color? color = switch (decoration) {
      BoxDecoration(:final Color? color) => color,
      ShapeDecoration(:final Color? color) => color,
      _ => null,
    };
    if (color != null) layers.add(color);
  }
  Color result = base;
  for (final Color layer in layers.reversed) {
    result = Color.alphaBlend(layer, result);
  }
  return result;
}

Color _textColor(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style!.color!;

Future<void> _pumpOpenMatch(
  WidgetTester tester, {
  ThemeData? theme,
  double scale = 1.0,
}) async {
  final feed.CurrentMonthFixturesHarness harness = feed
      .buildCurrentMonthFixturesHarness((http.Request request) async {
        final String path = request.url.path;
        if (path == '/feed/current-month-fixtures') {
          return feed.okJsonList(<Object?>[feed.sampleFeedItem.toJson()]);
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
      child: _app(
        theme ?? AppTheme.dark,
        const CurrentMonthFixturesScreen(),
        scale: scale,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpHome(WidgetTester tester, ThemeData theme) async {
  final auth.AuthHarness harness = auth.buildAuthHarness((
    http.Request request,
  ) async {
    if (request.url.path == '/me/daily-challenge') {
      return http.Response(
        jsonEncode(
          const MyDailyChallengeDto(
            day: '2026-10-03',
            total: 10,
            predicted: 10,
            complete: true,
          ).toJson(),
        ),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    if (request.url.path == '/me/streak') {
      return http.Response(
        jsonEncode(const MyStreakDto(current: 1, longest: 11).toJson()),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
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
        unreadCountProvider.overrideWithValue(const AsyncData<int>(19)),
      ],
      retry: (retryCount, error) => null,
      child: _app(
        theme,
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
  await tester.pumpAndSettle();
}

Future<void> _pumpBoard(
  WidgetTester tester,
  ThemeData theme,
  List<BoardEntry> entries, {
  String? me,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        theme,
        Scaffold(
          body: LeaderboardBoard(
            keyPrefix: 'k',
            myParticipantId: me,
            showHeader: true,
            entries: entries,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BoardEntry _entry(int i, int rank, {int? movement}) => BoardEntry(
  participantId: 'p-$i',
  rank: rank,
  displayName: 'لاعب ${i + 1}',
  points: 100 - i,
  pointsLabel: '${100 - i}',
  matchesCount: 20,
  accuracyPercent: 30,
  movement: movement,
);

void main() {
  _known(
    'UI-01',
    'stepper zones are 61x26 (fotmob_match_card.dart:1311-1313)',
    'a score stepper zone is at least 48px tall',
    (WidgetTester tester) async {
      _phone(tester);
      await _pumpOpenMatch(tester);
      for (final String side in <String>['home', 'away']) {
        for (final String zone in <String>['increment', 'decrement']) {
          final Size size = tester.getSize(
            find.byKey(Key('currentMonthFixtures.$side.$zone.f-1')),
          );
          expect(size.height, greaterThanOrEqualTo(48), reason: '$side $zone');
        }
      }
    },
  );

  _known(
    'UI-02',
    'fixed dark text on the light gold is 2.86:1; the selected date line '
        'is 3.73:1 (fixtures_date_bar.dart:231-241, 193-194)',
    'the day strip text reaches 4.5:1 in both themes',
    (WidgetTester tester) async {
      _phone(tester);
      for (final (ThemeData theme, AppTokens t) in <(ThemeData, AppTokens)>[
        (AppTheme.dark, _dark),
        (AppTheme.light, _light),
      ]) {
        await tester.pumpWidget(
          _app(
            theme,
            Scaffold(
              body: FixturesDateStrip(
                selectedDay: DateTime.now(),
                onDaySelected: (DateTime day) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final Finder badge = find.text(_ar.fixturesDateToday);
        expect(
          _contrast(_textColor(tester, badge), _backdrop(badge, t.surface)),
          greaterThanOrEqualTo(4.5),
          reason: '${t.brightness} badge',
        );
        final Finder dateLine = find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.style?.color == t.onPrimary.withValues(alpha: 0.85),
        );
        if (dateLine.evaluate().isNotEmpty) {
          final Finder first = dateLine.first;
          final Color under = _backdrop(first, t.surface);
          expect(
            _contrast(
              Color.alphaBlend(_textColor(tester, first), under),
              under,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '${t.brightness} selected date line',
          );
        }
      }
    },
  );

  _known(
    'UI-03',
    'the active tab is primaryLight, 4.49:1 on the light bar '
        '(nukhbaa_shell.dart:283)',
    'the active tab label reaches 4.5:1 in the light theme',
    (WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          AppTheme.light,
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: NukhbaaBottomNav(
              index: 0,
              onChanged: (int index) {},
            ),
          ),
        ),
      );
      final Finder label = find.text('الرئيسية');
      final Material bar = tester.widget<Material>(
        find.ancestor(of: label, matching: find.byType(Material)).first,
      );
      final Color under = Color.alphaBlend(
        bar.color!,
        AppTheme.light.scaffoldBackgroundColor,
      );
      expect(
        _contrast(_textColor(tester, label), under),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  _known(
    'UI-04',
    'fixed 70px bar, 10px labels, no selected state for screen readers '
        '(nukhbaa_shell.dart:219-300)',
    'the bottom bar says which tab is selected and fits at x2.0',
    (WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          AppTheme.dark,
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: NukhbaaBottomNav(
              index: 0,
              onChanged: (int index) {},
            ),
          ),
          scale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('الرئيسية')).style!.fontSize,
        greaterThanOrEqualTo(12),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('nav.item.home'))),
        containsSemantics(isSelected: true, isButton: true),
      );
    },
  );

  _known(
    'UI-05',
    'white on the dark error red is 3.51:1 (home_screen.dart:479, '
        'account_screen.dart:80)',
    'the unread badge reaches 4.5:1 in both themes',
    (WidgetTester tester) async {
      _phone(tester);
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark,
        AppTheme.light,
      ]) {
        await _pumpHome(tester, theme);
        final Badge badge = tester.widget<Badge>(
          find.descendant(
            of: find.byKey(const Key('home.notifications')),
            matching: find.byType(Badge),
          ),
        );
        final Color fill =
            badge.backgroundColor ??
            theme.badgeTheme.backgroundColor ??
            theme.colorScheme.error;
        final Color label =
            badge.textColor ??
            theme.badgeTheme.textColor ??
            theme.colorScheme.onError;
        expect(
          _contrast(label, fill),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness}',
        );
      }
    },
  );

  _known(
    'UI-06',
    'the success badge is blue (4.35:1 dark, 3.61:1 light) and the danger '
        'badge is 4.37:1 / 4.28:1 (app_badge.dart:33-40)',
    'success and danger badges reach 4.5:1 and success reads as green',
    (WidgetTester tester) async {
      for (final (ThemeData theme, AppTokens t) in <(ThemeData, AppTokens)>[
        (AppTheme.dark, _dark),
        (AppTheme.light, _light),
      ]) {
        await tester.pumpWidget(
          _app(
            theme,
            Scaffold(
              body: ColoredBox(
                color: t.surface,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppBadge(label: 'نجاح', tone: AppBadgeTone.success),
                      AppBadge(label: 'خطأ', tone: AppBadgeTone.danger),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (final String label in <String>['نجاح', 'خطأ']) {
          final Finder text = find.text(label);
          expect(
            _contrast(_textColor(tester, text), _backdrop(text, t.surface)),
            greaterThanOrEqualTo(4.5),
            reason: '${t.brightness} $label',
          );
        }
        final double hue = HSLColor.fromColor(
          _textColor(tester, find.text('نجاح')),
        ).hue;
        expect(hue, inInclusiveRange(90, 180), reason: '${t.brightness} hue');
      }
    },
  );

  _known(
    'UI-07',
    'white on the gradient start #008BFF is 3.42:1 (home_screen.dart:529, '
        'app_colors.dart:130)',
    'the overview card keeps 4.5:1 for its white text over the whole '
        'gradient',
    (WidgetTester tester) async {
      _phone(tester);
      for (final (ThemeData theme, AppTokens t) in <(ThemeData, AppTokens)>[
        (AppTheme.dark, _dark),
        (AppTheme.light, _light),
      ]) {
        await _pumpHome(tester, theme);
        final Finder title = find.text('لوحة النخبة');
        await tester.ensureVisible(title);
        final Gradient? gradient = find
            .ancestor(of: title, matching: find.byType(DecoratedBox))
            .evaluate()
            .map((Element e) => (e.widget as DecoratedBox).decoration)
            .whereType<BoxDecoration>()
            .map((BoxDecoration d) => d.gradient)
            .firstWhere((Gradient? g) => g != null, orElse: () => null);
        expect(gradient, isNotNull);
        for (final Color stop in gradient!.colors) {
          expect(
            _contrast(t.onPrimary, stop),
            greaterThanOrEqualTo(4.5),
            reason: '${t.brightness} $stop',
          );
        }
      }
    },
  );

  _known(
    'UI-08',
    'the dark card is a hard-coded #2F2F2F from the retired grey palette '
        '(fotmob_match_card.dart:478)',
    'a match card sits on the theme surface',
    (WidgetTester tester) async {
      _phone(tester);
      await _pumpOpenMatch(tester);
      final Container card = tester.widget<Container>(
        find.byKey(const Key('currentMonthFixtures.fixture.f-1')),
      );
      expect((card.decoration! as BoxDecoration).color, _dark.surface);
    },
  );

  _known(
    'UI-10',
    'a crest asset has no edge, so white flag fields vanish on white cards '
        '(team_logo.dart:91-104)',
    'a crest drawn from an asset carries an edge in the light theme',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          AppTheme.light,
          const Scaffold(
            body: Center(
              child: TeamLogo(
                displayName: 'فنلندا',
                size: 34,
                assetPath: 'assets/team_logos/finland.png',
              ),
            ),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(TeamLogo),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border != null,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  _known(
    'UI-11',
    'the initial is the first character, so "ال..." names show a bare alef '
        '(user_avatar.dart:64-67)',
    'an avatar initial skips the Arabic article',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            AppTheme.dark,
            const Scaffold(
              body: Center(
                child: UserAvatar(
                  displayName: 'المستشار',
                  avatarUrl: null,
                  size: 52,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('م'), findsOneWidget);
      expect(find.text('ا'), findsNothing);
    },
  );

  _known(
    'UI-12',
    'podium heights follow position, not rank (leaderboard_board.dart:'
        '383-418)',
    'three players tied on rank 1 stand at one height',
    (WidgetTester tester) async {
      _phone(tester);
      await _pumpBoard(tester, AppTheme.dark, <BoardEntry>[
        _entry(0, 1),
        _entry(1, 1),
        _entry(2, 1),
      ]);
      final double first = tester
          .getSize(find.byKey(const Key('k.item.p-0')))
          .height;
      expect(tester.getSize(find.byKey(const Key('k.item.p-1'))).height, first);
      expect(tester.getSize(find.byKey(const Key('k.item.p-2'))).height, first);
    },
  );

  _known(
    'UI-13',
    'light silver rank 3.90:1, bronze 4.22:1, moves on the viewer row '
        '3.66:1 / 4.24:1 (leaderboard_board.dart:578-600, 848)',
    'rank pills and moves reach 4.5:1 in both themes',
    (WidgetTester tester) async {
      _phone(tester);
      for (final (ThemeData theme, AppTokens t) in <(ThemeData, AppTokens)>[
        (AppTheme.dark, _dark),
        (AppTheme.light, _light),
      ]) {
        await _pumpBoard(tester, theme, <BoardEntry>[
          _entry(0, 1),
          _entry(1, 2),
          _entry(2, 3),
          _entry(3, 4, movement: 2),
          _entry(4, 5, movement: -3),
        ], me: 'p-4');
        for (final (String id, String rank) in <(String, String)>[
          ('p-1', '2'),
          ('p-2', '3'),
        ]) {
          final Finder pill = find.descendant(
            of: find.byKey(Key('k.item.$id')),
            matching: find.text(rank),
          );
          expect(
            _contrast(_textColor(tester, pill), _backdrop(pill, t.surface)),
            greaterThanOrEqualTo(4.5),
            reason: '${t.brightness} rank $rank',
          );
        }
        final Finder move = find.descendant(
          of: find.byKey(const Key('k.movement.p-4')),
          matching: find.byType(Text),
        );
        expect(
          _contrast(_textColor(tester, move), _backdrop(move, t.surface)),
          greaterThanOrEqualTo(4.5),
          reason: '${t.brightness} move on the viewer row',
        );
      }
    },
  );

  _known(
    'UI-14',
    'the calendar button shows on the month and season boards, where it '
        'does nothing (leaderboards_screen.dart:477, 551-563)',
    'the month board shows no calendar button',
    (WidgetTester tester) async {
      _phone(tester);
      final boards.LeaderboardsHarness harness = boards
          .buildLeaderboardsHarness((http.Request request) async {
            if (request.url.path == '/seasons/s-10/fixture-leaderboard') {
              return boards.okJsonObject(
                const FixtureLeaderboardDto(
                  seasonId: 's-10',
                  entries: <FixtureLeaderboardEntryDto>[],
                ).toJson(),
              );
            }
            if (request.url.path == '/champions') {
              return boards.okJsonObject(const <String, Object?>{
                'schema_version': 1,
                'champions': <Object?>[],
              });
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
            // A fixture of the month's own season, so the board is shown.
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
          child: _app(AppTheme.dark, const LeaderboardsScreen(userId: 'u-me')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leaderboards.period')), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_rounded), findsNothing);
    },
  );

  _known(
    'UI-15',
    'the pills are 42px tall (segmented_pills.dart:41)',
    'a segmented pill is at least 48px tall',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          AppTheme.dark,
          Scaffold(
            body: Center(
              child: SegmentedPills(
                keyPrefix: 'pills',
                labels: const <String>['الشهر', 'اليوم', 'الموسم'],
                selectedIndex: 0,
                onSelected: (int index) {},
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('pills.0'))).height,
        greaterThanOrEqualTo(48),
      );
    },
  );

  _known(
    'UI-16',
    'the live chip is 32px and the double button 36px tall '
        '(live_matches_chip.dart:115, fotmob_match_card.dart:1588)',
    'the live chip and the double button are at least 48px tall',
    (WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          AppTheme.dark,
          Scaffold(
            body: Center(
              child: LiveMatchesChip(
                hasLive: true,
                selected: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const Key('currentMonthFixtures.live')))
            .height,
        greaterThanOrEqualTo(48),
      );
      await _pumpOpenMatch(tester);
      expect(
        tester
            .getSize(find.byKey(const Key('currentMonthFixtures.double.f-1')))
            .height,
        greaterThanOrEqualTo(48),
      );
    },
  );

  _known(
    'UI-17',
    'the day chips scale their text down to a fixed height, so larger '
        'system text never reaches them (fixtures_date_bar.dart:52, 219)',
    'the day strip text grows with the system text size',
    (WidgetTester tester) async {
      _phone(tester);
      Future<double> weekdayHeight(double scale) async {
        await tester.pumpWidget(
          _app(
            AppTheme.dark,
            Scaffold(
              body: FixturesDateStrip(
                selectedDay: DateTime(2026, 10, 3),
                onDaySelected: (DateTime day) {},
              ),
            ),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final Finder selected = find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.style?.color == _dark.onPrimary &&
              w.style?.fontWeight == FontWeight.w800,
        );
        return tester.getRect(selected.first).height;
      }

      final double normal = await weekdayHeight(1.0);
      final double doubled = await weekdayHeight(2.0);
      expect(doubled / normal, greaterThanOrEqualTo(1.6));
    },
  );

  _known(
    'UI-18',
    'the double label sits in a fixed 130px slot and is cut at large text '
        '(fotmob_match_card.dart:624-653)',
    'the double button label is not cut at x2.0',
    (WidgetTester tester) async {
      _phone(tester);
      await _pumpOpenMatch(tester, scale: 2.0);
      final RenderParagraph label = tester.renderObject<RenderParagraph>(
        find.text(_ar.predictionMakeItDoubleLabel),
      );
      expect(label.didExceedMaxLines, isFalse);
    },
  );

  _known(
    'UI-21',
    'the list draws a divider between cards that already carry a border '
        '(async_list_view.dart:125)',
    'my predictions separates its cards by space, not lines',
    (WidgetTester tester) async {
      _phone(tester);
      final predictions.PredictionHarness harness = predictions
          .buildPredictionHarness((http.Request request) async {
            if (request.url.path == '/me/fixture-predictions') {
              return predictions.okJsonList(<Object?>[
                const FixturePredictionDto(
                  id: 'fp-1',
                  participantId: 'part-1',
                  fixtureId: 'f-1',
                  submittedAt: '2026-10-03T06:57:00.000Z',
                  homeGoals: 1,
                  awayGoals: 1,
                ).toJson(),
                const FixturePredictionDto(
                  id: 'fp-2',
                  participantId: 'part-1',
                  fixtureId: 'f-2',
                  submittedAt: '2026-10-03T06:58:00.000Z',
                  homeGoals: 4,
                  awayGoals: 0,
                ).toJson(),
              ]);
            }
            return predictions.okJsonList(const <Object?>[]);
          });
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: _app(AppTheme.dark, const PredictionHistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history.item.fp-1')), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    },
  );

  _known(
    'UI-22',
    'the admin field outline is the hairline token, 1.24:1 on its fill in '
        'the dark theme (admin_ui_kit.dart:98-106)',
    'an admin text field outline reaches 3:1 on its fill',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark,
        AppTheme.light,
      ]) {
        await tester.pumpWidget(
          _app(
            theme,
            Scaffold(
              body: Center(
                child: AdminTextField(controller: controller, hint: 'بحث'),
              ),
            ),
          ),
        );
        final InputDecoration decoration = tester
            .widget<TextField>(find.byType(TextField))
            .decoration!;
        final Color fill =
            decoration.fillColor ?? theme.inputDecorationTheme.fillColor!;
        final Color outline =
            (decoration.enabledBorder ??
                    theme.inputDecorationTheme.enabledBorder!)
                .borderSide
                .color;
        expect(
          _contrast(Color.alphaBlend(outline, fill), fill),
          greaterThanOrEqualTo(3),
          reason: '${theme.brightness}',
        );
      }
    },
  );

  _known(
    'UI-27',
    'the account and bell buttons on home carry no tooltip '
        '(home_screen.dart:472-492)',
    'the home header buttons are named for screen readers',
    (WidgetTester tester) async {
      _phone(tester);
      await _pumpHome(tester, AppTheme.dark);
      for (final String key in <String>['home.notifications', 'home.account']) {
        expect(
          tester.widget<IconButton>(find.byKey(Key(key))).tooltip,
          isNotNull,
          reason: key,
        );
      }
    },
  );

  group(
    'UI-24',
    () {
      test('the web page lets the reader zoom and matches the app colours', () {
        final String index = File('web/index.html').readAsStringSync();
        expect(index, isNot(contains('user-scalable=no')));
        expect(index, isNot(contains('maximum-scale=1.0')));
        final Object? manifest = jsonDecode(
          File('web/manifest.json').readAsStringSync(),
        );
        expect(manifest, isA<Map<String, Object?>>());
        final Map<String, Object?> fields = manifest as Map<String, Object?>;
        expect((fields['theme_color'] as String?)?.toLowerCase(), '#071426');
      });
    },
    skip:
        'UI-24: index.html blocks pinch zoom (web/index.html:9) and the '
        'manifest colour is #0d1b2a, not the app background '
        '(web/manifest.json:6-7)',
  );
}
