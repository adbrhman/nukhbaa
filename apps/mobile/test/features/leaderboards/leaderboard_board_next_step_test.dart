/// The summary's next rung (script 125), drawn through the real board: a
/// viewer far down sees the points to the rank just above, then the points
/// to the top; a viewer whose next rung is the top sees one line, as before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

BoardEntry _entry(String id, int rank, int points) => BoardEntry(
  participantId: id,
  rank: rank,
  displayName: id,
  points: points,
  pointsLabel: '$points',
);

Future<void> _pump(
  WidgetTester tester,
  List<BoardEntry> entries,
  String me,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LeaderboardBoard(
            entries: entries,
            keyPrefix: 'nextTest',
            myParticipantId: me,
            showHeader: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('far down: the rank just above, then the top', (tester) async {
    await _pump(tester, <BoardEntry>[
      _entry('a', 1, 96),
      _entry('b', 2, 87),
      _entry('c', 3, 87),
      _entry('x', 71, 48),
      _entry('y', 71, 48),
      _entry('me', 73, 42),
    ], 'me');

    expect(find.text('6 نقاط للوصول للمرتبة 71'), findsOneWidget);
    expect(find.text('54 نقطة للوصول للمرتبة 1'), findsOneWidget);
    // Reading order: the next rung on the line above, or on the same line
    // to its right in Arabic -- the two pills wrap on a phone.
    final Rect next = tester.getRect(find.text('6 نقاط للوصول للمرتبة 71'));
    final Rect top = tester.getRect(find.text('54 نقطة للوصول للمرتبة 1'));
    expect(
      next.top < top.top || (next.top == top.top && next.right > top.right),
      isTrue,
      reason: 'the next rung reads first',
    );
  });

  testWidgets('when the next rung is the top, one line as before', (
    tester,
  ) async {
    await _pump(tester, <BoardEntry>[
      _entry('a', 1, 21),
      _entry('b', 2, 19),
    ], 'b');

    expect(find.text('نقطتان للوصول للمرتبة 1'), findsOneWidget);
    expect(find.textContaining('للوصول للمرتبة 2'), findsNothing);
  });

  testWidgets('the leader sees no next rung', (tester) async {
    await _pump(tester, <BoardEntry>[
      _entry('a', 1, 21),
      _entry('b', 2, 19),
    ], 'a');

    expect(find.text('أنت في الصدارة 🥇'), findsOneWidget);
    expect(find.textContaining('للوصول للمرتبة'), findsNothing);
  });
}
