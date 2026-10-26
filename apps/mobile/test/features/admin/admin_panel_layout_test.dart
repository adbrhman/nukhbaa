/// The admin panel's layout after script 124, through the real hub and the
/// real home section with their reads answered at once: user names are a
/// tab of the users section, back from a section opens the home page
/// instead of leaving the panel, and the home page's four quick tiles open
/// their sections.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/features/admin/screens/sections/admin_home_section.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

List<Override> _overrides() => <Override>[
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
];

Widget _app(Widget home) => ProviderScope(
  overrides: _overrides(),
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('ar'),
    home: home,
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _title(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

void main() {
  testWidgets('users opens on its two tabs, and back returns to the home '
      'page instead of leaving the panel', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const AdminHubScreen()));
    await tester.pumpAndSettle();
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AdminHubScreen)),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    final Finder usersTile = find.byKey(const Key('admin.shell.nav.users'));
    await tester.scrollUntilVisible(
      usersTile,
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('admin.shell.navList')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(usersTile);
    await tester.pumpAndSettle();

    expect(_title(l10n.adminUsersTab), findsOneWidget);
    expect(find.byKey(const Key('admin.users.tabs')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.users.tabs')),
        matching: find.text('الحسابات'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.users.tabs')),
        matching: find.text('الأسماء'),
      ),
      findsOneWidget,
    );

    // The system back gesture asks the navigator to pop the panel's route.
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();

    expect(find.byType(AdminHubScreen), findsOneWidget);
    expect(_title(l10n.adminDashboardTab), findsOneWidget);
    expect(find.byKey(const Key('admin.users.tabs')), findsNothing);
  });

  testWidgets('the four quick tiles open their sections', (tester) async {
    _phone(tester);
    final List<AdminSection> opened = <AdminSection>[];
    await tester.pumpWidget(
      _app(Scaffold(body: AdminHomeSection(onNavigate: opened.add))),
    );
    await tester.pumpAndSettle();

    for (final AdminSection section in <AdminSection>[
      AdminSection.resultsScoring,
      AdminSection.fixtures,
      AdminSection.announcements,
      AdminSection.users,
    ]) {
      await tester.tap(
        find.byKey(Key('admin.dashboard.quick.${section.name}')),
      );
      await tester.pump();
    }

    expect(opened, <AdminSection>[
      AdminSection.resultsScoring,
      AdminSection.fixtures,
      AdminSection.announcements,
      AdminSection.users,
    ]);
  });
}
