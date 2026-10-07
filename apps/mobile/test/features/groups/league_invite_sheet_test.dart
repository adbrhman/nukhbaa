/// Inviting to a friends' league by name, through the real league board,
/// the real invitation sheet, the real `GroupsApi` and `DuelsApi` and a
/// fake server: "invite" offers the link and a search; a player found by
/// name is invited once and marked sent; a player already in the league is
/// marked so.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/leaderboards/widgets/friends_league_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const GroupDto _league = GroupDto(
  id: 'g-1',
  name: 'Office',
  ownerId: 'u-1',
  inviteCode: 'ABCD23EFGH',
  createdAt: '2026-10-01T00:00:00.000Z',
  memberCount: 2,
);

final class _Server {
  final List<Map<String, Object?>> invites = <Map<String, Object?>>[];

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/groups/g-1/invitations' && request.method == 'POST') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      invites.add(body);
      if (body['user_id'] == 'u-member') {
        return http.Response(
          jsonEncode(const <String, Object?>{
            'schema_version': 1,
            'code': 'group.already_member',
            'message': 'already',
          }),
          409,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okJsonObject(const <String, Object?>{'invited': true});
    }
    switch (path) {
      case '/duels/players':
        return okJsonObject(
          const DuelPlayersDto(
            players: <DuelPlayerDto>[
              DuelPlayerDto(userId: 'u-khaled', displayName: 'Khaled'),
              DuelPlayerDto(userId: 'u-member', displayName: 'Khalid'),
            ],
          ).toJson(),
        );
      case '/me/groups':
        return okJsonObject(
          const MyGroupsDto(
            groups: <MyGroupEntryDto>[
              MyGroupEntryDto(
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
            entries: <FixtureLeaderboardEntryDto>[],
          ).toJson(),
        );
      case '/me/duels':
        return okJsonObject(
          const MyDuelsDto(
            challenges: <DuelChallengeDto>[],
            duels: <DuelSummaryDto>[],
          ).toJson(),
        );
      case '/me/fixture-predictions':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('a player found by name is invited once and marked sent', (
    tester,
  ) async {
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
          home: const Scaffold(
            body: FriendsLeagueBoard(seasonId: 's-1', keyPrefix: 'friends'),
          ),
        ),
      ),
    );
    await _frames(tester);

    await tester.tap(find.byKey(const Key('friends.invite')));
    await _frames(tester);
    expect(find.byKey(const Key('leagueInvite.share')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('leagueInvite.search')), 'Kha');
    await _frames(tester);
    expect(
      find.byKey(const Key('leagueInvite.player.u-khaled')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('leagueInvite.invite.u-khaled')));
    await _frames(tester);
    expect(server.invites, <Map<String, Object?>>[
      <String, Object?>{'user_id': 'u-khaled'},
    ]);
    expect(find.byKey(const Key('leagueInvite.sent.u-khaled')), findsOneWidget);
    expect(find.byKey(const Key('leagueInvite.invite.u-khaled')), findsNothing);

    await tester.tap(find.byKey(const Key('leagueInvite.invite.u-member')));
    await _frames(tester);
    expect(
      find.byKey(const Key('leagueInvite.member.u-member')),
      findsOneWidget,
    );
  });
}
