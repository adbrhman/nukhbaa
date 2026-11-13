/// The podium names (script 271): the first two parts of a long name, a
/// two-word part («عبد الرحمن») kept whole, on up to two lines over the
/// place's full width (the report menu opens from the picture), and the
/// full name on the ranked lines below.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

const String _p = 'pod';

BoardEntry _entry(String id, int rank, String name) => BoardEntry(
  participantId: id,
  rank: rank,
  displayName: name,
  points: 30 - rank,
  pointsLabel: '${30 - rank}',
  matchesCount: 9,
);

final List<BoardEntry> _board = <BoardEntry>[
  _entry('a', 1, 'حمزه علي محمد السقاف'),
  _entry('b', 2, 'عبد الرحمن المغربي'),
  _entry('c', 3, 'Mohammed Nasser Ali'),
  _entry('d', 4, 'سليمان أحمد الرفاعي'),
  _entry('e', 5, 'Osama Khaled'),
];

Future<void> _pump(WidgetTester tester, {String me = 'e'}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark,
        home: Scaffold(
          body: LeaderboardBoard(
            entries: _board,
            keyPrefix: _p,
            myParticipantId: me,
            showHeader: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _nameKey(String id) => find.byKey(Key('$_p.participant.$id'));

String _name(WidgetTester tester, String id) =>
    tester.widget<Text>(_nameKey(id)).data ?? '';

void main() {
  testWidgets('the podium shows a name and its second part', (tester) async {
    await _pump(tester);

    expect(_name(tester, 'a'), 'حمزه علي');
    expect(_name(tester, 'b'), 'عبد الرحمن المغربي');
    expect(_name(tester, 'c'), 'Mohammed Nasser');
  });

  testWidgets('a ranked line keeps the full name', (tester) async {
    await _pump(tester);

    expect(_name(tester, 'd'), 'سليمان أحمد الرفاعي');
  });

  testWidgets('the name has the place to itself, on up to two lines', (
    tester,
  ) async {
    await _pump(tester);

    for (final String id in <String>['a', 'b', 'c']) {
      final Finder place = find.byKey(Key('$_p.item.$id'));
      final RenderBox name = tester.renderObject<RenderBox>(_nameKey(id));
      expect(
        name.constraints.maxWidth,
        closeTo(tester.getSize(place).width, 0.5),
        reason: id,
      );
      expect(tester.widget<Text>(_nameKey(id)).maxLines, 2, reason: id);
      expect(
        find.descendant(of: place, matching: find.byType(IconButton)),
        findsNothing,
        reason: id,
      );
    }
  });

  testWidgets('the picture opens the menu, except the viewer\'s own', (
    tester,
  ) async {
    await _pump(tester, me: 'b');

    expect(find.byKey(const Key('player.menu.a')), findsOneWidget);
    expect(find.byKey(const Key('player.menu.c')), findsOneWidget);
    expect(find.byKey(const Key('player.menu.b')), findsNothing);
    // The whole picture is the target, at least the 48 dp a finger needs.
    final Size picture = tester.getSize(find.byKey(const Key('player.menu.c')));
    expect(picture.width, greaterThanOrEqualTo(48));
    expect(picture.height, greaterThanOrEqualTo(48));
  });
}
