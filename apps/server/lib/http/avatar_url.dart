/// Builds the read URL of a user's profile picture.
library;

import 'package:domain/domain.dart';

/// Returns the relative URL serving [user]'s picture, or null when they have
/// none.
///
/// Relative, not absolute: the server does not know its own public origin
/// (it sits behind a proxy), and the client already holds the API base it
/// used to make this very request. Guessing a host here would be inventing a
/// fact nobody verified.
///
/// The `v` parameter is `avatarUpdatedAt` in epoch milliseconds -- the cache
/// key. A replaced picture is a different URL, so no device can keep serving
/// the old bytes from cache, and an unchanged picture is fetched once and
/// never again.
String? avatarUrlFor(User user) {
  final DateTime? updatedAt = user.avatarUpdatedAt;
  if (user.avatarMime == null || updatedAt == null) {
    return null;
  }
  return avatarUrlOf(userId: user.id, updatedAt: updatedAt);
}

/// Builds the same URL from the two facts it actually needs, for callers that
/// hold those facts without holding a whole [User] -- a leaderboard row, for
/// one, which never loads the users it ranks.
///
/// One function so the shape exists once: if the route ever moves, every
/// picture on the platform moves with it, instead of the board quietly keeping
/// a hand-built string that used to be right.
String avatarUrlOf({required UserId userId, required DateTime updatedAt}) =>
    '/users/${userId.value}/avatar'
    '?v=${updatedAt.toUtc().millisecondsSinceEpoch}';
