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

  /// The duels page; `duel:CODE` opens that challenge (migration 0092).
  static const String duel = 'duel';
}

/// The challenge code a `duel:CODE` push carries, or null.
String? duelCodeForLink(String link) {
  const String prefix = '${PushLinks.duel}:';
  if (!link.startsWith(prefix)) return null;
  final String code = link.substring(prefix.length).trim();
  return code.isEmpty ? null : code;
}

/// The name a tapped push is counted under (P3-8): a challenge counts as
/// a duel push; its code is not reported.
String pushOpenNameForLink(String link) =>
    duelCodeForLink(link) == null ? link : PushLinks.duel;

/// The shell tab a push [link] opens, or null for a link this build does
/// not know -- the push then opens the app as a plain tap would.
int? shellTabForLink(String link) => switch (link) {
  PushLinks.fixtures => 1,
  PushLinks.league => 3,
  PushLinks.inbox => 0,
  PushLinks.duel => 0,
  _ when duelCodeForLink(link) != null => 0,
  _ => null,
};
