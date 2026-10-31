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

  /// The player's chat with Nukhbaa support: support answered him
  /// (migration 0187).
  static const String support = 'support';

  /// The admins' support inbox: a player wrote (migration 0187).
  static const String supportInbox = 'support_inbox';

  /// The head-to-head league's tab: an absence warning, a relegation or a
  /// promotion (migration 0189).
  static const String h2h = 'h2h';
}

/// The shell tab a push [link] opens, or null for a link this build does
/// not know -- the push then opens the app as a plain tap would.
int? shellTabForLink(String link) => switch (link) {
  PushLinks.fixtures => 1,
  PushLinks.league => 3,
  PushLinks.inbox => 0,
  // The chat opens on top of the account tab, where its row is.
  PushLinks.support => 4,
  // A player wrote: the admins' inbox over the account tab (script 167).
  PushLinks.supportInbox => 4,
  // The head-to-head league's tab (migration 0189).
  PushLinks.h2h => 2,
  _ => null,
};
