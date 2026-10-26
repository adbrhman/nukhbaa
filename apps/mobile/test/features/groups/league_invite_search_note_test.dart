/// Audit L-03: a search by name that finds nobody, or fails, says so
/// instead of showing an empty list. Through the real invitation sheet,
/// the real `GroupsApi` and a fake server.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/groups/league_invite_sheet.dart';
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

Future<void> _search(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) handler,
) async {
  final harness = buildCurrentMonthFixturesHarness(handler);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: const Scaffold(body: LeagueInviteSheet(group: _league)),
      ),
    ),
  );
  await tester.enterText(find.byKey(const Key('leagueInvite.search')), 'Zed');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nobody by that name is said', (tester) async {
    await _search(
      tester,
      (request) async => request.url.path == '/groups/invitees'
          ? okJsonObject(
              const GroupInviteesDto(players: <GroupInviteeDto>[]).toJson(),
            )
          : http.Response('not found', 404),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const Key('leagueInvite.searchNote')))
          .data,
      'لا يوجد لاعب بهذا الاسم.',
    );
  });

  testWidgets('a failed search is said, not hidden', (tester) async {
    await _search(tester, (request) async => http.Response('boom', 500));

    expect(find.byKey(const Key('leagueInvite.searchNote')), findsOneWidget);
  });
}
