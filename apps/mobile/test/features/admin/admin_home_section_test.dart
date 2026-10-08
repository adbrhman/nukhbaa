/// The admin home (2026-10-07): what needs a decision, today's matches, the
/// pulse, the latest actions in words. Drawn through the real section with
/// the real theme; the providers are overridden and the clock is fixed, so
/// the test reads the same at any hour, midnight included.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/features/admin/screens/sections/admin_home_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

// 2026-10-07 15:00 Riyadh (12:00 UTC).
final DateTime _now = DateTime.utc(2026, 10, 7, 12);

// 137 and 47 sit above the GET /admin/users page cap (50): the pulse must
// read the real aggregate, not the length of a capped page.
const UserStatsDto _stats = UserStatsDto(total: 137, active: 90, suspended: 47);

CurrentMonthFixtureItemDto _fixture(
  String id,
  String home,
  DateTime kickoff, {
  int? resultHome,
  int? resultAway,
}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'الدوري الإنجليزي',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: id,
    homeTeam: home,
    awayTeam: 'Chelsea',
    kickoffAt: kickoff.toIso8601String(),
  ),
  resultHomeGoals: resultHome,
  resultAwayGoals: resultAway,
);

// Over three hours ago with no result: the one match waiting.
final CurrentMonthFixtureItemDto _awaiting = _fixture(
  'f-await',
  'Arsenal',
  _now.subtract(const Duration(hours: 3)),
);
// Over with its result recorded.
final CurrentMonthFixtureItemDto _done = _fixture(
  'f-done',
  'Liverpool',
  _now.subtract(const Duration(hours: 5)),
  resultHome: 2,
  resultAway: 1,
);
// Kicked off half an hour ago.
final CurrentMonthFixtureItemDto _live = _fixture(
  'f-live',
  'Everton',
  _now.subtract(const Duration(minutes: 30)),
);
// Tonight, 19:00 Riyadh.
final CurrentMonthFixtureItemDto _later = _fixture(
  'f-later',
  'Fulham',
  _now.add(const Duration(hours: 4)),
);
// Tomorrow: in the month, not today.
final CurrentMonthFixtureItemDto _tomorrow = _fixture(
  'f-tomorrow',
  'Brentford',
  _now.add(const Duration(days: 1)),
);

const List<AuditEntryDto> _entries = <AuditEntryDto>[
  AuditEntryDto(
    id: 'a-1',
    actorId: 'u-admin',
    action: 'fixture_hidden',
    targetRef: 'f-done',
    occurredAt: '2026-10-07T11:00:00.000Z',
  ),
  AuditEntryDto(
    id: 'a-2',
    actorId: 'u-admin',
    action: 'user_renamed',
    targetRef: '3a5610b1-70b8-443d-a5ba-6abd00000000',
    occurredAt: '2026-10-07T10:00:00.000Z',
  ),
  AuditEntryDto(
    id: 'a-3',
    actorId: 'u-admin',
    action: 'a_token_this_build_does_not_know',
    targetRef: 'x-1',
    occurredAt: '2026-10-07T09:00:00.000Z',
  ),
];

Future<List<AdminSection>> _pump(
  WidgetTester tester, {
  List<CurrentMonthFixtureItemDto>? fixtures,
  AdminAttention attention = const AdminAttention(
    heldReferrals: 2,
    freshErrors: 3,
  ),
  Size size = const Size(900, 6000),
  double textScale = 1,
}) async {
  // Tall: every card of the list is built at once, so a "findsNothing"
  // below is not a lazy list that never built the item.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final List<AdminSection> opened = <AdminSection>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminDashboardProvider.overrideWith(
          (ref) async => AdminDashboardSnapshot(
            stats: _stats,
            auditLog: const AuditLogDto(entries: _entries),
            competitions: const <CompetitionDto>[],
            currentMonthFixtures:
                fixtures ??
                <CurrentMonthFixtureItemDto>[
                  _awaiting,
                  _done,
                  _live,
                  _later,
                  _tomorrow,
                ],
          ),
        ),
        adminAttentionProvider.overrideWith((ref) async => attention),
        adminRetentionProvider.overrideWith(
          (ref) async => const AdminRetentionDto(
            today: '2026-10-07',
            weeks: <RetentionWeekDto>[
              RetentionWeekDto(
                weekStart: '2026-10-05',
                complete: false,
                activeUsers: 11,
                active3Plus: 0,
                leagueActive: 0,
                leagueActive3Plus: 0,
                leagueMembers: 0,
                leagueReturned: null,
              ),
            ],
            cohorts: <RetentionCohortDto>[],
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: AdminHomeSection(onNavigate: opened.add, now: () => _now),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The last card is on screen: the list was built to its end.
  expect(find.byKey(const Key('admin.dashboard.activity.all')), findsOneWidget);
  return opened;
}

Finder _in(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

void main() {
  testWidgets('each waiting thing has a row with its count that opens it', (
    tester,
  ) async {
    final List<AdminSection> opened = await _pump(tester);

    expect(
      _in('admin.dashboard.attention.results', find.text('1')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.attention.referrals', find.text('2')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.attention.errors', find.text('3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.dashboard.attention.clear')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('admin.dashboard.attention.results')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('admin.dashboard.attention.referrals')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin.dashboard.attention.errors')));
    await tester.pump();
    expect(opened, <AdminSection>[
      AdminSection.resultsScoring,
      AdminSection.referrals,
      AdminSection.errorLog,
    ]);
  });

  testWidgets('nothing waiting reads as clear, not as an empty card', (
    tester,
  ) async {
    await _pump(
      tester,
      fixtures: <CurrentMonthFixtureItemDto>[_done, _later],
      attention: const AdminAttention(heldReferrals: 0, freshErrors: 0),
    );

    expect(
      find.byKey(const Key('admin.dashboard.attention.clear')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.dashboard.attention.results')),
      findsNothing,
    );
  });

  testWidgets('a source that failed says so instead of a false zero', (
    tester,
  ) async {
    await _pump(
      tester,
      fixtures: <CurrentMonthFixtureItemDto>[_done],
      attention: const AdminAttention(heldReferrals: null, freshErrors: null),
    );

    expect(find.text('تعذّر التحقق من الدعوات والأخطاء'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.dashboard.attention.clear')),
      findsNothing,
    );
  });

  testWidgets("today lists the Riyadh day only, each match's state in words", (
    tester,
  ) async {
    await _pump(tester);

    expect(
      _in(
        'admin.dashboard.today.f-await',
        find.textContaining('بانتظار النتيجة'),
      ),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.today.f-done', find.textContaining('انتهت 2-1')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.today.f-live', find.textContaining('مباشرة')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.today.f-later', find.textContaining('قادمة')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.dashboard.today.f-tomorrow')),
      findsNothing,
    );
    // No raw instant anywhere on the page.
    expect(find.textContaining('000Z'), findsNothing);
    expect(find.textContaining('T12:'), findsNothing);
  });

  testWidgets('the pulse reads the real aggregates; the old noise is gone', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('إجمالي اللاعبين'), findsOneWidget);
    expect(find.text('137'), findsOneWidget);
    expect(find.text('موقوفون'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
    expect(find.text('لعبوا هذا الأسبوع'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    // "Active" meaning "not suspended" contradicted the weekly figure.
    expect(find.text('مستخدمون نشطون'), findsNothing);
    expect(find.text('مركز العمليات'), findsNothing);
    expect(find.text('إجراءات سريعة'), findsNothing);
  });

  testWidgets('the latest actions read as sentences, never as codes or ids', (
    tester,
  ) async {
    final List<AdminSection> opened = await _pump(tester);

    expect(find.text('إخفاء مباراة: Liverpool × Chelsea'), findsOneWidget);
    expect(find.text('تغيير اسم لاعب'), findsOneWidget);
    expect(find.text('إجراء إداري'), findsOneWidget);
    expect(find.textContaining('fixture_hidden'), findsNothing);
    expect(find.textContaining('3a5610b1'), findsNothing);

    await tester.tap(find.byKey(const Key('admin.dashboard.activity.all')));
    await tester.pump();
    expect(opened, <AdminSection>[AdminSection.audit]);
  });

  testWidgets('on a phone at double text size every row fits', (tester) async {
    // The UI survey draws the home page with empty data, so it never sees
    // the attention rows or today's matches; this draws all of them at the
    // survey's phone width and its largest text size. An overflow is a
    // FlutterError, which fails the test on its own.
    await _pump(tester, size: const Size(360, 6000), textScale: 2);

    expect(
      find.byKey(const Key('admin.dashboard.attention.errors')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.dashboard.today.f-later')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.dashboard.today.all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
