/// Profile pictures kept on the phone between visits and launches (audit
/// M-35).
///
/// The server answers a picture with `max-age=31536000, immutable` and its
/// URL carries `?v=` (the upload time), but the app fetches the bytes
/// through `api_client`, which has no disk cache: every board or group
/// opened after the two-minute memory hold, and every launch, downloaded
/// every face again. On Android the bytes are now kept in the app's cache
/// folder, keyed by the whole URL, so a replaced picture is a new file and
/// an old face never comes back. On the web the browser's own cache already
/// honours the server's header, so nothing is kept here.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar_disk_cache_stub.dart'
    if (dart.library.io) 'avatar_disk_cache_io.dart'
    as impl;

/// The pictures kept on this device. Never throws: a cache that cannot read
/// or write only means the picture is downloaded, as before.
abstract interface class AvatarDiskCache {
  /// The bytes kept for [url], or null.
  Future<Uint8List?> read(String url);

  /// Keeps [bytes] for [url].
  Future<void> write(String url, Uint8List bytes);
}

/// Keeps nothing: the web, and tests.
final class NoAvatarDiskCache implements AvatarDiskCache {
  /// Creates the cache that keeps nothing.
  const NoAvatarDiskCache();

  @override
  Future<Uint8List?> read(String url) async => null;

  @override
  Future<void> write(String url, Uint8List bytes) async {}
}

/// This device's picture cache.
final avatarDiskCacheProvider = Provider<AvatarDiskCache>(
  (ref) => impl.platformAvatarDiskCache(),
);
