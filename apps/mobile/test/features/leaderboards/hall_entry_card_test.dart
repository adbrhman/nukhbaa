/// The Hall of Fame's door on the leaderboard tab: it says what it opens, it
/// answers a touch, and the keyboard guard lets go of a focused field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/leaderboards/widgets/dismiss_keyboard_on_tap.dart';
import 'package:mobile/features/leaderboards/widgets/hall_entry_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

Widget _app(Widget body) => MaterialApp(
  theme: AppTheme.dark,
  locale: const Locale('ar'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

void main() {
  testWidgets('the card names the hall and opens it on a tap', (tester) async {
    int opened = 0;
    await tester.pumpWidget(_app(HallEntryCard(onTap: () => opened++)));
    expect(find.text('قاعة المشاهير'), findsOneWidget);
    expect(find.textContaining('الأرقام القياسية'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leaderboards.hall.entry')));
    expect(opened, 1);
  });

  testWidgets('the card keeps a comfortable touch height', (tester) async {
    await tester.pumpWidget(_app(HallEntryCard(onTap: () {})));
    final Size size = tester.getSize(
      find.byKey(const Key('leaderboards.hall.entry')),
    );
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('a touch on the wrapped screen drops the focus', (tester) async {
    final FocusNode node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(
        DismissKeyboardOnTap(
          child: Column(
            children: <Widget>[
              TextField(focusNode: node),
              const SizedBox(key: Key('blank'), height: 200, width: 200),
            ],
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('blank')));
    await tester.pump();
    expect(node.hasFocus, isFalse);
  });
}
