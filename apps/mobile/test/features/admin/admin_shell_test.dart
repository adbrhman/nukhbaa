library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contracts/contracts.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

Widget _host() => ProviderScope(
  overrides: [
    adminDashboardProvider.overrideWith(
      (ref) async => const AdminDashboardSnapshot(
        users: UserListDto(users: []),
        auditLog: AuditLogDto(entries: []),
        competitions: [],
        currentMonthFixtures: [],
      ),
    ),
  ],
  child: const MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: AdminHubScreen(),
  ),
);

void main() {
  group('AdminHubScreen navigation', () {
    testWidgets(
      'desktop: شريط جانبي دائم يعرض كل الأقسام؛ اختيار قسم غير منفَّذ يعرض القسم النائب',
      (tester) async {
        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(AdminHubScreen)),
        );

        expect(find.byKey(const Key('admin.shell.sidebar')), findsOneWidget);
        expect(find.byKey(const Key('admin.hub.drawer')), findsNothing);
        expect(find.text(l10n.adminDashboardTab), findsWidgets);

        final Finder teamsTile = find.byKey(
          const Key('admin.shell.nav.ledger'),
        );
        final Finder navScrollable = find.descendant(
          of: find.byKey(const Key('admin.shell.navList')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          teamsTile,
          200,
          scrollable: navScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(teamsTile);
        await tester.pumpAndSettle();

        expect(find.text(l10n.adminLedgerLookupTab), findsWidgets);
      },
    );

    testWidgets(
      'جوال: الشريط الجانبي مخفي، والتنقّل عبر Drawer يغلق نفسه بعد الاختيار',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('admin.shell.sidebar')), findsNothing);
        expect(find.byIcon(Icons.menu), findsOneWidget);

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('admin.hub.drawer')), findsOneWidget);

        // "ledger" (6/8 بعد حذف الأقسام النائبة) دون الطيّ في شاشة 400×800،
        // فلا يُبنى داخل شجرة الـListView الكسول إلا بعد التمرير الفعلي
        // إليه؛ ensureVisible لا يكفي لأنه يتطلب أن يكون العنصر مبنيًا
        // مسبقًا. scrollUntilVisible يُمرِّر تدريجيًا حتى يظهر فعليًا.
        //
        // ليس "audit" (الأخير) لأن AuditLogSection يحمّل عند البناء ولا
        // يكتمل مزوّده في مضيف الاختبار، فيدور مؤشّره أبدًا ولا تستقرّ
        // pumpAndSettle بعد النقر. القسم النائب القديم كان خاملاً فلم
        // تظهر المسألة.
        final Finder settingsTile = find.byKey(
          const Key('admin.shell.nav.ledger'),
        );
        final Finder navScrollable = find.descendant(
          of: find.byKey(const Key('admin.shell.navList')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          settingsTile,
          200,
          scrollable: navScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(settingsTile);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('admin.hub.drawer')), findsNothing);
      },
    );
  });
}
