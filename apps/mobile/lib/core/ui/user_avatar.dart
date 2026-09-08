/// The one place a profile picture is drawn.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_tokens.dart';
import 'avatar_bytes_provider.dart';

/// Draws a user's profile picture, falling back to their name's first letter.
///
/// The fallback is not an error state: most users have no picture, and a
/// letter in the app's own colours reads better than a generic silhouette.
///
/// Two details the endpoint forces:
///
/// * The stored `avatar_url` is RELATIVE, because the server sits behind a
///   proxy and cannot know its own public origin, so it is handed to
///   `api_client` verbatim and resolved against the same base every other
///   call already uses.
/// * `GET /users/{id}/avatar` is bearer-gated. The token is NOT attached
///   here: the bytes travel the shared transport, which owns authentication,
///   timeouts and 401 handling for every request the app makes. A widget that
///   reached for the network itself could not authenticate on Flutter web at
///   all, where `Image.network`'s headers are dropped by the browser's own
///   image loader.
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

    // With a ring, the picture is inset by the ring's own thickness, so the
    // drawn diameter is [size] whether or not there is a photo -- a row does
    // not shift when one participant uploads one.
    final double inner = ring == null ? size : size - borderWidth * 2;

    // The bytes come through `api_client`, not from the widget's own network
    // call. `Image.network`'s `headers` are dropped on Flutter web, so the
    // previous version could not authenticate there at all and every picture
    // silently became an initial.
    final Uint8List? bytes = ref.watch(avatarBytesProvider(url)).value;
    if (bytes == null) {
      // Loading, absent and failed all land here on purpose: the initial is a
      // complete answer in every one of those cases, and a spinner in a
      // 34-pixel circle on a scrolling list is noise.
      return outerFallback;
    }

    final Widget picture = ClipOval(
      child: Image.memory(
        bytes,
        width: inner,
        height: inner,
        fit: BoxFit.cover,
        gaplessPlayback: true,
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
  }
}
