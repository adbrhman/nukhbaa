/// Button labels on their own fills, drawn through the real entry points in
/// both themes: a destructive confirm (AppDialog.confirm -- sign out,
/// leave, delete) and the home card's "start predicting". Before the colour
/// audit of 2026-10-15 the destructive confirm was white on the dark
/// theme's bright red (3.5:1), and the home button's blue sat at 4.54:1 on
/// white, on the edge (CA-12).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/app_dialog.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show sampleUser;
import '../../support/current_month_fixtures_harness.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The fill right under [label]: the nearest [Material] around it.
Color _fillUnder(WidgetTester tester, Finder label) => tester
    .widget<Material>(
      find.ancestor(of: label, matching: find.byType(Material)).first,
    )
    .color!;

/// The colour [label] is drawn in: its own style, else the inherited one.
Color _labelColour(WidgetTester tester, Finder label) =>
    tester.widget<Text>(label).style?.color ??
    DefaultTextStyle.of(tester.element(label)).style.color!;

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    testWidgets('$name: a destructive confirm reads on its red', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => AppDialog.confirm(
                    context,
                    title: 'title',
                    message: 'message',
                    confirmLabel: 'confirm',
                    cancelLabel: 'cancel',
                    destructive: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final Finder confirm = find.text('confirm');
      final double ratio = _contrast(
        _labelColour(tester, confirm),
        _fillUnder(tester, confirm),
      );
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$name: the confirm label is ${ratio.toStringAsFixed(2)}:1',
      );
    });

    testWidgets('$name: the home "start predicting" label reads on white', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = buildCurrentMonthFixturesHarness((request) async {
        final String path = request.url.path;
        if (path == '/feed/current-month-fixtures' ||
            path == '/me/fixture-predictions' ||
            path == '/teams') {
          return okJsonList(const []);
        }
        return http.Response('not found', 404);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: theme,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: HomeScreen(
              user: sampleUser,
              onOpenMatches: () {},
              onOpenAccount: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder label = find.descendant(
        of: find.byKey(const Key('home.startPredicting')),
        matching: find.byType(Text),
      );
      final double ratio = _contrast(
        _labelColour(tester, label),
        _fillUnder(tester, label),
      );
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$name: "start predicting" is ${ratio.toStringAsFixed(2)}:1',
      );
    });
  }
}
