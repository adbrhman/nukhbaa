/// The ranked board as it draws it: the podium (the leader crowned and
/// raised, places on diamonds), then each line as a card with its figures
/// under the name; accuracy is a bare percentage in the line and the summary,
/// a line without movement shows a muted dash rather than an empty cell, and
/// nothing claims a refresh time the board does not know.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/user_avatar.dart';
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

  testWidgets('below the podium each line is a card; no table header', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('boardHeader.accuracy')), findsNothing);
    // The cards stand apart: a gap between one line and the next.
    final Rect d = tester.getRect(find.byKey(const Key('$_p.item.d')));
    final Rect e = tester.getRect(find.byKey(const Key('$_p.item.e')));
    expect(e.top - d.bottom, greaterThan(4));
    // Accuracy and the counted matches sit under the name, inside the card.
    for (final String figure in <String>['accuracy', 'matches', 'points']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('$_p.item.d')),
          matching: find.byKey(Key('$_p.$figure.d')),
        ),
        findsOneWidget,
        reason: figure,
      );
    }
    final Rect name = tester.getRect(
      find.byKey(const Key('$_p.participant.d')),
    );
    final Rect accuracy = tester.getRect(
      find.byKey(const Key('$_p.accuracy.d')),
    );
    expect(accuracy.top, greaterThanOrEqualTo(name.bottom));
    expect(_textOf(tester, '$_p.points.d'), '10');
  });

  testWidgets('the podium: the leader crowned and raised, places on '
      'diamonds', (tester) async {
    await _pump(tester);

    Finder within(String id, Finder f) =>
        find.descendant(of: find.byKey(Key('$_p.item.$id')), matching: f);
    expect(
      within('a', find.byIcon(Icons.workspace_premium_rounded)),
      findsOneWidget,
    );
    expect(
      within('b', find.byIcon(Icons.workspace_premium_rounded)),
      findsNothing,
    );
    for (final (String id, String rank) in <(String, String)>[
      ('a', '1'),
      ('b', '2'),
      ('c', '3'),
    ]) {
      expect(
        find.descendant(
          of: within(id, find.byType(Transform)),
          matching: find.text(rank),
        ),
        findsWidgets,
        reason: id,
      );
    }
    // The leader's picture stands higher than second and third.
    double top(String id) =>
        tester.getTopLeft(within(id, find.byType(UserAvatar))).dy;
    expect(top('a'), lessThan(top('b')));
    expect(top('a'), lessThan(top('c')));
  });
}
