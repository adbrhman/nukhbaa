/// The bundled crests are drawn at most 34 logical pixels, 102 on a 3x
/// screen, so a crest above 160 pixels or 40 KB is weight no player sees
/// (audit M-34: 339 crests weighed 8.9 MB, most at 500 to 800 pixels). A
/// new crest is resized before it is added; this test is the rule.
///
/// Every bundled crest is also reachable (audit L-09): Al Ahly of Egypt and
/// the Asian national flags were shipped and never shown.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';

/// Width and height from a PNG's IHDR chunk, big-endian at bytes 16 to 23.
(int, int) _pngSize(List<int> bytes) {
  int at(int i) =>
      (bytes[i] << 24) |
      (bytes[i + 1] << 16) |
      (bytes[i + 2] << 8) |
      bytes[i + 3];
  return (at(16), at(20));
}

void main() {
  test('every crest is at most 160 pixels and 40 KB', () {
    final List<String> heavy = <String>[];
    var count = 0;
    for (final FileSystemEntity entity in Directory(
      'assets/team_logos',
    ).listSync()) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      count++;
      final List<int> bytes = entity.readAsBytesSync();
      final (int width, int height) = _pngSize(bytes);
      if (bytes.length > 40 * 1024 || width > 160 || height > 160) {
        heavy.add(
          '${entity.uri.pathSegments.last}: ${width}x$height, '
          '${bytes.length} bytes',
        );
      }
    }
    expect(count, greaterThan(300));
    expect(heavy, isEmpty);
  });

  test('Al Ahly of Egypt and the Asian flags are shown', () {
    expect(teamLogoAssetPath('الأهلي المصري'), 'assets/team_logos/al-ahly.png');
    expect(teamLogoAssetPath('الزمالك'), 'assets/team_logos/zamalek.png');
    expect(teamLogoAssetPath('Japan'), 'assets/team_logos/japan.png');
    expect(teamLogoAssetPath('Palestine'), 'assets/team_logos/palestine.png');
    expect(
      teamLogoAssetPath('South Korea'),
      'assets/team_logos/south-korea.png',
    );
  });
}
