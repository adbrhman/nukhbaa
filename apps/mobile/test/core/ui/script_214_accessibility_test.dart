/// Accessibility Scanner findings of 2026-11-05 (script 214): the bottom bar's
/// tabs are named apart from the screen titles, the date dialog's day columns
/// are 48 dp or more, and a dark crest gets a plate on the dark card.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/accessible_date_picker.dart';
import 'package:mobile/core/ui/team_logo.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/l10n/app_localizations.dart';

Widget _app(Widget home, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.dark,
  locale: const Locale('ar'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: home,
);

void main() {
  testWidgets('a bottom tab is one node named "tab X", not the bare title', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: NukhbaaBottomNav(
                index: 1,
                onChanged: (int index) {},
              ),
            ),
          ),
        ),
      );
      final SemanticsNode fixtures = tester.getSemantics(
        find.byKey(const Key('nav.item.fixtures')),
      );
      expect(fixtures.label, contains('تبويب المباريات'));
      expect(fixtures, isSemantics(isSelected: true, isButton: true));
      // The bare title of the tab is no node's name any more.
      expect(find.bySemanticsLabel('المباريات'), findsNothing);
      expect(find.bySemanticsLabel('الحساب'), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('the date dialog is drawn at 1.06 text scale at least, and a '
      'larger reader scale is kept', (tester) async {
    double? seenDefault;
    double? seenLarge;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) => accessibleDatePickerBuilder(
            context,
            Builder(
              builder: (BuildContext inner) {
                seenDefault = MediaQuery.textScalerOf(inner).scale(1);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(seenDefault, greaterThanOrEqualTo(minDatePickerTextScale));
    // 328 dp x 1.06 over seven columns: 49.7 dp a day.
    expect(328 * minDatePickerTextScale / 7, greaterThanOrEqualTo(48));

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: Builder(
              builder: (BuildContext scaled) => accessibleDatePickerBuilder(
                scaled,
                Builder(
                  builder: (BuildContext inner) {
                    seenLarge = MediaQuery.textScalerOf(inner).scale(1);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(seenLarge, 1.5);
  });

  testWidgets('a crest lost on the dark card sits on a plate; others do not', (
    tester,
  ) async {
    Future<void> pumpLogo(Color? brand) => tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: TeamLogo(
              displayName: 'Test',
              size: 34,
              assetPath: 'assets/flags/finland.png',
              brandColor: brand,
            ),
          ),
        ),
      ),
    );

    await pumpLogo(Colors.black);
    expect(find.byKey(const Key('teamLogo.plate')), findsOneWidget);

    await pumpLogo(Colors.white);
    expect(find.byKey(const Key('teamLogo.plate')), findsNothing);

    await pumpLogo(null);
    expect(find.byKey(const Key('teamLogo.plate')), findsNothing);
  });
}
