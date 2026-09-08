/// The one place a profile picture is drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../design/app_tokens.dart';
import '../providers.dart';

/// Draws a user's profile picture, falling back to their name's first letter.
///
/// The fallback is not an error state: most users have no picture, and a
/// letter in the app's own colours reads better than a generic silhouette.
///
/// Two details the endpoint forces:
///
/// * The stored `avatar_url` is RELATIVE, because the server sits behind a
///   proxy and cannot know its own public origin. It is resolved here against
///   the same base the app already uses for every other call.
/// * `GET /users/{id}/avatar` is bearer-gated, so the request needs the
///   token. It is read once per URL rather than held, so a sign-out cannot
///   leave a stale credential attached to an image request.
class UserAvatar extends ConsumerWidget {
  /// Creates an avatar for [displayName], showing [avatarUrl] when present.
  const UserAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.size,
    this.gradient = true,
    this.borderColor,
    this.borderWidth = 1,
    super.key,
  });

  /// The name whose first letter is the fallback.
  final String displayName;

  /// The server-relative picture URL, or null when there is none.
  final String? avatarUrl;

  /// Diameter in logical pixels.
  final double size;

  /// Whether the fallback circle uses the primary gradient (the account
  /// header) or a flat elevated surface (leaderboard rows).
  final bool gradient;

  /// An explicit ring colour, drawn around the picture AND the fallback alike
  /// so a row does not change shape the moment a user uploads a photo. The
  /// podium passes its medal colour here. Null keeps the default: a hairline
  /// border on the flat fallback, none on the gradient one.
  final Color? borderColor;

  /// The ring's thickness. The picture is inset by it, so the drawn diameter
  /// stays [size] whether or not there is a photo.
  final double borderWidth;

  String get _initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  /// The letter circle, drawn at [diameter]. [withRing] is false for the
  /// copy that sits INSIDE a ring container, so a failed image never draws a
  /// second border or overflows the ring it is nested in.
  Widget _fallback(BuildContext context, double diameter, bool withRing) {
    final AppTokens tokens = context.tokens;
    final Color? ring = withRing ? borderColor : null;
    final bool plain = gradient && ring == null && withRing;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: plain ? tokens.primaryGradient : null,
        color: plain ? null : tokens.surfaceElevated,
        shape: BoxShape.circle,
        border: !withRing
            ? null
            : (plain
                  ? null
                  : Border.all(
                      color: ring ?? tokens.border,
                      width: borderWidth,
                    )),
      ),
      child: Text(
        _initial,
        style: TextStyle(
          color: plain ? tokens.onPrimary : tokens.textSecondary,
          fontWeight: FontWeight.bold,
          fontSize: diameter * 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? url = avatarUrl;
    final Color? ring = borderColor;
    final Widget outerFallback = _fallback(context, size, true);

    if (url == null) {
      return outerFallback;
    }

    final AppConfig config = ref.watch(appConfigProvider);
    final TokenStore store = ref.watch(tokenStoreProvider);
    final Uri resolved = config.apiBaseUrl.resolve(
      url.startsWith('/') ? url.substring(1) : url,
    );
    // With a ring, the picture is inset by the ring's own thickness, so the
    // drawn diameter is [size] whether or not there is a photo -- a row does
    // not shift when one participant uploads one.
    final double inner = ring == null ? size : size - borderWidth * 2;

    return FutureBuilder<String?>(
      future: store.read(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        if (token == null || token.isEmpty) {
          return outerFallback;
        }
        final Widget picture = ClipOval(
          child: Image.network(
            resolved.toString(),
            width: inner,
            height: inner,
            fit: BoxFit.cover,
            headers: <String, String>{'authorization': 'Bearer $token'},
            // A picture that fails to load is not worth an error affordance:
            // the letter is a complete answer on its own.
            errorBuilder: (_, _, _) => _fallback(context, inner, ring == null),
          ),
        );
        if (ring == null) {
          return picture;
        }
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: borderWidth),
          ),
          child: picture,
        );
      },
    );
  }
}
