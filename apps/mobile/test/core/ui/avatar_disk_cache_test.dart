/// Profile pictures kept on the phone (audit M-35): a picture written is
/// read back by its whole URL, another version of the same picture is a
/// different file, and the folder is trimmed, oldest first, once it grows
/// past its limit.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/avatar_disk_cache.dart';
import 'package:mobile/core/ui/avatar_disk_cache_io.dart';

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('avatar_cache_test');
  });

  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  test('a picture written is read back by its whole URL', () async {
    final FileAvatarDiskCache cache = FileAvatarDiskCache(folder);
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);

    expect(await cache.read('/users/u1/avatar?v=1'), isNull);
    await cache.write('/users/u1/avatar?v=1', bytes);

    expect(await cache.read('/users/u1/avatar?v=1'), bytes);
    expect(
      await cache.read('/users/u1/avatar?v=2'),
      isNull,
      reason: 'a replaced picture is a new URL, never the old face',
    );
  });

  test('past its limit the folder loses its oldest pictures', () async {
    final FileAvatarDiskCache cache = FileAvatarDiskCache(
      folder,
      maxBytes: 25,
      keepBytes: 15,
    );
    final Uint8List ten = Uint8List(10);

    File fileOf(String url) =>
        File('${folder.path}/${base64Url.encode(utf8.encode(url))}');
    await cache.write('/a', ten);
    await cache.write('/b', ten);
    fileOf('/a').setLastModifiedSync(DateTime(2020));
    fileOf('/b').setLastModifiedSync(DateTime(2021));
    await cache.write('/c', ten);

    expect(await cache.read('/a'), isNull, reason: 'the oldest went first');
    expect(await cache.read('/b'), isNull, reason: 'then the next oldest');
    expect(await cache.read('/c'), isNotNull, reason: 'down to 15 bytes');
  });

  test('a folder that cannot be written is no error', () async {
    final File notAFolder = File('${folder.path}/file')..writeAsStringSync('x');
    final FileAvatarDiskCache cache = FileAvatarDiskCache(
      Directory(notAFolder.path),
    );

    await cache.write('/a', Uint8List(1));

    expect(await cache.read('/a'), isNull);
  });

  test('under flutter test nothing is kept', () {
    expect(platformAvatarDiskCache(), isA<NoAvatarDiskCache>());
  });
}
