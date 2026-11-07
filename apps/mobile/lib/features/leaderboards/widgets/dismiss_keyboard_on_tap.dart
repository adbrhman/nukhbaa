/// Puts the on-screen keyboard away when a screen without any text field is
/// touched.
///
/// On a phone's browser a text field left over from an earlier screen can keep
/// the keyboard coming back on every tap. A screen that reads and never types
/// wraps itself in this: a touch drops the focus and asks the platform to hide
/// the keyboard. It never takes the touch from the screen underneath.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps [child]; every touch on it releases the text focus.
class DismissKeyboardOnTap extends StatelessWidget {
  /// Creates the wrapper.
  const DismissKeyboardOnTap({required this.child, super.key});

  /// The screen to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        unawaited(
          SystemChannels.textInput
              .invokeMethod<void>('TextInput.hide')
              .catchError((Object _) {}),
        );
      },
      child: child,
    );
  }
}
