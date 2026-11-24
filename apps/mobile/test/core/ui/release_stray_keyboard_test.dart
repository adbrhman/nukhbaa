/// The guard against a keyboard that no field asked for: a touch lets go of
/// a stray focus and hides the keyboard, and leaves a field being typed in
/// alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/release_stray_keyboard.dart';

// NK319_03
Widget _app(Widget body) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: body),
);

/// Records the platform's text-input calls; the hide requests are counted.
List<String> _recordTextInput(WidgetTester tester) {
  final List<String> calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.textInput,
    (MethodCall call) async {
      calls.add(call.method);
      return null;
    },
  );
  addTearDown(tester.testTextInput.register);
  return calls;
}

int _hides(List<String> calls) =>
    calls.where((String m) => m == 'TextInput.hide').length;

void main() {
  testWidgets('a touch with no field focused asks to hide the keyboard', (
    tester,
  ) async {
    final List<String> calls = _recordTextInput(tester);
    await tester.pumpWidget(
      _app(
        const ReleaseStrayKeyboard(
          child: SizedBox(key: Key('blank'), height: 200, width: 200),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('blank')));
    await tester.pump();

    expect(_hides(calls), 1);
  });

  testWidgets('a stray focus that is not a field is dropped', (tester) async {
    final List<String> calls = _recordTextInput(tester);
    final FocusNode node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(
        ReleaseStrayKeyboard(
          child: Focus(
            focusNode: node,
            child: const SizedBox(key: Key('blank'), height: 200, width: 200),
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
    expect(_hides(calls), 1);
  });

  testWidgets('a field being typed in keeps its focus and its keyboard', (
    tester,
  ) async {
    final List<String> calls = _recordTextInput(tester);
    final FocusNode node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(
        ReleaseStrayKeyboard(
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
    calls.clear();

    await tester.tap(find.byKey(const Key('blank')));
    await tester.pump();

    expect(node.hasFocus, isTrue);
    expect(_hides(calls), 0);
  });

  testWidgets('the touch still reaches the screen under the guard', (
    tester,
  ) async {
    _recordTextInput(tester);
    int taps = 0;
    await tester.pumpWidget(
      _app(
        ReleaseStrayKeyboard(
          child: Center(
            child: TextButton(
              key: const Key('button'),
              onPressed: () => taps++,
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('button')));

    expect(taps, 1);
  });
}
