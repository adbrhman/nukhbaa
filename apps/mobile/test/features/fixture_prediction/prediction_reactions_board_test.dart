/// Reactions on the predictions board (migration 0094) through the real
/// board, the real `PredictionApi` and a fake server: a cell shows what its
/// prediction received; tapping another player's cell reacts, and tapping
/// the same reaction again takes it back; the viewer's own cell shows its
/// reactions and gives none; an inbox row about a reaction opens the board.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const String _reactPath =
    '/seasons/s-1/fixtures/f-1/predictions/p-khaled/reaction';

String _minutesAgo(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

Map<String, Object?> _prediction(String participantId, String name) =>
    FixturePredictionDto(
      id: 'pr-$participantId',
      participantId: participantId,
      fixtureId: 'f-1',
      submittedAt: '2026-10-06T12:00:00.000Z',
      homeGoals: 2,
      awayGoals: 1,
      isDouble: false,
      displayName: name,
    ).toJson();

/// A started match with two predictions; khaled's has two fires, one of
/// them the viewer's once [mine] is set.
final class _Server {
  _Server({required this.kickoffAt});

  final String kickoffAt;
  final List<http.Request> requests = <http.Request>[];
  String? mine;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == _reactPath && request.method == 'PUT') {
      mine =
          (jsonDecode(request.body) as Map<String, Object?>)['emoji']
              as String?;
      return okJsonObject(const {'reacted': true, 'first': true});
    }
    if (path == _reactPath && request.method == 'DELETE') {
      mine = null;
      return okJsonObject(const {'removed': true});
    }
    switch (path) {
      case '/feed/current-month-fixtures':
        return okJsonList([
          CurrentMonthFixtureItemDto(
            competitionId: 'c-1',
            competitionName: 'League',
            seasonLabel: '10/2026',
            fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: 'f-1',
              homeTeam: 'Arsenal',
              awayTeam: 'Chelsea',
              kickoffAt: kickoffAt,
            ),
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('p-me', 'Ahmad')]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          _prediction('p-me', 'Ahmad'),
          _prediction('p-khaled', 'Khaled'),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          const FixtureScoresDto(
            fixtureId: 'f-1',
            scores: <ParticipantFixtureScoreDto>[],
          ).toJson(),
        );
      case '/seasons/s-1/fixtures/f-1/reactions':
        return okJsonObject(
          PredictionReactionsDto(
            reactions: <PredictionReactionTallyDto>[
              PredictionReactionTallyDto(
                participantId: 'p-khaled',
                counts: <String, int>{'fire': mine == 'fire' ? 2 : 1},
                mine: mine,
              ),
              const PredictionReactionTallyDto(
                participantId: 'p-me',
                counts: <String, int>{'clap': 3},
              ),
            ],
          ).toJson(),
        );
      case '/teams':
        return okJsonList(const []);
      case '/notifications':
        return okJsonObject(const {
          'schema_version': 2,
          'recipient_id': 'u-1',
          'unread_count': 0,
          'notifications': [
            {
              'schema_version': 2,
              'id': 'n1',
              'recipient_id': 'u-1',
              'kind': 'prediction_reaction',
              'read': true,
              'created_at': '2026-10-06T19:00:00Z',
              'actor_user_id': 'u-2',
              'fixture_id': 'f-1',
            },
          ],
        });
    }
    return http.Response('not found', 404);
  }

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).length;
}

Future<_Server> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final _Server server = _Server(kickoffAt: _minutesAgo(10));
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
        home: home,
      ),
    ),
  );
  await _frames(tester);
  return server;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Widget _board(String kickoffAt) =>
    FixturePredictionsBoardPage(kickoffAt: kickoffAt);

void main() {
  testWidgets('a cell shows what its prediction received', (tester) async {
    await _pump(tester, _board(_minutesAgo(10)));

    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.reactions.f-1.p-khaled')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.reactions.f-1.p-me')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('another player cell reacts, and the same reaction undoes it', (
    tester,
  ) async {
    final _Server server = await _pump(tester, _board(_minutesAgo(10)));

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-khaled')),
    );
    await _frames(tester);
    expect(find.byKey(const Key('reactionSheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reactionSheet.kind.fire')));
    await _frames(tester);
    expect(server.count('PUT', _reactPath), 1);
    expect(server.mine, 'fire');
    expect(find.byKey(const Key('reactionSheet')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.reactions.f-1.p-khaled')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-khaled')),
    );
    await _frames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('reactionSheet.count.fire')))
          .data,
      '2',
    );
    await tester.tap(find.byKey(const Key('reactionSheet.kind.fire')));
    await _frames(tester);
    expect(server.count('DELETE', _reactPath), 1);
    expect(server.mine, isNull);
    expect(find.byKey(const Key('reactionSheet')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.reactions.f-1.p-khaled')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('my own cell shows its reactions and gives none', (tester) async {
    final _Server server = await _pump(tester, _board(_minutesAgo(10)));

    await tester.tap(find.byKey(const Key('fixturePredictions.cell.f-1.p-me')));
    await _frames(tester);
    expect(find.byKey(const Key('reactionSheet')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('reactionSheet.count.clap')))
          .data,
      '3',
    );

    await tester.tap(find.byKey(const Key('reactionSheet.kind.fire')));
    await _frames(tester);
    expect(
      server.requests.where((r) => r.url.path.endsWith('/reaction')),
      isEmpty,
    );
  });

  testWidgets('each kind keeps its own colour, on the board and the sheet', (
    tester,
  ) async {
    const AppTokens tokens = AppTokens.dark;
    Color? iconColor(Finder of) => tester
        .widget<Icon>(find.descendant(of: of, matching: find.byType(Icon)))
        .color;

    await _pump(tester, _board(_minutesAgo(10)));
    expect(
      iconColor(
        find.byKey(const Key('fixturePredictions.reactions.f-1.p-khaled')),
      ),
      tokens.bronze,
    );
    expect(
      iconColor(find.byKey(const Key('fixturePredictions.reactions.f-1.p-me'))),
      tokens.successText,
    );

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-khaled')),
    );
    await _frames(tester);
    expect(
      iconColor(find.byKey(const Key('reactionSheet.kind.like'))),
      tokens.primaryText,
    );
    expect(
      iconColor(find.byKey(const Key('reactionSheet.kind.sad'))),
      tokens.silver,
    );
    expect(
      iconColor(find.byKey(const Key('reactionSheet.kind.shock'))),
      tokens.errorText,
    );
  });

  testWidgets('an inbox row about a reaction opens the board', (tester) async {
    await _pump(tester, const NotificationsScreen());

    await tester.tap(find.byKey(const Key('notifications.item.n1')));
    await _frames(tester);

    expect(find.byType(FixturePredictionsBoardPage), findsOneWidget);
  });
}
