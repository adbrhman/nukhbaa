library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/screens/sections/admin_dashboard_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

// 137/90/47 عمداً أكبر من حد صفحة GET /admin/users (ListUsers.maxLimit=50):
// لو ظلت البطاقة تقرأ طول تلك الصفحة المحدودة بدل stats الحقيقي، فلن يظهر
// 137 على الشاشة أبداً مهما كان عدد المستخدمين الفعلي.
const _stats = UserStatsDto(total: 137, active: 90, suspended: 47);

// أسبوع فارغ لبطاقة «سلاسة التطبيق» المضمَّنة في اللوحة. نعزلها كما يفعل
// admin_frame_stats_card_test.dart بدل تركها تستدعي HttpClient حقيقياً
// (الذي يرجع 400 في مضيف الاختبار ويترك مؤقّتات معلّقة).
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
        stats: _stats,
        auditLog: AuditLogDto(entries: []),
        competitions: [],
        currentMonthFixtures: [],
      ),
    ),
    adminFrameStatsProvider.overrideWith((ref) async => _emptyFrameStats),
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
    home: Scaffold(body: AdminDashboardSection(onNavigate: (_) {})),
  ),
);

void main() {
  testWidgets('يعرض إجمالي المستخدمين والنشطين والموقوفين الحقيقيين من stats', (
    tester,
  ) async {
    // بطاقات المقاييس قرب أعلى الشاشة فعلاً، لكن نوسّع مساحة الاختبار
    // صراحة بدل الاعتماد على افتراض الحجم الافتراضي -- نفس الدرس
    // الموثّق في admin_shell_test.dart (ListView لا يبني ما هو بعيد
    // عن نافذة العرض).
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('إجمالي المستخدمين'), findsOneWidget);
    expect(find.text('137'), findsOneWidget);
    expect(find.text('مستخدمون نشطون'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('مستخدمون موقوفون'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
    // The two analytics cards moved to their own section (2026-10-07).
    // The list's last item is on screen first, so it was built to its
    // end and "findsNothing" is not a lazy list hiding them.
    expect(find.text('مباريات الشهر الحالي'), findsOneWidget);
    expect(find.byKey(const Key('admin.retention')), findsNothing);
    expect(find.byKey(const Key('admin.frameStats')), findsNothing);
  });
}
