/// Script 226: the report / block menu on the other places a player's name
/// is shown (the reaction sheet of the predictions board, the members of a
/// league), and the conduct rules the report and block stand on.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/rules_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/prediction_reaction_sheet.dart';
import 'package:mobile/features/groups/group_members_screen.dart';
import 'package:mobile/features/moderation/blocked_players.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show AuthHarness, buildAuthHarness;
import '../../support/current_month_fixtures_harness.dart'
    show buildCurrentMonthFixturesHarness, okJsonObject;

const GroupDto _league = GroupDto(
  id: 'g-1',
  name: 'Office',
  ownerId: 'u-owner',
  inviteCode: 'ABCD23EFGH',
  createdAt: '2026-10-01T00:00:00.000Z',
  memberCount: 2,
);

Future<http.Response> _membersServer(http.Request request) async {
  switch (request.url.path) {
    case '/groups/g-1/members':
      return okJsonObject(
        const GroupMembersDto(
          groupId: 'g-1',
          members: <GroupMembershipDto>[
            GroupMembershipDto(
              id: 'm-1',
              groupId: 'g-1',
              userId: 'u-owner',
              role: 'owner',
              joinedAt: '2026-10-01T00:00:00.000Z',
              displayName: 'Owner',
            ),
            GroupMembershipDto(
              id: 'm-2',
              groupId: 'g-1',
              userId: 'u-sara',
              role: 'member',
              joinedAt: '2026-10-02T00:00:00.000Z',
              displayName: 'Sara',
            ),
          ],
        ).toJson(),
      );
    case '/me/groups':
      return okJsonObject(
        const MyGroupsDto(groups: <MyGroupEntryDto>[]).toJson(),
      );
  }
  return http.Response('not found', 404);
}

Future<void> _pumpMembers(
  WidgetTester tester,
  InMemoryBlockedPlayersStore store,
) async {
  final harness = buildCurrentMonthFixturesHarness(_membersServer);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        blockedPlayersStoreProvider.overrideWithValue(store),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: GroupMembersScreen(group: _league, isOwner: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required bool isMine,
  required InMemoryBlockedPlayersStore store,
}) async {
  final AuthHarness harness = buildAuthHarness(
    (http.Request request) async => http.Response('not found', 404),
    seedToken: 'jwt',
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        blockedPlayersStoreProvider.overrideWithValue(store),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PredictionReactionSheet(
              seasonId: 's-1',
              fixtureId: 'f-1',
              participantId: 'p-1',
              playerName: isMine ? 'Me' : 'Khaled Saleh',
              homeName: 'Arsenal',
              awayName: 'Chelsea',
              homeGoals: 2,
              awayGoals: 1,
              isMine: isMine,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the members of a league are listed with the menu', (
    tester,
  ) async {
    await _pumpMembers(tester, InMemoryBlockedPlayersStore());

    expect(find.text('Sara'), findsOneWidget);
    expect(find.byKey(const Key('player.menu.u-sara')), findsOneWidget);
  });

  testWidgets('a blocked member is hidden by name in the league', (
    tester,
  ) async {
    await _pumpMembers(
      tester,
      InMemoryBlockedPlayersStore(<String, String>{'sara': 'Sara'}),
    );

    expect(find.text('Sara'), findsNothing);
    expect(find.text(blockedPlayerLabel), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
  });

  testWidgets('another player\'s reaction sheet carries the menu', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      isMine: false,
      store: InMemoryBlockedPlayersStore(),
    );

    expect(find.byKey(const Key('player.menu.p-1')), findsOneWidget);
  });

  testWidgets('the viewer\'s own reaction sheet has no menu', (tester) async {
    await _pumpSheet(
      tester,
      isMine: true,
      store: InMemoryBlockedPlayersStore(),
    );

    expect(find.byKey(const Key('player.menu.p-1')), findsNothing);
  });

  testWidgets('the rules page forbids objectionable content and says how to '
      'report it', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const RulesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rules.conduct.title')), findsOneWidget);
    expect(find.byKey(const Key('rules.conduct.name')), findsOneWidget);
    expect(find.byKey(const Key('rules.conduct.picture')), findsOneWidget);
    expect(find.byKey(const Key('rules.conduct.abuse')), findsOneWidget);
    expect(find.byKey(const Key('rules.conduct.action')), findsOneWidget);
    expect(find.byKey(const Key('rules.conduct.report')), findsOneWidget);
  });
}
