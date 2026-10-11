/// Every bundled crest and league mark is a real PNG (2026-10-11): the
/// Newcastle and Coventry City files had been stored as unreadable bytes,
/// so their cards fell back to initials with no error anywhere. A file
/// that is not a PNG now fails here instead of on a player's screen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// The eight bytes every PNG file starts with.
const List<int> _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// Files known to be unreadable and still waiting for a real crest; each
/// one shows initials meanwhile. Remove a name once its crest is replaced.
const Set<String> _awaitingCrest = <String>{};

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
  test('every crest and league mark is a PNG', () {
    final List<String> broken = <String>[];
    for (final String dir in <String>[
      'assets/team_logos',
      'assets/league_logos',
    ]) {
      for (final FileSystemEntity entity in Directory(dir).listSync()) {
        if (entity is! File || !entity.path.endsWith('.png')) continue;
        final String name = entity.uri.pathSegments.last;
        if (_awaitingCrest.contains(name)) continue;
        if (!_isPng(entity)) broken.add('$dir/$name');
      }
    }
    expect(broken, isEmpty);
  });

  test('Newcastle and Coventry City resolve to their replaced crests', () {
    expect(teamLogoAssetPath('نيوكاسل'), 'assets/team_logos/newcastle.png');
    expect(
      teamLogoAssetPath('كوفنتري سيتي'),
      'assets/team_logos/coventry-city.png',
    );
    for (final String slug in <String>['newcastle', 'coventry-city']) {
      expect(_isPng(File('assets/team_logos/$slug.png')), isTrue, reason: slug);
    }
  });
}
