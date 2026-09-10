/// Pins the leaderboard's gap pill to competition ranking (1-1-1-4): a
/// viewer tied on the top total is the leader -- never "0 points to reach
/// rank 1" -- and anyone below is measured to the leader, with Arabic
/// number agreement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';

BoardEntry _entry(String id, int rank, int points) => BoardEntry(
  participantId: id,
  rank: rank,
  displayName: id,
  points: points,
  pointsLabel: '$points',
);

Future<void> _pump(WidgetTester tester, List<BoardEntry> entries, String me) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LeaderboardBoard(
              entries: entries,
              keyPrefix: 'gapTest',
              myParticipantId: me,
            ),
          ),
        ),
      ),
    );

final List<BoardEntry> _board = <BoardEntry>[
  _entry('a', 1, 21),
  _entry('b', 1, 21),
  _entry('c', 1, 21),
  _entry('d', 4, 17),
  _entry('e', 5, 16),
];

void main() {
  testWidgets('a viewer tied on rank 1 is the leader, not 0 points away', (
    tester,
  ) async {
    await _pump(tester, _board, 'b');
    expect(find.text('أنت في الصدارة 🥇'), findsOneWidget);
    expect(find.textContaining('للوصول للمرتبة'), findsNothing);
  });

  testWidgets('a viewer below rank 1 is measured to the leader', (
    tester,
  ) async {
    await _pump(tester, _board, 'd');
    expect(find.text('4 نقاط للوصول للمرتبة 1'), findsOneWidget);
    expect(find.text('أنت في الصدارة 🥇'), findsNothing);
  });

  testWidgets('a two-point gap uses the Arabic dual', (tester) async {
    await _pump(tester, <BoardEntry>[
      _entry('a', 1, 21),
      _entry('b', 2, 19),
    ], 'b');
    expect(find.text('نقطتان للوصول للمرتبة 1'), findsOneWidget);
  });
}
