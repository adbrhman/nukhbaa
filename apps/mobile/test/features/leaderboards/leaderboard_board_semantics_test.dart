/// The ranked table is read out one line per player: a screen reader hears
/// the rank, the name, the points with Arabic number agreement, the accuracy
/// and whether the line is the viewer's own -- not a scatter of bare figures.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

const String _p = 'sem';

BoardEntry _entry(String id, int rank, int points, {int? accuracy}) =>
    BoardEntry(
      participantId: id,
      rank: rank,
      displayName: id,
      points: points,
      pointsLabel: '$points',
      matchesCount: 4,
      accuracyPercent: accuracy,
    );

final List<BoardEntry> _board = <BoardEntry>[
  _entry('a', 1, 20, accuracy: 40),
  _entry('b', 2, 15),
  _entry('c', 3, 12),
  _entry('d', 4, 10, accuracy: 25),
  _entry('e', 5, 2),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // The board speaks through the app's localizations; the labels
        // below are the Arabic ones.
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark,
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

void main() {
  testWidgets('a table line reads as one sentence, the viewer marked', (
    tester,
  ) async {
    // Disposed inside the body: the binding checks for a live handle
    // before addTearDown callbacks run.
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(tester);

      expect(
        tester.getSemantics(find.byKey(const Key('$_p.item.d'))).label,
        'المركز 4، d، 10 نقاط، الدقة 25%، أنت',
      );
      expect(
        tester.getSemantics(find.byKey(const Key('$_p.item.e'))).label,
        'المركز 5، e، نقطتان',
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('the summary reads the viewer standing and the gap together', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(tester);

      expect(
        find.bySemanticsLabel(
          'مركزك 4، 10 نقاط، الدقة 25%، 10 نقاط للوصول للمرتبة 1',
        ),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });
}
