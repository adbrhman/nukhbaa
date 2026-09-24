/// The ranked table as the board draws it: every header label sits over its
/// own column, accuracy is a bare percentage in the table and the summary,
/// a line without movement shows a muted dash rather than an empty cell, and
/// nothing claims a refresh time the board does not know.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

const String _p = 'tbl';

BoardEntry _entry(
  String id,
  int rank,
  int points, {
  int? accuracy,
  int? movement,
}) => BoardEntry(
  participantId: id,
  rank: rank,
  displayName: id,
  points: points,
  pointsLabel: '$points',
  matchesCount: 4,
  accuracyPercent: accuracy,
  movement: movement,
);

final List<BoardEntry> _board = <BoardEntry>[
  _entry('a', 1, 20, accuracy: 40, movement: 1),
  _entry('b', 2, 15, accuracy: 30),
  _entry('c', 3, 12, accuracy: 20),
  _entry('d', 4, 10, accuracy: 25, movement: 2),
  _entry('e', 5, 8, movement: 0),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LeaderboardBoard(
            entries: _board,
            keyPrefix: _p,
            myParticipantId: 'd',
            showHeader: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  testWidgets('accuracy is a bare percentage in the row and the summary', (
    tester,
  ) async {
    await _pump(tester);

    expect(_textOf(tester, '$_p.accuracy.d'), '25%');
    expect(find.text('25%'), findsNWidgets(2));
    expect(_textOf(tester, '$_p.accuracy.e'), '—');
  });

  testWidgets('no movement draws a dash, a mover keeps its arrow', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('$_p.movement.e.none')), findsOneWidget);
    expect(find.byKey(const Key('$_p.movement.d')), findsOneWidget);
  });

  testWidgets('no invented refresh time; the gap pill stays', (tester) async {
    await _pump(tester);

    expect(find.textContaining('آخر تحديث'), findsNothing);
    expect(find.text('10 نقاط للوصول للمرتبة 1'), findsOneWidget);
  });

  testWidgets('each header label sits over its own column', (tester) async {
    await _pump(tester);

    for (final String column in <String>['accuracy', 'matches', 'points']) {
      final double header = tester
          .getCenter(find.byKey(Key('boardHeader.$column')))
          .dx;
      final double cell = tester.getCenter(find.byKey(Key('$_p.$column.d'))).dx;
      // The row's 1.4px highlight border is the only difference allowed.
      expect((header - cell).abs(), lessThan(2.0), reason: column);
    }
  });
}
