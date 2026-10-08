/// The analytics section (2026-10-07): the retention and smoothness cards
/// left the dashboard for their own entry under "النظام". Drawn through the
/// real hub, menu and theme, with the providers overridden.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

const _emptyFrameStats = AdminFrameStatsDto(
  windowDays: 7,
  overall: FrameTotalsDto(
    build: null,
    reports: 0,
    users: 0,
    frames: 0,
    slowFrames: 0,
    frozenFrames: 0,
    worstFrameMs: 0,
    lastReportedAt: '2026-09-24T09:00:00.000Z',
  ),
  builds: [],
);

Widget _host() => ProviderScope(
  overrides: [
    adminDashboardProvider.overrideWith(
      (ref) async => const AdminDashboardSnapshot(
        stats: UserStatsDto(total: 0, active: 0, suspended: 0),
        auditLog: AuditLogDto(entries: []),
        competitions: [],
        currentMonthFixtures: [],
      ),
    ),
    adminFrameStatsProvider.overrideWith((ref) async => _emptyFrameStats),
    adminAttentionProvider.overrideWith(
      (ref) async => const AdminAttention(heldReferrals: 0, freshErrors: 0),
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
    theme: AppTheme.dark,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: const AdminHubScreen(),
  ),
);

void main() {
  testWidgets(
    'the dashboard has no analytics card; the system group opens them',
    (tester) async {
      // Desktop width for the side menu, and tall enough that the whole menu
      // and the whole dashboard are built at once: a lazy list leaves out what
      // sits below the fold, and a "findsNothing" there would prove nothing.
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // The last item of the dashboard is on screen, so the list was built to
      // its end, and neither card is in it.
      expect(
        find.byKey(const Key('admin.dashboard.activity.all')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin.retention')), findsNothing);
      expect(find.byKey(const Key('admin.frameStats')), findsNothing);

      // The home entry stands alone with no group title; the system group is
      // titled and holds the analytics entry.
      expect(find.text('نظرة عامة'), findsNothing);
      expect(find.text('النظام'), findsOneWidget);

      await tester.tap(find.byKey(const Key('admin.shell.nav.analytics')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin.analytics.scroll')), findsOneWidget);
      expect(find.byKey(const Key('admin.retention')), findsOneWidget);
      expect(find.byKey(const Key('admin.frameStats')), findsOneWidget);
      expect(find.byKey(const Key('admin.frameStats.empty')), findsOneWidget);
    },
  );
}
