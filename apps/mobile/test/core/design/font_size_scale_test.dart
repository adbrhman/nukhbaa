/// Every font size in the app comes from the type scale: the Material roles
/// in `AppTypography.textTheme`, or a named step of `AppFontSize`. A bare
/// number after `fontSize:` -- or inside a ternary there -- is a size the
/// design system does not know about. Sizes derived from a widget's own
/// geometry (`diameter * 0.4`) are not bare numbers and stay allowed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _bare = RegExp(r'fontSize:\s*\d|fontSize:[^,\n]*\?\s*\d');

void main() {
  test('no bare font size outside the type scale', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      final String path = entity.path.replaceAll(r'\', '/');
      if (entity is! File || !path.endsWith('.dart')) continue;
      if (path.startsWith('lib/l10n/')) continue;
      if (path.endsWith('core/design/app_typography.dart')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (_bare.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
