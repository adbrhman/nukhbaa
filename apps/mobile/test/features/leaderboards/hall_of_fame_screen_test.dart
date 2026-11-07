/// The Hall of Fame screen, open to every player: what it shows with two
/// crowned months, with none, and that it still fits a
/// 360-wide phone with the text at double size.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/leaderboards/champions_providers.dart';
import 'package:mobile/features/leaderboards/hall_of_fame_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

MonthChampionDto _champion(
  String month,
  String userId,
  int points,
  int exact,
) => MonthChampionDto(
  seasonId: 's-$month',
  seasonLabel: '$month/2026',
  userId: userId,
  displayName: 'player-$userId',
  points: points,
  exactCount: exact,
  decidedCount: 200,
  crownedAt: DateTime.utc(2026, int.parse(month) + 1, 1).toIso8601String(),
  celebrateUntil: DateTime.utc(2026, int.parse(month) + 1, 3).toIso8601String(),
  prize: 'prize-$month',
);

Future<void> _pump(
  WidgetTester tester,
  Future<MonthChampionsDto> Function() load, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [monthChampionsProvider.overrideWith((ref) => load())],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: HallOfFameScreen(now: DateTime.utc(2026, 11, 7)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final MonthChampionsDto twoMonths = MonthChampionsDto(
    champions: <MonthChampionDto>[
      _champion('10', 'b', 138, 40),
      _champion('09', 'a', 132, 40),
    ],
  );

  testWidgets('shows the cup, the months, the titles and the records', (
    tester,
  ) async {
    await _pump(tester, () async => twoMonths);
    expect(find.byKey(const Key('champions.record.title')), findsOneWidget);
    expect(find.byKey(const Key('hall.season.cup')), findsOneWidget);
    expect(find.text('كأس موسم 2026/2027'), findsOneWidget);
    expect(find.text('ينتظر بطله'), findsOneWidget);
    expect(
      find.byKey(const Key('champions.record.champion.s-10.b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('champions.record.champion.s-09.a')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('hall.record.mostPoints')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('hall.record.mostPoints')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two months crowned: the legends say how to get in', (
    tester,
  ) async {
    await _pump(tester, () async => twoMonths);
    await tester.scrollUntilVisible(
      find.byKey(const Key('hall.legends.empty')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('hall.legends.empty')), findsOneWidget);
    expect(find.textContaining('لم يدخل أحد'), findsOneWidget);
  });

  testWidgets('nothing crowned yet: the cup still waits, the rest is empty', (
    tester,
  ) async {
    await _pump(tester, () async => const MonthChampionsDto(champions: []));
    expect(find.byKey(const Key('hall.season.cup')), findsOneWidget);
    expect(find.byKey(const Key('champions.record.empty')), findsOneWidget);
    expect(find.byKey(const Key('hall.section.records')), findsNothing);
  });

  testWidgets('fits 360 wide at double text size without overflow', (
    tester,
  ) async {
    await _pump(tester, () async => twoMonths, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('hall.legends.empty')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
