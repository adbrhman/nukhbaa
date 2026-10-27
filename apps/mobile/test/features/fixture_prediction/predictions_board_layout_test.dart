/// The predictions board's layout through the real page, the real `GET /me`
/// and a fake server (batch 157): an admin's day of five matches whose
/// doubles paid makes five cards, which fold into one line that opens them
/// (most players first); the match headers stay pinned on top while forty
/// players scroll under them, and follow the columns sideways.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

String _hoursAgo(int hours) =>
    DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();

const List<String> _fixtures = <String>['f-1', 'f-2', 'f-3', 'f-4', 'f-5'];
const int _playerCount = 40;

/// Players p-0 and p-1 doubled the exact score of every match (6 each);
/// on f-3, p-2 did too. Everyone else called it wrong.
int _doublers(String fixtureId) => fixtureId == 'f-3' ? 3 : 2;

Map<String, Object?> _prediction(String fixtureId, int i) =>
    FixturePredictionDto(
      id: 'pr-$fixtureId-$i',
      participantId: 'p-$i',
      fixtureId: fixtureId,
      submittedAt: '2026-10-27T12:00:00.000Z',
      homeGoals: i < _doublers(fixtureId) ? 2 : 0,
      awayGoals: 1,
      isDouble: i < _doublers(fixtureId),
      displayName: 'Player $i',
    ).toJson();

final class _Server {
  final String kickoffAt = _hoursAgo(3);

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    final RegExpMatch? fixture = RegExp(
      r'^/seasons/s-1/fixtures/([^/]+)/(predictions|scores|reactions)$',
    ).firstMatch(path);
    if (fixture != null) {
      final String id = fixture.group(1)!;
      switch (fixture.group(2)) {
        case 'predictions':
          return okJsonList([
            for (int i = 0; i < _playerCount; i++) _prediction(id, i),
          ]);
        case 'scores':
          return okJsonObject(
            FixtureScoresDto(
              fixtureId: id,
              scores: <ParticipantFixtureScoreDto>[
                for (int i = 0; i < _playerCount; i++)
                  ParticipantFixtureScoreDto(
                    fixtureId: id,
                    participantId: 'p-$i',
                    rulesetVersion: 3,
                    grade: i < _doublers(id) ? 'exact_scoreline' : 'incorrect',
                    points: i < _doublers(id) ? 6 : 0,
                  ),
              ],
            ).toJson(),
          );
        case 'reactions':
          return okJsonObject(
            const PredictionReactionsDto(
              reactions: <PredictionReactionTallyDto>[],
            ).toJson(),
          );
      }
    }
    switch (path) {
      case '/me':
        return okJsonObject(
          const MeResponseDto(
            user: AuthenticatedUserDto(
              userId: 'u-1',
              role: 'admin',
              status: 'active',
              displayName: 'Player 0',
            ),
          ).toJson(),
        );
      case '/feed/current-month-fixtures':
        return okJsonList([
          for (int i = 0; i < _fixtures.length; i++)
            CurrentMonthFixtureItemDto(
              competitionId: 'c-1',
              competitionName: 'League',
              seasonLabel: '10/2026',
              fixture: SeasonFixtureCardDto(
                seasonId: 's-1',
                fixtureId: _fixtures[i],
                homeTeam: 'Home ${i + 1}',
                awayTeam: 'Away ${i + 1}',
                kickoffAt: kickoffAt,
              ),
            ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('f-1', 0)]);
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(WidgetTester tester) async {
  // A 360 x 800 phone.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final _Server server = _Server();
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

const Key _toggle = Key('fixturePredictions.cards.toggle');
const Key _scroll = Key('fixturePredictions.scroll');
Key _doubles(String fixtureId) => Key('fixturePredictions.doubles.$fixtureId');
Key _header(String fixtureId) => Key('fixturePredictions.header.$fixtureId');

void main() {
  testWidgets('five cards fold into one line that opens them, most first', (
    tester,
  ) async {
    await _pump(tester);

    // The table is there: the first and the last player's cells are built.
    expect(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('fixturePredictions.cell.f-5.p-39')),
      findsOneWidget,
    );

    expect(
      find.descendant(
        of: find.byKey(_toggle),
        matching: find.text('بطاقات اليوم (5): مضاعفات ناجحة 5'),
      ),
      findsOneWidget,
    );
    for (final String id in _fixtures) {
      expect(find.byKey(_doubles(id)), findsNothing);
    }

    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    for (final String id in _fixtures) {
      expect(find.byKey(_doubles(id)), findsOneWidget);
    }
    // f-3's three doubles first, then kickoff order.
    final List<double> tops = <double>[
      for (final String id in <String>['f-3', 'f-1', 'f-2', 'f-4', 'f-5'])
        tester.getTopLeft(find.byKey(_doubles(id))).dy,
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));

    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    for (final String id in _fixtures) {
      expect(find.byKey(_doubles(id)), findsNothing);
    }
  });

  testWidgets('the match headers stay on top while the players scroll', (
    tester,
  ) async {
    await _pump(tester);

    final double scrollTop = tester.getTopLeft(find.byKey(_scroll)).dy;
    final Finder firstRow = find.byKey(const Key('fixturePredictions.row.p-0'));
    final Finder lastRow = find.byKey(const Key('fixturePredictions.row.p-39'));
    expect(firstRow.hitTestable(), findsOneWidget);
    expect(lastRow.hitTestable(), findsNothing);

    await tester.drag(find.byKey(_scroll), const Offset(0, -3000));
    await tester.pumpAndSettle();

    // The last player is on screen, the first scrolled away, and the
    // headers are still there, at the top of the table.
    expect(lastRow.hitTestable(), findsOneWidget);
    expect(firstRow.hitTestable(), findsNothing);
    expect(find.byKey(_header('f-1')).hitTestable(), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const Key('fixturePredictions.pinnedHeaders')))
          .dy,
      moreOrLessEquals(scrollTop),
    );
    // A pinned header covers the rows under it: a tap there reaches the
    // header, never a cell scrolled beneath it.
    expect(
      tester.getBottomLeft(find.byKey(_header('f-1'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(lastRow).dy),
    );
  });

  testWidgets('the headers follow the columns sideways, both ways', (
    tester,
  ) async {
    await _pump(tester);

    double headerX(String id) => tester.getCenter(find.byKey(_header(id))).dx;
    double cellX(String id) =>
        tester.getCenter(find.byKey(Key('fixturePredictions.cell.$id.p-0'))).dx;

    final double before = headerX('f-1');
    expect(cellX('f-1'), moreOrLessEquals(before));

    // The columns scroll under the finger; the headers follow.
    // (Dragged from a cell on screen: the columns' own middle lies below
    // the screen, under forty rows.)
    await tester.drag(
      find.byKey(const Key('fixturePredictions.cell.f-2.p-0')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(headerX('f-1'), isNot(moreOrLessEquals(before)));
    for (final String id in _fixtures) {
      expect(headerX(id), moreOrLessEquals(cellX(id)));
    }

    // The headers scroll back under the finger; the columns follow.
    await tester.drag(
      find.byKey(const Key('fixturePredictions.headers')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    expect(headerX('f-1'), moreOrLessEquals(before));
    for (final String id in _fixtures) {
      expect(headerX(id), moreOrLessEquals(cellX(id)));
    }
  });
}
