/// The friends' league tab through the real board, the real `GroupsApi`
/// and a fake server: with a league it shows the league's month board as
/// the server ranked it; before any league it names the players the viewer
/// duels most and opens league creation; the shared invitation carries a
/// one-tap link.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/groups/create_group_screen.dart';
import 'package:mobile/features/groups/league_invite.dart';
import 'package:mobile/features/leaderboards/widgets/friends_league_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const GroupDto _league = GroupDto(
  id: 'g-1',
  name: 'Office',
  ownerId: 'u-1',
  inviteCode: 'ABCD23EFGH',
  createdAt: '2026-10-01T00:00:00.000Z',
  memberCount: 4,
);

DuelSummaryDto _duel(String id, String opponentId, String name) =>
    DuelSummaryDto(
      id: id,
      challengeId: 'c-$id',
      fixtureId: 'f-$id',
      homeTeam: 'Arsenal',
      awayTeam: 'Chelsea',
      kickoffAt: '2026-10-05T18:00:00.000Z',
      acceptedAt: '2026-10-05T12:00:00.000Z',
      isChallenger: true,
      opponentUserId: opponentId,
      opponentName: name,
      myIsDouble: false,
      state: 'settled',
    );

final class _Server {
  _Server({required this.inLeague});

  final bool inLeague;
  final List<String> paths = <String>[];

  Future<http.Response> handle(http.Request request) async {
    paths.add(request.url.path);
    switch (request.url.path) {
      case '/me/groups':
        return okJsonObject(
          MyGroupsDto(
            groups: <MyGroupEntryDto>[
              if (inLeague)
                const MyGroupEntryDto(
                  group: _league,
                  role: 'owner',
                  joinedAt: '2026-10-01T00:00:00.000Z',
                ),
            ],
          ).toJson(),
        );
      case '/groups/g-1/seasons/s-1/month-board':
        return okJsonObject(
          const FixtureLeaderboardDto(
            seasonId: 's-1',
            entries: <FixtureLeaderboardEntryDto>[
              FixtureLeaderboardEntryDto(
                rank: 1,
                participantId: 'p-friend',
                displayName: 'Friend',
                totalPoints: 9,
                fixturesScored: 4,
              ),
              FixtureLeaderboardEntryDto(
                rank: 2,
                participantId: 'p-me',
                displayName: 'Me',
                totalPoints: 6,
                fixturesScored: 4,
              ),
            ],
          ).toJson(),
        );
      case '/me/duels':
        return okJsonObject(
          MyDuelsDto(
            challenges: const <DuelChallengeDto>[],
            duels: <DuelSummaryDto>[
              _duel('1', 'u-sara', 'Sara'),
              _duel('2', 'u-khaled', 'Khaled'),
              _duel('3', 'u-khaled', 'Khaled'),
            ],
          ).toJson(),
        );
      case '/me/fixture-predictions':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<_Server> _pump(WidgetTester tester, {required bool inLeague}) async {
  final _Server server = _Server(inLeague: inLeague);
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
        home: const Scaffold(
          body: FriendsLeagueBoard(seasonId: 's-1', keyPrefix: 'friends'),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  return server;
}

void main() {
  testWidgets('a league shows its month board as the server ranked it', (
    tester,
  ) async {
    final _Server server = await _pump(tester, inLeague: true);

    expect(server.paths, contains('/groups/g-1/seasons/s-1/month-board'));
    expect(find.byKey(const Key('friends.item.p-friend')), findsOneWidget);
    expect(find.byKey(const Key('friends.item.p-me')), findsOneWidget);
    expect(find.byKey(const Key('friends.invite')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('friends.name'))).data,
      contains('Office'),
    );
  });

  testWidgets('before any league it names the players duelled most', (
    tester,
  ) async {
    await _pump(tester, inLeague: false);

    expect(
      tester.widget<Text>(find.byKey(const Key('friends.rivals'))).data,
      contains('Khaled، Sara'),
    );

    await tester.tap(find.byKey(const Key('friends.start.create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CreateGroupScreen), findsOneWidget);
  });

  test('the invitation carries a one-tap league link and the code', () {
    final String text = leagueShareText(_league);

    expect(text, contains('?league=ABCD23EFGH'));
    expect(text, contains('Office'));
  });
}
