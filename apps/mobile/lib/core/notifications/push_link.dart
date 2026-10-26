/// Where a push opens the app (batch 3b): the `link` value the server puts
/// in the FCM data payload. Mirrors `PushLink` in the domain package; the
/// two sets must stay equal.
abstract final class PushLinks {
  /// The fixtures to predict.
  static const String fixtures = 'fixtures';

  /// This week's league table.
  static const String league = 'league';

  /// The in-app inbox.
  static const String inbox = 'inbox';
}

/// The shell tab a push [link] opens, or null for a link this build does
/// not know -- the push then opens the app as a plain tap would.
int? shellTabForLink(String link) => switch (link) {
  PushLinks.fixtures => 1,
  PushLinks.league => 3,
  PushLinks.inbox => 0,
  _ => null,
};
