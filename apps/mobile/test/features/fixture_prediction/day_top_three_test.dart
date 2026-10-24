/// The day's three most points through the real predictions board, the
/// real `GET /me`, the real day board read and a fake server (2026-10-25):
/// an admin sees a line naming the first three of the day's standings, in
/// the server's order, and the card ranks them with their points; a player
/// with no points is left out, and a player who is not an admin sees no
/// line and the day board is never asked for.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/time/riyadh_day_turnover.dart';
import 'package:mobile/features/fixture_prediction/widgets/day_top_three_card.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

String _hoursAgo(int hours) =>
    DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();

FixtureLeaderboardEntryDto _entry(
  int rank,
  String id,
  String name,
  int points,
) => FixtureLeaderboardEntryDto(
  rank: rank,
  participantId: id,
  displayName: name,
  totalPoints: points,
  fixturesScored: 5,
);

/// The server's order: Mohammed and Osama level on 15 (the tie-breaks put
/// Mohammed first), Waleed 12, Riyad 12, Zaid nothing.
final FixtureLeaderboardDto _dayBoard = FixtureLeaderboardDto(
  seasonId: 's-1',
  entries: <FixtureLeaderboardEntryDto>[
    _entry(1, 'p-moh', 'Mohammed', 15),
    _entry(2, 'p-osama', 'Osama', 15),
    _entry(3, 'p-waleed', 'Waleed', 12),
    _entry(4, 'p-riyad', 'Riyad', 12),
    _entry(5, 'p-zaid', 'Zaid', 0),
  ],
);

final class _Server {
  _Server({required this.role});

  final String role;
  final String kickoffAt = _hoursAgo(3);
  final List<Uri> dayBoardReads = <Uri>[];

  Map<String, Object?> _prediction(String id, String name) =>
      FixturePredictionDto(
        id: 'pr-$id',
        participantId: id,
        fixtureId: 'f-1',
        submittedAt: '2026-10-24T12:00:00.000Z',
        homeGoals: 1,
        awayGoals: 0,
        displayName: name,
      ).toJson();

  Future<http.Response> handle(http.Request request) async {
    switch (request.url.path) {
      case '/me':
        return okJsonObject(
          MeResponseDto(
            user: AuthenticatedUserDto(
              userId: 'u-1',
              role: role,
              status: 'active',
              displayName: 'Mohammed',
            ),
          ).toJson(),
        );
      case '/feed/current-month-fixtures':
        return okJsonList([
          CurrentMonthFixtureItemDto(
            competitionId: 'c-1',
            competitionName: 'League',
            seasonLabel: '10/2026',
            fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: 'f-1',
              homeTeam: 'Liverpool',
              awayTeam: 'Brighton',
              kickoffAt: kickoffAt,
            ),
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('p-moh', 'Mohammed')]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          for (final FixtureLeaderboardEntryDto e in _dayBoard.entries)
            _prediction(e.participantId, e.displayName),
        ]);
      case '/seasons/s-1/fixtures/f-1/reactions':
        return okJsonObject(
          const PredictionReactionsDto(
            reactions: <PredictionReactionTallyDto>[],
          ).toJson(),
        );
      case '/seasons/s-1/fixture-leaderboard':
        dayBoardReads.add(request.url);
        return okJsonObject(_dayBoard.toJson());
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildCurrentMonthFixturesHarness(server.handle);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FixturePredictionsBoardPage(kickoffAt: server.kickoffAt),
      ),
    ),
  );
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const Key _banner = Key('fixturePredictions.topThree');
const Key _card = Key('dayTopThree.card');

void main() {
  testWidgets('an admin sees the day top three, as the day board ranks them', (
    tester,
  ) async {
    final _Server server = _Server(role: 'admin');
    await _pump(tester, server);

    // The read is the "today" tab's: that Riyadh day, 00:00 to 00:00.
    final DateTime day = RiyadhDayTurnover.dayKeyOf(
      DateTime.parse(server.kickoffAt),
    );
    final DateTime opens = RiyadhDayTurnover.opensAt(day);
    expect(server.dayBoardReads, isNotEmpty);
    expect(
      DateTime.parse(server.dayBoardReads.last.queryParameters['from']!),
      opens,
    );
    expect(
      DateTime.parse(server.dayBoardReads.last.queryParameters['to']!),
      opens.add(const Duration(days: 1)),
    );

    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.text('الأكثر نقاطاً اليوم: Mohammed · Osama · Waleed'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_banner));
    await _frames(tester);
    expect(find.byKey(_card), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('dayTopThree.date'))).data,
      dayTopThreeDateLabel(day),
    );
    const Map<String, (String, String)> shown = <String, (String, String)>{
      'p-moh': ('1', '15 نقطة'),
      'p-osama': ('2', '15 نقطة'),
      'p-waleed': ('3', '12 نقطة'),
    };
    for (final MapEntry<String, (String, String)> e in shown.entries) {
      final Finder row = find.byKey(Key('dayTopThree.player.${e.key}'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(e.value.$1)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(Key('dayTopThree.points.${e.key}')))
            .data,
        e.value.$2,
      );
    }
    expect(find.byKey(const Key('dayTopThree.player.p-riyad')), findsNothing);
    expect(find.byKey(const Key('dayTopThree.player.p-zaid')), findsNothing);
    expect(find.byKey(const Key('dayTopThree.share')), findsOneWidget);
  });

  testWidgets('the line and the card hold at 360px with text x2', (
    tester,
  ) async {
    await _pump(tester, _Server(role: 'admin'), textScale: 2);
    expect(find.byKey(_banner), findsOneWidget);
    await tester.tap(find.byKey(_banner));
    await _frames(tester);
    expect(find.byKey(_card), findsOneWidget);
    expect(
      find.byKey(const Key('dayTopThree.player.p-waleed')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a player sees no top-three line, and it is never read', (
    tester,
  ) async {
    final _Server server = _Server(role: 'user');
    await _pump(tester, server);

    expect(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-osama')),
      findsOneWidget,
    );
    expect(find.byKey(_banner), findsNothing);
    expect(server.dayBoardReads, isEmpty);
  });

  test('nobody with points means no card; the share text ranks the three', () {
    final DateTime day = DateTime(2026, 10, 24);
    expect(
      dayTopThreeOf(
        FixtureLeaderboardDto(
          seasonId: 's-1',
          entries: <FixtureLeaderboardEntryDto>[_entry(1, 'p-zaid', 'Zaid', 0)],
        ),
        day: day,
        unnamed: 'لاعب',
      ),
      isNull,
    );
    expect(dayTopThreeOf(null, day: day, unnamed: 'لاعب'), isNull);

    final DayTopThree top = dayTopThreeOf(
      _dayBoard,
      day: day,
      unnamed: 'لاعب',
    )!;
    expect(dayTopThreeDateLabel(day), 'السبت 24 أكتوبر 2026');
    expect(
      dayTopThreeShareText(top),
      'الأكثر نقاطاً في النخبة · السبت 24 أكتوبر 2026\n'
      '1. Mohammed · 15 نقطة\n'
      '2. Osama · 15 نقطة\n'
      '3. Waleed · 12 نقطة',
    );
  });
}
