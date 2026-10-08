/// The counts beside the admin menu entries (2026-10-08): the same numbers
/// as the home page's «يحتاج تدخلك», drawn through the real hub -- the
/// desktop sidebar and the phone drawer -- with the providers overridden.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_nav_counts.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/l10n/app_localizations.dart';

// Over five hours ago with no result: past any live window, whatever the
// hour the suite runs at.
CurrentMonthFixtureItemDto _awaiting(String id) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'الدوري الإنجليزي',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-10',
    fixtureId: id,
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 5))
        .toIso8601String(),
  ),
);

final SeasonDto _sep = SeasonDto(
  id: 's-09',
  competitionId: 'c-1',
  label: '09/2026',
  startAt: DateTime.utc(2026, 8, 31, 21),
  endAt: DateTime.utc(2026, 9, 30, 21),
);

AdminDashboardSnapshot _dashboard(List<CurrentMonthFixtureItemDto> items) =>
    AdminDashboardSnapshot(
      stats: const UserStatsDto(total: 0, active: 0, suspended: 0),
      auditLog: const AuditLogDto(entries: <AuditEntryDto>[]),
      competitions: const <CompetitionDto>[],
      currentMonthFixtures: items,
    );

Future<void> _pumpHub(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminDashboardProvider.overrideWith(
          (ref) async =>
              _dashboard(<CurrentMonthFixtureItemDto>[_awaiting('f-1')]),
        ),
        adminAttentionProvider.overrideWith(
          (ref) async => const AdminAttention(heldReferrals: 2, freshErrors: 3),
        ),
        adminMonthPulseProvider.overrideWith(
          (ref) async => AdminMonthPulse(
            current: null,
            board: null,
            uncrowned: <SeasonDto>[_sep],
          ),
        ),
        adminRetentionProvider.overrideWith(
          (ref) async => const AdminRetentionDto(
            today: '2026-10-08',
            weeks: <RetentionWeekDto>[],
            cohorts: <RetentionCohortDto>[],
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const AdminHubScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The count shown on [section]'s menu entry, or null when it shows none.
String? _count(WidgetTester tester, AdminSection section) {
  final Finder badge = find.descendant(
    of: find.byKey(Key('admin.shell.nav.${section.name}')),
    matching: find.byType(Badge),
  );
  if (badge.evaluate().isEmpty) return null;
  final Finder label = find.descendant(of: badge, matching: find.byType(Text));
  return tester.widget<Text>(label).data;
}

const Map<AdminSection, String> _expected = <AdminSection, String>{
  AdminSection.resultsScoring: '1',
  AdminSection.referrals: '2',
  AdminSection.errorLog: '3',
  AdminSection.champions: '1',
};

void _expectCounts(WidgetTester tester) {
  for (final AdminSection section in AdminSection.values) {
    expect(
      _count(tester, section),
      _expected[section],
      reason: 'the count on ${section.name}',
    );
  }
}

void main() {
  test('adminNavCounts: only what waits, nothing for a missing source', () {
    final DateTime now = DateTime.now();
    expect(
      adminNavCounts(
        dashboard: _dashboard(<CurrentMonthFixtureItemDto>[
          _awaiting('a'),
          _awaiting('b'),
        ]),
        attention: const AdminAttention(heldReferrals: 0, freshErrors: 4),
        month: const AdminMonthPulse(
          current: null,
          board: null,
          uncrowned: <SeasonDto>[],
        ),
        now: now,
      ),
      <AdminSection, int>{
        AdminSection.resultsScoring: 2,
        AdminSection.errorLog: 4,
      },
    );
    expect(
      adminNavCounts(dashboard: null, attention: null, month: null, now: now),
      isEmpty,
    );
    // A failed attention read is null counts: no badge, not a zero badge.
    expect(
      adminNavCounts(
        dashboard: null,
        attention: const AdminAttention(heldReferrals: null, freshErrors: null),
        month: null,
        now: now,
      ),
      isEmpty,
    );
  });

  testWidgets('the desktop sidebar counts what the home page lists', (
    tester,
  ) async {
    // Tall: the whole menu and the whole home page are built.
    await _pumpHub(tester, const Size(1280, 6000));

    _expectCounts(tester);
    // The home page's rows carry the same numbers.
    for (final (String key, String count) in <(String, String)>[
      ('admin.dashboard.attention.results', '1'),
      ('admin.dashboard.attention.referrals', '2'),
      ('admin.dashboard.attention.errors', '3'),
      ('admin.dashboard.attention.crowning', '1'),
    ]) {
      expect(
        find.descendant(of: find.byKey(Key(key)), matching: find.text(count)),
        findsOneWidget,
        reason: key,
      );
    }
  });

  testWidgets('the phone drawer shows the same counts', (tester) async {
    await _pumpHub(tester, const Size(360, 6000));

    tester
        .state<ScaffoldState>(find.byKey(const Key('admin.hub.scaffold')))
        .openDrawer();
    await tester.pumpAndSettle();

    _expectCounts(tester);
  });
}
