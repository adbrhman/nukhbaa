/// The terms and prizes a new account reads before the app opens (asked by
/// the backup admin, 2026-11-02): set by [SessionController] when a
/// registration opens a session or a first Google sign-in chooses its name,
/// read by the [SessionGate], cleared by the player's acceptance. Held for
/// the session only: a returning player is never shown them again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the session's new account still has to read the terms.
class WelcomeTerms extends Notifier<bool> {
  @override
  bool build() => false;

  /// A new account was just created: show the terms.
  void show() => state = true;

  /// The player read and accepted them.
  void accept() => state = false;
}

/// See [WelcomeTerms].
final welcomeTermsProvider = NotifierProvider<WelcomeTerms, bool>(
  WelcomeTerms.new,
);
