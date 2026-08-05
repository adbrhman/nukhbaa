library;

/// Canonical stacking order for overlay-style UI.
///
/// Flutter has no native z-index; widgets stack in paint order instead.
/// These constants exist so any code building a manual `Stack`/`Overlay`
/// (rather than relying on `Navigator`/`ScaffoldMessenger`, which already
/// handle their own ordering) can reference an agreed priority instead of
/// guessing. Higher value paints on top.
abstract final class AppLayering {
  static const int content = 0;
  static const int appBar = 10;
  static const int bottomNav = 10;
  static const int stickyHeader = 12;
  static const int snackbar = 30;
  static const int modalScrim = 40;
  static const int bottomSheet = 50;
  static const int dialog = 55;

  /// Reserved for rare full-screen blocking states (e.g. session gate).
  /// Prefer an inline loading/disabled state over this wherever possible.
  static const int blockingLoader = 60;
}
