/// The verdict marks on the web are icons from the app's own font, never
/// emoji that need fonts.gstatic.com (audit L-53); on native they stay the
/// text the screens and their tests read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/emoji_mark.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('as icons: a doubled hit is a bolt and a flame, no text', (
    tester,
  ) async {
    await _pump(tester, const EmojiMark('⚡🔥', asIcons: true));

    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('as icons: a hit and a miss', (tester) async {
    await _pump(
      tester,
      const Column(
        children: <Widget>[
          EmojiMark('✅', asIcons: true),
          EmojiMark('❌', asIcons: true),
          EmojiMark('', asIcons: true),
        ],
      ),
    );

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(Icon), findsNWidgets(2));
  });

  testWidgets('as text: the same characters, under the given key', (
    tester,
  ) async {
    await _pump(
      tester,
      const EmojiMark('✅', asIcons: false, textKey: Key('mark')),
    );

    expect(tester.widget<Text>(find.byKey(const Key('mark'))).data, '✅');
    expect(find.byType(Icon), findsNothing);
  });

  test('the icons follow the marks, in order', () {
    expect(EmojiMark.iconsFor('⚡🔥'), <IconData>[
      Icons.bolt_rounded,
      Icons.local_fire_department_rounded,
    ]);
    expect(EmojiMark.iconsFor('?'), isEmpty);
  });
}
