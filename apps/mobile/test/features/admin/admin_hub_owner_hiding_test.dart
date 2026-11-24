/// «الإدارة العامة للمالك» through the real hub (script 306): an admin with no
/// owner seat finds no trace of it, in the phone's drawer, in the wide
/// layout's sidebar or by opening the section directly; the owner seat's own
/// drawer lists it (the positive control, so the absences above are not just
/// an empty harness). The seat is known by the server's `is_owner` flag only.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

// NK306_01
const String _ownerPage = 'الإدارة العامة للمالك';

const AuthenticatedUserDto _owner = AuthenticatedUserDto(
  userId: 'u-owner-id',
  role: 'admin',
  status: 'active',
  email: 'owner@example.com',
  isOwner: true,
);

const AuthenticatedUserDto _otherAdmin = AuthenticatedUserDto(
  userId: 'u-admin',
  role: 'admin',
  status: 'active',
  email: 'reviewer@example.com',
);

Future<http.Response> Function(http.Request) _serverFor(
  AuthenticatedUserDto me,
) {
  return (http.Request request) async => okMe(me);
}

Future<void> _open(
  WidgetTester tester,
  AuthenticatedUserDto me, {
  required Size size,
  AdminSection? initialSection,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final AuthHarness harness = buildAuthHarness(
    _serverFor(me),
    seedToken: 'admin-jwt',
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        monthlySeasonsProvider.overrideWith((ref) async => const <SeasonDto>[]),
        adminDashboardProvider.overrideWith(
          (ref) async => const AdminDashboardSnapshot(
            stats: UserStatsDto(total: 0, active: 0, suspended: 0),
            auditLog: AuditLogDto(entries: []),
            competitions: [],
            currentMonthFixtures: [],
          ),
        ),
        adminAttentionProvider.overrideWith(
          (ref) async => const AdminAttention(freshErrors: 0),
        ),
        adminMonthPulseProvider.overrideWith(
          (ref) async =>
              const AdminMonthPulse(current: null, board: null, uncrowned: []),
        ),
        adminRetentionProvider.overrideWith(
          (ref) async => const AdminRetentionDto(
            today: '2026-09-28',
            weeks: [
              RetentionWeekDto(
                weekStart: '2026-09-28',
                complete: false,
                activeUsers: 0,
                active3Plus: 0,
                leagueActive: 0,
                leagueActive3Plus: 0,
                leagueMembers: 0,
                leagueReturned: null,
              ),
            ],
            cohorts: [],
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AdminHubScreen(initialSection: initialSection),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('admin.hub.drawer')), findsOneWidget);
}

void main() {
  const Size phone = Size(400, 800);
  const Size wide = Size(1200, 800);

  testWidgets('a phone admin with no seat: the drawer has no owner page', (
    tester,
  ) async {
    await _open(tester, _otherAdmin, size: phone);
    await _openDrawer(tester);

    // The drawer is built: its first tile is the home page's.
    expect(find.byKey(const Key('admin.shell.nav.dashboard')), findsOneWidget);
    expect(find.byKey(const Key('admin.shell.nav.owner')), findsNothing);
    expect(find.text(_ownerPage), findsNothing);
  });

  testWidgets('a wide admin with no seat: the sidebar has no owner page', (
    tester,
  ) async {
    await _open(tester, _otherAdmin, size: wide);

    expect(find.byKey(const Key('admin.shell.sidebar')), findsOneWidget);
    expect(find.byKey(const Key('admin.shell.nav.dashboard')), findsOneWidget);
    expect(find.byKey(const Key('admin.shell.nav.owner')), findsNothing);
    expect(find.text(_ownerPage), findsNothing);
  });

  testWidgets('opening the owner page directly draws none of its tabs', (
    tester,
  ) async {
    await _open(
      tester,
      _otherAdmin,
      size: phone,
      initialSection: AdminSection.owner,
    );

    expect(find.byKey(const Key('admin.owner.none')), findsOneWidget);
    expect(find.text('المفاتيح'), findsNothing);
    expect(find.text('المخفيون'), findsNothing);
    expect(find.text('المواجهات'), findsNothing);
  });

  testWidgets('the owner seat\'s phone drawer lists the owner page', (
    tester,
  ) async {
    await _open(tester, _owner, size: phone);
    await _openDrawer(tester);

    expect(find.byKey(const Key('admin.shell.nav.owner')), findsOneWidget);
    expect(find.text(_ownerPage), findsWidgets);
  });

  testWidgets('the owner seat\'s wide sidebar lists the owner page', (
    tester,
  ) async {
    await _open(tester, _owner, size: wide);

    expect(find.byKey(const Key('admin.shell.nav.owner')), findsOneWidget);
  });
}
