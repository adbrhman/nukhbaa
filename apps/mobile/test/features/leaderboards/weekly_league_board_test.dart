/// Widget tests for [WeeklyLeagueBoard] over the real [AuthApi] and the real
/// [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). The board is driven exactly as production drives it: it
/// asks `GET /me/weekly-league` through `myWeeklyLeagueProvider` and draws
/// what came back, so a board that stopped asking, asked the wrong path, or
/// re-decided the server's zones fails here.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/leaderboards/widgets/weekly_league_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _p = 'wl';

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _entry(
  int rank,
  String userId,
  String name,
  int points,
  String outcome, {
  bool me = false,
  int exact = 0,
  int decided = 0,
}) => <String, Object?>{
  'rank': rank,
  'user_id': userId,
  'display_name': name,
  'avatar_url': null,
  'points': points,
  'exact_count': exact,
  'decided_count': decided,
  'projected_outcome': outcome,
  'is_me': me,
};

Map<String, Object?> _league({
  required int tier,
  required int up,
  required int down,
  required List<Map<String, Object?>> entries,
}) => <String, Object?>{
  'schema_version': 1,
  'week_start': '2026-09-21',
  'week_end': '2026-09-27',
  'tier': tier,
  'group_index': 1,
  'my_rank': 4,
  'promotion_zone': up,
  'relegation_zone': down,
  'entries': entries,
};

/// A silver group of five: one goes up, one goes down, one has no profile.
final Map<String, Object?> _silver = _league(
  tier: 2,
  up: 1,
  down: 1,
  entries: <Map<String, Object?>>[
    _entry(1, 'u-a', 'Ali', 9, 'promoted', exact: 1, decided: 3),
    _entry(2, 'u-b', '', 7, 'held', decided: 3),
    _entry(3, 'u-c', 'Sara', 5, 'held', decided: 2),
    _entry(4, 'u-me', 'Me', 3, 'held', me: true, decided: 2),
    _entry(5, 'u-e', 'Omar', 0, 'relegated'),
  ],
);

Future<http.Response> Function(http.Request) _serve(Map<String, Object?> body) {
  return (http.Request request) async {
    if (request.url.path == '/me/weekly-league') return _okJson(body);
    return http.Response('not found', 404);
  };
}

Future<void> _pump(WidgetTester tester, AuthHarness harness) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: WeeklyLeagueBoard(keyPrefix: _p, showHeader: true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('draws the tier, the group, both zones and every outcome', (
    tester,
  ) async {
    final harness = buildAuthHarness(_serve(_silver), seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(
      harness.captured.map((c) => c.request.url.path),
      contains('/me/weekly-league'),
    );
    expect(_textOf(tester, '$_p.tier'), ar.weeklyLeagueTierSilver);
    expect(_textOf(tester, '$_p.group'), ar.weeklyLeagueGroup(2));
    expect(_textOf(tester, '$_p.zone.up'), ar.weeklyLeaguePromotionZone(1));
    expect(_textOf(tester, '$_p.zone.down'), ar.weeklyLeagueRelegationZone(1));

    // The server's outcome, not a rank the client re-read.
    expect(find.byKey(const Key('$_p.outcome.u-a.promoted')), findsOneWidget);
    expect(find.byKey(const Key('$_p.outcome.u-c.held')), findsOneWidget);
    expect(find.byKey(const Key('$_p.outcome.u-e.relegated')), findsOneWidget);
    expect(find.byTooltip(ar.weeklyLeagueOutcomePromoted), findsOneWidget);
    expect(find.byTooltip(ar.weeklyLeagueOutcomeRelegated), findsOneWidget);

    // A member without a profile gets the neutral name, never a blank.
    expect(
      _textOf(tester, '$_p.participant.u-b'),
      ar.weeklyLeagueUnnamedMember,
    );
    expect(_textOf(tester, '$_p.participant.u-e'), 'Omar');
  });

  testWidgets('the bottom rung shows no relegation zone', (tester) async {
    final harness = buildAuthHarness(
      _serve(
        _league(
          tier: 1,
          up: 1,
          down: 0,
          entries: <Map<String, Object?>>[
            _entry(1, 'u-a', 'Ali', 4, 'promoted', decided: 1),
            _entry(2, 'u-me', 'Me', 0, 'held', me: true),
            _entry(3, 'u-c', 'Sara', 0, 'held'),
            _entry(4, 'u-d', 'Omar', 0, 'held'),
          ],
        ),
      ),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(_textOf(tester, '$_p.tier'), ar.weeklyLeagueTierBronze);
    expect(find.byKey(const Key('$_p.zone.up')), findsOneWidget);
    expect(find.byKey(const Key('$_p.zone.down')), findsNothing);
    expect(find.byTooltip(ar.weeklyLeagueOutcomeRelegated), findsNothing);
  });

  testWidgets('a failed read offers a retry that asks the server again', (
    tester,
  ) async {
    var calls = 0;
    final harness = buildAuthHarness((request) async {
      if (request.url.path != '/me/weekly-league') {
        return http.Response('not found', 404);
      }
      calls += 1;
      if (calls == 1) {
        return errorEnvelope(503, 'server.unavailable', 'try later');
      }
      return _okJson(_silver);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(find.byKey(const Key('browse.error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('browse.error.retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(_textOf(tester, '$_p.tier'), ar.weeklyLeagueTierSilver);
  });

  testWidgets('the overtaken card names who passed the reader', (tester) async {
    final harness = buildAuthHarness(
      _serve(<String, Object?>{..._silver, 'overtaken_by': 'Ali'}),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(_textOf(tester, '$_p.overtaken'), ar.weeklyLeagueOvertakenBy('Ali'));
  });

  testWidgets('no pass, no card', (tester) async {
    final harness = buildAuthHarness(_serve(_silver), seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(find.byKey(const Key('$_p.overtaken')), findsNothing);
  });

  testWidgets('a group with no lines says so instead of an empty table', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      _serve(
        _league(tier: 1, up: 0, down: 0, entries: <Map<String, Object?>>[]),
      ),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(_textOf(tester, '$_p.empty'), ar.weeklyLeagueEmpty);
  });

  test('the period is the server week, formatted and never shifted', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    final MyWeeklyLeagueDto league = MyWeeklyLeagueDto.fromJson(_silver);

    expect(
      weeklyLeaguePeriodLabel(en, league, 'en'),
      en.weeklyLeaguePeriod('21 September', '27 September'),
    );

    final MyWeeklyLeagueDto odd = MyWeeklyLeagueDto.fromJson(<String, Object?>{
      ..._silver,
      'week_start': 'soon',
    });
    expect(
      weeklyLeaguePeriodLabel(en, odd, 'en'),
      en.weeklyLeaguePeriod('soon', '27 September'),
    );
  });

  test('every rung has its own name', () {
    final Set<String> names = <String>{
      for (int tier = 1; tier <= 5; tier++) weeklyLeagueTierName(ar, tier),
    };
    expect(names, hasLength(5));
    expect(weeklyLeagueTierName(ar, 5), ar.weeklyLeagueTierElite);
    expect(weeklyLeagueTierName(ar, 9), ar.weeklyLeagueTierElite);
  });
}
