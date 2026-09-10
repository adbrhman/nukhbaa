#!/usr/bin/env python3
"""Profile pictures never render, anywhere -- not on the account screen, not
on the leaderboard -- even for a user whose picture IS stored (the avatar
sheet offers "delete photo", which only appears when the server returned an
avatar_url).

Cause: `UserAvatar` fetched the image with `Image.network(..., headers: {...})`.
That is a raw HTTP request issued from the widget layer, which is exactly what
ADR-002 2.8 forbids -- "the app performs NO direct HTTP; api_client owns every
request" -- and the boundary is not decorative here. On Flutter web the image
is loaded by the browser's own <img> pipeline, which cannot carry an
Authorization header at all, so a bearer-gated GET /users/{id}/avatar arrives
unauthenticated and 401s. The widget's errorBuilder then draws the initial,
which is indistinguishable from "this user has no picture" -- which is why
this looked like a missing-data bug for days.

Fix: fetch the bytes through the same transport as every other call and render
them from memory. Authentication, timeout, and 401 handling become the shared
pipeline's job, as they already are for every other request the app makes.
"""
import os
import sys

ROOT = os.path.abspath(os.path.dirname(__file__))


def create(rel, body):
    path = os.path.join(ROOT, rel)
    if os.path.isfile(path):
        if open(path, encoding="utf-8").read() == body:
            print("  skip   " + rel + " (already written)")
            return
        sys.exit("EXISTS with different content: " + rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(body)
    print("  new    " + rel)


def patch(rel, pairs):
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        sys.exit("MISSING: " + rel)
    src = open(path, encoding="utf-8").read()
    for i, (old, new) in enumerate(pairs, 1):
        if new in src and old not in src:
            print("  skip   %s [%d] (already applied)" % (rel, i))
            continue
        if src.count(old) != 1:
            sys.exit("ANCHOR x%d in %s [edit %d]" % (src.count(old), rel, i))
        src = src.replace(old, new, 1)
    open(path, "w", encoding="utf-8").write(src)
    print("  ok     " + rel)


# ---------------------------------------------------------------------------
# 1. Transport: one raw send, reused by the JSON path and the bytes path.
# ---------------------------------------------------------------------------
patch("packages/api_client/lib/src/api_transport.dart", [
(
    """  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    List<int>? requestBytes,
    String? requestContentType,
    required Result<T> Function(String body) decode,
  }) async {
    final uri = _resolve(path, query);""",
    """  /// `GET` returning raw bytes rather than JSON -- the one response on this
  /// platform that is not a document: `GET /users/{id}/avatar`.
  ///
  /// `Ok(null)` for `404`, because a user with no stored picture is not an
  /// error; the caller draws their initial. Every other status goes through
  /// the shared error decoding, and a `401` still triggers the shared
  /// unauthorized hook, so an expired session logs out here exactly as it
  /// does on any other call.
  ///
  /// This exists so images travel the same authenticated pipeline as
  /// everything else. `Image.network`'s `headers` argument is silently
  /// dropped on Flutter web (the browser's own `<img>` loader fetches the
  /// URL), so a widget that reached for the network directly could not
  /// authenticate at all there.
  Future<Result<Uint8List?>> getBytes(String path) async {
    final sent = await _rawSend(method: 'GET', path: path);
    if (sent is Err<http.Response>) return Result.err(sent.error);
    final response = (sent as Ok<http.Response>).value;
    final status = response.statusCode;
    if (status == 404) return const Result.ok(null);
    if (status >= 200 && status < 300) return Result.ok(response.bodyBytes);
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
  }

  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    List<int>? requestBytes,
    String? requestContentType,
    required Result<T> Function(String body) decode,
  }) async {
    final sent = await _rawSend(
      method: method,
      path: path,
      query: query,
      requestBody: requestBody,
      requestBytes: requestBytes,
      requestContentType: requestContentType,
    );
    if (sent is Err<http.Response>) return Result.err(sent.error);
    final response = (sent as Ok<http.Response>).value;

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return decode(response.body);
    }
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
  }

  // The wire itself: URL, headers, method, timeout. Status interpretation is
  // deliberately NOT here -- a bytes response and a JSON response disagree
  // about what 404 means, and folding that into the sender would force one of
  // them to lie.
  Future<Result<http.Response>> _rawSend({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    List<int>? requestBytes,
    String? requestContentType,
  }) async {
    final uri = _resolve(path, query);""",
), (
    """      return Result.err(networkError(cause));
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return decode(response.body);
    }
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
  }

  Uri _resolve(String path, Map<String, String>? query) {""",
    """      return Result.err(networkError(cause));
    }

    return Result.ok(response);
  }

  Uri _resolve(String path, Map<String, String>? query) {""",
), (
    "import 'dart:convert';\n",
    "import 'dart:convert';\nimport 'dart:typed_data';\n",
)])

# ---------------------------------------------------------------------------
# 2. The read itself
# ---------------------------------------------------------------------------
patch("packages/api_client/lib/src/auth_api.dart", [(
    """  /// `DELETE /me/avatar` — removes the caller's picture, if any.""",
    """  /// `GET /users/{id}/avatar` — the stored picture's bytes, for any user.
  ///
  /// [avatarPath] is the server-relative URL the server already built and put
  /// on the DTO (`avatar_url`), passed back verbatim rather than rebuilt
  /// here: the route shape is the server's to own, and the `?v=` version in
  /// it is what makes a replaced picture a different resource.
  ///
  /// `Ok(null)` when the user has no picture — the caller draws their initial.
  Future<Result<Uint8List?>> avatarBytes(String avatarPath) {
    return _transport.getBytes(avatarPath);
  }

  /// `DELETE /me/avatar` — removes the caller's picture, if any.""",
), (
    "import 'package:api_client/src/api_transport.dart';\n",
    "import 'dart:typed_data';\n\nimport 'package:api_client/src/api_transport.dart';\n",
)])

# ---------------------------------------------------------------------------
# 3. A provider keyed by the URL, so a board of 30 rows fetches each face once
# ---------------------------------------------------------------------------
create("apps/mobile/lib/core/ui/avatar_bytes_provider.dart", '''/// The bytes behind one profile picture, keyed by the server-relative URL.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../providers.dart';

/// Fetches [avatarPath] through `api_client` and caches it by URL.
///
/// Keyed by the whole URL, `?v=` included, which is what makes caching safe:
/// a replaced picture has a different version and therefore a different
/// provider instance, so a stale face cannot survive an upload. Two rows
/// showing the same person on one leaderboard share one fetch.
///
/// Not auto-disposed, deliberately: scrolling a board back and forth would
/// otherwise re-download every face each time it left the viewport.
///
/// A failure resolves to `null` rather than an error state. A picture that
/// will not load is not worth an error affordance -- the initial is a
/// complete answer -- and the widget treats "no bytes" identically whether
/// the user has no picture or the fetch failed.
final avatarBytesProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  avatarPath,
) async {
  final api = ref.watch(authApiProvider);
  final result = await api.avatarBytes(avatarPath);
  return switch (result) {
    Ok<Uint8List?>(:final value) => value,
    Err<Uint8List?>() => null,
  };
});
''')

# ---------------------------------------------------------------------------
# 4. The widget renders from memory
# ---------------------------------------------------------------------------
patch("apps/mobile/lib/core/ui/user_avatar.dart", [
(
    """  @override
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
  }""",
    """  @override
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
    final Uint8List? bytes = ref.watch(avatarBytesProvider(url)).valueOrNull;
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
  }""",
), (
    """///   proxy and cannot know its own public origin. It is resolved here against
///   the same base the app already uses for every other call.
/// * `GET /users/{id}/avatar` is bearer-gated, so the request needs the
///   token. It is read once per URL rather than held, so a sign-out cannot
///   leave a stale credential attached to an image request.""",
    """///   proxy and cannot know its own public origin, so it is handed to
///   `api_client` verbatim and resolved against the same base every other
///   call already uses.
/// * `GET /users/{id}/avatar` is bearer-gated. The token is NOT attached
///   here: the bytes travel the shared transport, which owns authentication,
///   timeouts and 401 handling for every request the app makes. A widget that
///   reached for the network itself could not authenticate on Flutter web at
///   all, where `Image.network`'s headers are dropped by the browser's own
///   image loader.""",
), (
    """import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../design/app_tokens.dart';
import '../providers.dart';""",
    """import '../design/app_tokens.dart';
import 'avatar_bytes_provider.dart';""",
)])

print("all patches applied")
