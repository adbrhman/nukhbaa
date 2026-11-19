/// The name of an empty seat (NK283): from December 2026 a round's empty
/// seat is a vacant seat (its opponent plays an absent opponent, NK278),
/// before it the group average. The group's match card, as the round's
/// matches list draws it, and the admin's late-seat note follow the round's
/// own day, never the phone's date.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_group_matches.dart';
import 'package:mobile/l10n/app_localizations.dart';

const H2hGroupMatchDto _againstEmpty = H2hGroupMatchDto(
  homeUserId: 'u-5',
  homeName: 'ليلى',
  homePoints: 2,
  winner: 'home',
);

Future<void> _pumpPair(WidgetTester tester, String day) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: H2hPairCard(
          key: const Key('h2h.pair.0'),
          match: _againstEmpty,
          status: 'settled',
          round: 4,
          day: day,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('an empty seat by the round day, December on is vacant', () {
    expect(h2hEmptySeatName('2026-12-04'), h2hVacantSeat);
    // A December cycle that runs into January (NK279).
    expect(h2hEmptySeatName('2027-01-02'), h2hVacantSeat);
    expect(h2hEmptySeatName('2026-11-30'), h2hAverageOpponent);
  });

  test('the late-seat note follows the month', () {
    expect(h2hLateSeatNote('2026-12-01'), contains('شاغر'));
    expect(h2hLateSeatNote('2026-12-01'), isNot(contains(h2hAverageOpponent)));
    expect(h2hLateSeatNote('2026-11-01'), contains(h2hAverageOpponent));
  });

  testWidgets('a December match card names the empty seat vacant', (
    tester,
  ) async {
    await _pumpPair(tester, '2026-12-04');

    expect(find.text(h2hVacantSeat), findsOneWidget);
    expect(find.text(h2hAverageOpponent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a November match card keeps the group average', (tester) async {
    await _pumpPair(tester, '2026-11-04');

    expect(find.text(h2hAverageOpponent), findsOneWidget);
    expect(find.text(h2hVacantSeat), findsNothing);
  });
}
