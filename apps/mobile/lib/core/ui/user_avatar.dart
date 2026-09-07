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

  String get _initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final String? url = avatarUrl;

    final Widget fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: gradient ? tokens.primaryGradient : null,
        color: gradient ? null : tokens.surfaceElevated,
        shape: BoxShape.circle,
        border: gradient ? null : Border.all(color: tokens.border),
      ),
      child: Text(
        _initial,
        style: TextStyle(
          color: gradient ? tokens.onPrimary : tokens.textSecondary,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );

    if (url == null) {
      return fallback;
    }

    final AppConfig config = ref.watch(appConfigProvider);
    final TokenStore store = ref.watch(tokenStoreProvider);
    final Uri resolved = config.apiBaseUrl.resolve(
      url.startsWith('/') ? url.substring(1) : url,
    );

    return FutureBuilder<String?>(
      future: store.read(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        if (token == null || token.isEmpty) {
          return fallback;
        }
        return ClipOval(
          child: Image.network(
            resolved.toString(),
            width: size,
            height: size,
            fit: BoxFit.cover,
            headers: <String, String>{'authorization': 'Bearer ' + token},
            // A picture that fails to load is not worth an error affordance:
            // the letter is a complete answer on its own.
            errorBuilder: (_, _, _) => fallback,
          ),
        );
      },
    );
  }
}
