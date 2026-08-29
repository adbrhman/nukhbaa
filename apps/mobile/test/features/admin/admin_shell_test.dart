library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/admin_hub_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

Widget _host() => const ProviderScope(
      child: MaterialApp(
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

        final Finder teamsTile =
            find.byKey(const Key('admin.shell.nav.teams'));
        await tester.ensureVisible(teamsTile);
        await tester.pumpAndSettle();
        await tester.tap(teamsTile);
        await tester.pumpAndSettle();

        expect(find.text(l10n.adminTeamsTab), findsWidgets);
        expect(find.text(l10n.adminSectionComingSoon), findsOneWidget);
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

        // "settings" هو العنصر الأخير (18/18) — لا يُبنى داخل شجرة الـListView
        // الكسول إلا بعد التمرير الفعلي إليه؛ ensureVisible لا يكفي لأنه
        // يتطلب أن يكون العنصر مبنيًا مسبقًا. scrollUntilVisible يُمرِّر
        // تدريجيًا حتى يظهر العنصر فعليًا في الشجرة.
        final Finder settingsTile =
            find.byKey(const Key('admin.shell.nav.settings'));
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
