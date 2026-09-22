/// Where a push opens the app (batch 3b): the `link` value of its FCM data
/// payload. The app maps each to a screen; a link it does not know opens
/// the app as a plain tap would.
///
/// A closed set of names, not routes: the server says what the push is
/// about, the app decides how to show it.
abstract final class PushLink {
  /// The fixtures to predict: the daily reminder, the pre-match push and
  /// the streak saver.
  static const String fixtures = 'fixtures';

  /// This week's league table: the overtaken push.
  static const String league = 'league';

  /// The in-app inbox: exact-hit and announcement pushes, sent now or
  /// deferred out of the quiet hours.
  static const String inbox = 'inbox';
}
