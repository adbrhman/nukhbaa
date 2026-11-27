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
import 'package:mobile/features/leaderboards/cup_champions_providers.dart';
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
  CupChampionsDto cup = const CupChampionsDto(champions: <CupChampionDto>[]),
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        monthChampionsProvider.overrideWith((ref) => load()),
        cupChampionsProvider.overrideWith((ref) async => cup),
      ],
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

  CupChampionsDto cupOf() => const CupChampionsDto(
    champions: <CupChampionDto>[
      CupChampionDto(
        monthStart: '2026-11-01',
        place: 1,
        how: 'final',
        userId: 'c1',
        displayName: 'cup-one',
      ),
      CupChampionDto(
        monthStart: '2026-11-01',
        place: 2,
        how: 'walkover',
        userId: 'c2',
        displayName: 'cup-two',
        decidedAt: '2026-11-06T12:00:00.000Z',
      ),
    ],
  );

  testWidgets('the Elite Cup champions are listed by month and path', (
    tester,
  ) async {
    await _pump(tester, () async => twoMonths, cup: cupOf());
    await tester.scrollUntilVisible(
      find.byKey(const Key('hall.section.cup')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('أبطال كأس النخبة'), findsOneWidget);
    expect(find.text('نوفمبر 2026'), findsOneWidget);
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.1')),
      findsOneWidget,
    );
    expect(find.text('cup-one'), findsOneWidget);
    expect(find.text('كأس النخبة · فاز في النهائي'), findsOneWidget);
    expect(
      find.text('كأس المسار الثاني · تُوِّج بلا خصم في النهائي'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no champion of the cup yet: the section takes no room', (
    tester,
  ) async {
    await _pump(tester, () async => twoMonths);
    expect(find.byKey(const Key('hall.section.cup')), findsNothing);
  });

  CupChampionDto cupPath(int place, String name, String? decidedAt) =>
      CupChampionDto(
        monthStart: '2026-11-01',
        place: place,
        how: 'final',
        userId: 'u$place',
        displayName: name,
        decidedAt: decidedAt,
      );

  Future<void> scrollToCup(WidgetTester tester) => tester.scrollUntilVisible(
    find.byKey(const Key('hall.section.cup')),
    300,
    scrollable: find.byType(Scrollable).first,
  );

  // The screen's clock in these tests is 2026-11-07 00:00 UTC.
  testWidgets('a runner-up leaves the hall 48 hours after its title', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => twoMonths,
      cup: CupChampionsDto(
        champions: <CupChampionDto>[
          cupPath(1, 'cup-one', '2026-10-01T10:00:00.000Z'),
          cupPath(2, 'cup-two', '2026-11-05T00:00:01.000Z'),
          cupPath(3, 'cup-three', '2026-11-05T00:00:00.000Z'),
        ],
      ),
    );
    await scrollToCup(tester);
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.3')),
      findsNothing,
    );
    expect(find.text('أبطال كأس النخبة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only path 1 left: the heading goes singular', (tester) async {
    await _pump(
      tester,
      () async => twoMonths,
      cup: CupChampionsDto(
        champions: <CupChampionDto>[
          cupPath(1, 'cup-one', '2026-10-01T10:00:00.000Z'),
          cupPath(2, 'cup-two', '2026-11-05T00:00:00.000Z'),
          cupPath(3, 'cup-three', null),
        ],
      ),
    );
    await scrollToCup(tester);
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.2')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.3')),
      findsNothing,
    );
    expect(find.text('بطل كأس النخبة'), findsOneWidget);
    expect(find.text('أبطال كأس النخبة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unreadable decided_at hides a runner-up', (tester) async {
    await _pump(
      tester,
      () async => twoMonths,
      cup: CupChampionsDto(
        champions: <CupChampionDto>[
          cupPath(1, 'cup-one', null),
          cupPath(2, 'cup-two', 'not-a-date'),
          cupPath(3, 'cup-three', ''),
        ],
      ),
    );
    await scrollToCup(tester);
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.2')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.3')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nobody left to show: the cup section takes no room', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => twoMonths,
      cup: CupChampionsDto(
        champions: <CupChampionDto>[
          cupPath(2, 'cup-two', '2026-11-01T00:00:00.000Z'),
        ],
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('hall.section.legends')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('hall.section.cup')), findsNothing);
    expect(
      find.byKey(const Key('hall.cup.champion.2026-11-01.2')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cup fits 360 wide at double text size', (tester) async {
    await _pump(tester, () async => twoMonths, cup: cupOf(), textScale: 2);
    await tester.scrollUntilVisible(
      find.byKey(const Key('hall.cup.champion.2026-11-01.2')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
