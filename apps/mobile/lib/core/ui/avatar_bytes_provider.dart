/// The bytes behind one profile picture, keyed by the server-relative URL.
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
