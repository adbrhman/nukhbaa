/// سجل النقاط (batch 146b, audit C-01 and L-14): the admin picks a month
/// and a player by name, never an id typed by hand, and reads every
/// movement of the fixture ledger with its match named.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/ledger_lookup_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a month and a player by name: every movement, the match '
      'named', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<Uri> asked = <Uri>[];
    final AdminHarness harness = buildAdminHarness((request) async {
      asked.add(request.url);
      switch (request.url.path) {
        case '/months':
          return _json(<Object?>[
            <String, Object?>{
              'id': 'm-10',
              'competition_id': 'c-1',
              'label': '10/2026',
              'start_at': '2026-09-30T21:00:00Z',
              'end_at': '2026-10-31T21:00:00Z',
            },
          ]);
        case '/admin/users':
          return _json(<String, Object?>{
            'schema_version': 1,
            'users': <Object?>[
              <String, Object?>{
                'schema_version': 1,
                'id': 'u-1',
                'email': 'semo@t.io',
                'display_name': 'Semo',
                'status': 'active',
              },
            ],
          });
        case '/admin/users/u-1/points':
          return _json(<String, Object?>{
            'schema_version': 1,
            'played': true,
            'month_points': 3,
            'streak_bonus': 2,
            'entries': <Object?>[
              <String, Object?>{
                'id': 'e1',
                'fixture_id': 'f1',
                'home_team': 'Arsenal',
                'away_team': 'Chelsea',
                'kind': 'fixture_score',
                'amount': 3,
                'occurred_at': '2026-10-10T21:00:00.000Z',
              },
            ],
          });
        case '/admin/audit':
          return _json(<String, Object?>{
            'schema_version': 1,
            'entries': <Object?>[],
          });
      }
      return errorEnvelope(404, 'test.unrouted', request.url.path);
    });
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: LedgerLookupSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No participant id to type any more.
    expect(
      find.byKey(const Key('admin.ledger.participantIdField')),
      findsNothing,
    );

    await _tap(
      tester,
      find.byKey(const Key('admin.fixtures.monthField.field')),
    );
    // An open menu item is tapped where it is: scrolling to it first
    // moves the page under the menu.
    await tester.tap(
      find.byKey(const Key('admin.fixtures.monthField.m-10')).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.ledger.searchField')),
      'semo',
    );
    await _tap(tester, find.byKey(const Key('admin.ledger.search')));
    await _tap(tester, find.byKey(const Key('admin.ledger.user.u-1')));

    final Uri read = asked.lastWhere(
      (Uri u) => u.path == '/admin/users/u-1/points',
    );
    expect(read.queryParameters['season'], 'm-10');
    expect(find.text('Semo'), findsOneWidget);
    expect(find.text('Arsenal × Chelsea'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('نقاط الشهر: 3'), findsOneWidget);
    expect(find.byKey(const Key('admin.ledger.streakBonus')), findsOneWidget);
    expect(find.textContaining('fixture_score'), findsNothing);
  });

  test('every kind of movement reads in words', () {
    expect(pointEntryKindLabel('fixture_score'), 'نقاط المباراة');
    expect(pointEntryKindLabel('correction'), 'تصحيح');
    expect(pointEntryKindLabel('streak_bonus'), startsWith('مكافأة سلسلة'));
  });
}
