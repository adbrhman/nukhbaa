/// A friends' league's members and the ways out (audit M-26, batch 141),
/// through the real screen, the real `GroupsApi` and a fake server: the
/// owner sees each member by name and removes one after confirming, and
/// deletes the league; a member sees no remove button and leaves.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/groups/group_members_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const GroupDto _league = GroupDto(
  id: 'g-1',
  name: 'Office',
  ownerId: 'u-owner',
  inviteCode: 'ABCD23EFGH',
  createdAt: '2026-10-01T00:00:00.000Z',
  memberCount: 2,
);

final class _Server {
  final List<String> deletes = <String>[];

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (request.method == 'DELETE') {
      deletes.add(path);
      if (path == '/groups/g-1') {
        return okJsonObject(const <String, Object?>{'deleted': true});
      }
      if (path == '/groups/g-1/members/me') {
        return okJsonObject(const <String, Object?>{'left': true});
      }
      return okJsonObject(const <String, Object?>{'removed': true});
    }
    switch (path) {
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
}

/// Opens the members screen from a first page, so leaving can pop back.
Future<_Server> _pump(WidgetTester tester, {required bool isOwner}) async {
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        GroupMembersScreen(group: _league, isOwner: isOwner),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  testWidgets('the owner sees names, removes a member after confirming', (
    tester,
  ) async {
    final _Server server = await _pump(tester, isOwner: true);

    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    // Nobody removes the owner, the owner included.
    expect(find.byKey(const Key('groupMembers.remove.u-owner')), findsNothing);
    expect(find.byKey(const Key('groupMembers.leave')), findsNothing);

    await tester.tap(find.byKey(const Key('groupMembers.remove.u-sara')));
    await tester.pumpAndSettle();
    // Cancelled: nothing is sent.
    await tester.tap(find.byKey(const Key('groupMembers.confirm.cancel')));
    await tester.pumpAndSettle();
    expect(server.deletes, isEmpty);

    await tester.tap(find.byKey(const Key('groupMembers.remove.u-sara')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groupMembers.confirm.ok')));
    await tester.pumpAndSettle();

    expect(server.deletes, <String>['/groups/g-1/members/u-sara']);
    expect(find.text('أُخرج Sara من الدوري.'), findsOneWidget);
  });

  testWidgets('the owner deletes the league and the screen closes', (
    tester,
  ) async {
    final _Server server = await _pump(tester, isOwner: true);

    await tester.tap(find.byKey(const Key('groupMembers.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groupMembers.confirm.ok')));
    await tester.pumpAndSettle();

    expect(server.deletes, <String>['/groups/g-1']);
    expect(find.byType(GroupMembersScreen), findsNothing);
  });

  testWidgets('a member has no remove buttons and leaves', (tester) async {
    final _Server server = await _pump(tester, isOwner: false);

    expect(find.byKey(const Key('groupMembers.remove.u-sara')), findsNothing);
    expect(find.byKey(const Key('groupMembers.delete')), findsNothing);

    await tester.tap(find.byKey(const Key('groupMembers.leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groupMembers.confirm.ok')));
    await tester.pumpAndSettle();

    expect(server.deletes, <String>['/groups/g-1/members/me']);
    expect(find.byType(GroupMembersScreen), findsNothing);
  });
}
