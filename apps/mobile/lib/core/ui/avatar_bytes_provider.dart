/// The bytes behind one profile picture, keyed by the server-relative URL.
library;

import 'dart:async';
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
/// Auto-disposed, then held for two minutes past its last watcher (the shape
/// `fixture_scores_providers.dart` already uses). Kept forever, as it was,
/// every face the user had ever scrolled past stayed decoded in memory for
/// the life of the process -- and a monthly board is the entire user base, at
/// up to 512 KB each. Two minutes is long enough that scrolling a board back
/// and forth re-downloads nothing, and bounded enough that memory cannot grow
/// without end.
///
/// A failure resolves to `null` rather than an error state. A picture that
/// will not load is not worth an error affordance -- the initial is a
/// complete answer -- and the widget treats "no bytes" identically whether
/// the user has no picture or the fetch failed.
final avatarBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, avatarPath) async {
      final link = ref.keepAlive();
      final Timer expiry = Timer(const Duration(minutes: 2), link.close);
      ref.onDispose(expiry.cancel);

      final api = ref.watch(authApiProvider);
      final result = await api.avatarBytes(avatarPath);
      return switch (result) {
        Ok<Uint8List?>(:final value) => value,
        Err<Uint8List?>() => null,
      };
    });
