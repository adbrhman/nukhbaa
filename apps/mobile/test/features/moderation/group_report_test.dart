/// Script 253 (Play release audit F5): a member reports a friends' league
/// by its name from the league's members screen, through the real screen,
/// the real `SupportApi` and a faked socket. The report reaches the
/// support chat with the name, the league's id and the reason; the owner
/// of the league has no such button.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/groups/group_members_screen.dart';
import 'package:mobile/features/moderation/blocked_players.dart';
import 'package:mobile/features/moderation/group_report.dart';
import 'package:mobile/features/moderation/player_actions.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart'
    show buildCurrentMonthFixturesHarness, okJsonObject;
import '../support/support_fake_server.dart';

const GroupDto _league = GroupDto(
  id: 'g-253',
  name: 'Office League',
  ownerId: 'u-owner',
  inviteCode: 'ABCD23EFGH',
  createdAt: '2026-10-01T00:00:00.000Z',
  memberCount: 2,
);

/// The league's members, and the support chat for everything else.
http.Response? _members(http.Request request) {
  switch (request.url.path) {
    case '/groups/g-253/members':
      return okJsonObject(
        const GroupMembersDto(
          groupId: 'g-253',
          members: <GroupMembershipDto>[
            GroupMembershipDto(
              id: 'm-1',
              groupId: 'g-253',
              userId: 'u-owner',
              role: 'owner',
              joinedAt: '2026-10-01T00:00:00.000Z',
              displayName: 'Owner',
            ),
            GroupMembershipDto(
              id: 'm-2',
              groupId: 'g-253',
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
  return null;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool isOwner,
  required FakeSupportServer support,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildCurrentMonthFixturesHarness(
    (http.Request request) async =>
        _members(request) ?? await support.handle(request),
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        blockedPlayersStoreProvider.overrideWithValue(
          InMemoryBlockedPlayersStore(),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: GroupMembersScreen(group: _league, isOwner: isOwner),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  test('the report says which league, its id and why', () {
    final String text = groupReportMessage(
      groupName: 'Office League',
      groupId: 'g-253',
      reason: groupReportReasons.first,
    );

    expect(text, startsWith('بلاغ عن اسم دوري'));
    expect(text, contains('الاسم: Office League'));
    expect(text, contains('المعرّف: g-253'));
    expect(text, contains(groupReportReasons.first));
  });

  testWidgets('a member reports the league name to the support chat', (
    tester,
  ) async {
    final FakeSupportServer support = FakeSupportServer();
    await _pump(tester, isOwner: false, support: support);

    await _tap(tester, 'groupMembers.report');
    expect(find.byKey(const Key('groupReport.title')), findsOneWidget);
    await _tap(tester, 'groupReport.reason.0');

    expect(support.messages, hasLength(1));
    final String body = support.messages.single['body']! as String;
    expect(body, contains('الاسم: Office League'));
    expect(body, contains('المعرّف: g-253'));
    expect(body, contains(groupReportReasons.first));
    expect(find.text(reportSentMessage), findsOneWidget);
    // The members are still listed: a report hides nothing.
    expect(find.text('Sara'), findsOneWidget);
  });

  testWidgets('closing the reason sheet sends nothing', (tester) async {
    final FakeSupportServer support = FakeSupportServer();
    await _pump(tester, isOwner: false, support: support);

    await _tap(tester, 'groupMembers.report');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(support.messages, isEmpty);
  });

  testWidgets('the owner of the league has no report button', (tester) async {
    await _pump(tester, isOwner: true, support: FakeSupportServer());

    expect(find.byKey(const Key('groupMembers.title')), findsOneWidget);
    expect(find.byKey(const Key('groupMembers.report')), findsNothing);
  });
}
