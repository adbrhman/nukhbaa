/// The admin menu, drawn for real: every section the hub can show has a tile
/// in it. A section missing from the menu groups compiled and passed every
/// other test, yet could never be opened ("user names", 2026-10-03).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/features/admin/admin_shell.dart';
import 'package:mobile/l10n/app_localizations.dart';

Future<List<AdminSection>> _open(WidgetTester tester) async {
  // Tall enough that the whole menu is built at once: no tile is left out
  // of the lazy list because it sits below the fold.
  tester.view.physicalSize = const Size(600, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final List<AdminSection> tapped = <AdminSection>[];
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AdminNavList(
          selected: AdminSection.dashboard,
          onSelect: tapped.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tapped;
}

void main() {
  testWidgets('every admin section has exactly one tile in the menu', (
    tester,
  ) async {
    await _open(tester);

    for (final AdminSection section in AdminSection.values) {
      expect(
        find.byKey(Key('admin.shell.nav.${section.name}')),
        findsOneWidget,
        reason: '${section.name} has no tile in the admin menu',
      );
    }
  });

  testWidgets('the user names tile opens the user names section', (
    tester,
  ) async {
    final List<AdminSection> tapped = await _open(tester);

    expect(find.text('أسماء المستخدمين'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.shell.nav.userNames')));
    await tester.pumpAndSettle();

    expect(tapped, <AdminSection>[AdminSection.userNames]);
  });
}
