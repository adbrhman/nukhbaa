/// Lets go of a keyboard that no field asked for.
///
/// On a phone's browser the page can keep the hidden input of an earlier
/// screen that had a text field (the password-reset code box brings up the
/// number pad), and that input brings its keyboard back on a tap anywhere,
/// the tab bar included. A touch on the wrapped screen, while no text field
/// of the app holds the focus, drops the stray focus and asks the platform
/// to hide the keyboard. It never takes the touch from the screen under it,
/// and it leaves a field being typed in alone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether a text field of the app holds the focus: its keyboard is wanted.
bool _fieldHasFocus() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorStateOfType<EditableTextState>() != null;
}

// NK319_01
/// Drops the focus and hides the keyboard unless a text field is being
/// typed in.
void releaseStrayKeyboard() {
  if (_fieldHasFocus()) return;
  FocusManager.instance.primaryFocus?.unfocus();
  unawaited(
    SystemChannels.textInput
        .invokeMethod<void>('TextInput.hide')
        .catchError((Object _) {}),
  );
}

/// Wraps [child]; every touch on it runs [releaseStrayKeyboard] first.
class ReleaseStrayKeyboard extends StatelessWidget {
  /// Creates the wrapper.
  const ReleaseStrayKeyboard({required this.child, super.key});

  /// The screen to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => releaseStrayKeyboard(),
      child: child,
    );
  }
}
