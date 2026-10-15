/// The web has no folder to keep pictures in; the browser caches them.
library;

import 'avatar_disk_cache.dart';

/// Keeps nothing.
AvatarDiskCache platformAvatarDiskCache() => const NoAvatarDiskCache();
