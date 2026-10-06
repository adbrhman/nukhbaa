/// "Which team do you support?" after a saved prediction, through the real
/// `AuthApi` and a fake server: a player with no favourite team is offered
/// the two teams of the match, and one tap stores theirs; a player who has
/// one is offered nothing; it is offered once per session.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/favorite_team_offer.dart';

import '../../support/current_month_fixtures_harness.dart';

const SeasonFixtureCardDto _fixture = SeasonFixtureCardDto(
  seasonId: 's-1',
  fixtureId: 'f-1',
  homeTeam: 'Arsenal',
  awayTeam: 'Chelsea',
  kickoffAt: '2026-10-10T14:30:00.000Z',
  homeTeamId: 't-arsenal',
  awayTeamId: 't-chelsea',
);

final class _Server {
  _Server(this.teams);

  List<String> teams;
  final List<List<String>> puts = <List<String>>[];
  int gets = 0;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/me/favorite-teams') {
      if (request.method == 'PUT') {
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        teams = <String>[
          for (final Object? id in body['team_ids']! as List<Object?>)
            id! as String,
        ];
        puts.add(teams);
      } else {
        gets++;
      }
      return okJsonObject(FavoriteTeamsDto(teamIds: teams).toJson());
    }
    return http.Response('not found', 404);
  }
}

Future<_Server> _pump(WidgetTester tester, List<String> teams) async {
  final _Server server = _Server(teams);
  final harness = buildCurrentMonthFixturesHarness(server.handle);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              key: const Key('save'),
              onPressed: () => offerFavoriteTeamAfterSave(
                context: context,
                ref: ref,
                fixture: _fixture,
              ),
              child: const Text('save'),
            ),
          ),
        ),
      ),
    ),
  );
  return server;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('no favourite yet: the two teams, and one tap stores one', (
    tester,
  ) async {
    final _Server server = await _pump(tester, const <String>[]);

    await tester.tap(find.byKey(const Key('save')));
    await _settle(tester);
    expect(find.byKey(const Key('favoriteOffer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('favoriteOffer.away')));
    await _settle(tester);

    expect(server.puts, <List<String>>[
      <String>['t-chelsea'],
    ]);
    expect(find.byKey(const Key('favoriteOffer.done')), findsOneWidget);
  });

  testWidgets('a player with a favourite is offered nothing', (tester) async {
    await _pump(tester, const <String>['t-arsenal']);

    await tester.tap(find.byKey(const Key('save')));
    await _settle(tester);

    expect(find.byKey(const Key('favoriteOffer')), findsNothing);
  });

  testWidgets('it is offered once per session', (tester) async {
    final _Server server = await _pump(tester, const <String>[]);

    await tester.tap(find.byKey(const Key('save')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('save')), warnIfMissed: false);
    await _settle(tester);

    expect(server.gets, 1);
  });
}
