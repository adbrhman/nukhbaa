/// Every flag shipped with the app is a real PNG (2026-10-11): the
/// Newcastle and Coventry City files had been stored as unreadable bytes,
/// so their cards fell back to initials with no error anywhere. A file
/// that is not a PNG now fails here instead of on a player's screen. The
/// clubs' crests no longer ship (script 266): the server's list holds them,
/// and the app keeps a downloaded file only once it reads as a PNG.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// The eight bytes every PNG file starts with.
const List<int> _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

bool _isPng(File file) {
  final RandomAccessFile raf = file.openSync();
  final List<int> head;
  try {
    head = raf.readSync(8);
  } finally {
    raf.closeSync();
  }
  if (head.length < 8) return false;
  for (var i = 0; i < 8; i++) {
    if (head[i] != _pngSignature[i]) return false;
  }
  return true;
}

void main() {
  test('every flag is a PNG', () {
    final List<String> broken = <String>[];
    for (final FileSystemEntity entity in Directory(
      'assets/flags',
    ).listSync()) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      if (!_isPng(entity)) broken.add(entity.uri.pathSegments.last);
    }
    expect(broken, isEmpty);
  });

  test('Newcastle and Coventry City resolve to their crests', () {
    expect(teamCrestSlug('نيوكاسل'), 'newcastle');
    expect(teamCrestSlug('كوفنتري سيتي'), 'coventry-city');
  });
}
