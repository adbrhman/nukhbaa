/// [AvatarDiskCache] over a folder in the app's cache directory.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'avatar_disk_cache.dart';

/// The cache in the app's temporary folder, or none under `flutter test`,
/// where every test must start from the same empty state.
AvatarDiskCache platformAvatarDiskCache() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return const NoAvatarDiskCache();
  }
  return FileAvatarDiskCache(
    Directory('${Directory.systemTemp.path}/nukhba_avatars'),
  );
}

/// One file per picture URL in [folder]; when the folder holds more than
/// [maxBytes], the least recently written files go until it holds
/// [keepBytes]. The system may also clear the cache folder at any time,
/// which only costs a download.
final class FileAvatarDiskCache implements AvatarDiskCache {
  /// Creates the cache over [folder].
  FileAvatarDiskCache(
    this.folder, {
    this.maxBytes = 20 * 1024 * 1024,
    this.keepBytes = 15 * 1024 * 1024,
  });

  /// Where the pictures are kept.
  final Directory folder;

  /// The size above which old pictures are removed.
  final int maxBytes;

  /// The size the folder is brought back to.
  final int keepBytes;

  File _fileFor(String url) =>
      File('${folder.path}/${base64Url.encode(utf8.encode(url))}');

  @override
  Future<Uint8List?> read(String url) async {
    try {
      final File file = _fileFor(url);
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String url, Uint8List bytes) async {
    try {
      if (!folder.existsSync()) {
        folder.createSync(recursive: true);
      }
      await _fileFor(url).writeAsBytes(bytes, flush: true);
      _trim();
    } on Object {
      // The picture is downloaded again next time; nothing depends on it.
    }
  }

  void _trim() {
    final List<File> files = folder.listSync().whereType<File>().toList();
    var total = 0;
    final Map<File, (int, DateTime)> facts = <File, (int, DateTime)>{};
    for (final File file in files) {
      final FileStat stat = file.statSync();
      facts[file] = (stat.size, stat.modified);
      total += stat.size;
    }
    if (total <= maxBytes) {
      return;
    }
    files.sort((File a, File b) => facts[a]!.$2.compareTo(facts[b]!.$2));
    for (final File file in files) {
      if (total <= keepBytes) {
        break;
      }
      total -= facts[file]!.$1;
      file.deleteSync();
    }
  }
}
