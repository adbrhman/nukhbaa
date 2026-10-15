/// A button's label is drawn in its foreground colour. The colour audit
/// found buttons labelled in fill tokens that miss 4.5:1 in the dark theme
/// (the admin's outlined button, 2026-10-15); text_color_tokens_test.dart
/// guards `TextStyle`, `TextSpan` and `copyWith`, and this reads every file
/// under lib/ for a `styleFrom(foregroundColor:)` naming a fill token.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

final RegExp _fillToken = RegExp(
  r'\b(?:tokens|t)\.(?:error|success|primary|primaryLight|goldAccent|silver|bronze)\b'
  r'|\b(?:scheme|colorScheme)\.(?:primary|error|secondary)\b',
);
final RegExp _foregroundArg = RegExp(r'\bforegroundColor\s*:');
final RegExp _callName = RegExp(r'([A-Za-z_][\w.]*)\s*(<[^>]*>)?\s*$');
final RegExp _notNewline = RegExp(r'[^\n]');

/// [source] with comments and string literals blanked to spaces, so a
/// bracket or a token name inside either cannot be mistaken for code; line
/// breaks stay where they were.
String _code(String source) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final int end = source.indexOf('\n', i);
      final int stop = end < 0 ? source.length : end;
      out.write(' ' * (stop - i));
      i = stop;
    } else if (source.startsWith('/*', i)) {
      final int end = source.indexOf('*/', i + 2);
      final int stop = end < 0 ? source.length : end + 2;
      out.write(source.substring(i, stop).replaceAll(_notNewline, ' '));
      i = stop;
    } else if (source[i] == "'" || source[i] == '"') {
      final String quote = source[i];
      final String close = source.startsWith(quote * 3, i) ? quote * 3 : quote;
      int j = i + close.length;
      while (j < source.length && !source.startsWith(close, j)) {
        if (source[j] == r'\') j++;
        j++;
      }
      final int stop = math.min(j + close.length, source.length);
      out.write(source.substring(i, stop).replaceAll(_notNewline, ' '));
      i = stop;
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

/// The name of the call whose argument list holds [at]: `TextStyle`,
/// `copyWith`, `BoxDecoration`...; null at the top level.
String? _enclosingCall(String code, int at) {
  int depth = 0;
  for (int i = at - 1; i >= 0; i--) {
    final String c = code[i];
    if (c == ')' || c == ']' || c == '}') {
      depth++;
    } else if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) {
        final String head = code.substring(math.max(0, i - 80), i);
        return _callName.firstMatch(head)?.group(1);
      }
      depth--;
    }
  }
  return null;
}

/// Where the argument starting at [start] ends: the next comma or closing
/// bracket at its own depth.
int _argumentEnd(String code, int start) {
  int depth = 0;
  int i = start;
  while (i < code.length) {
    final String c = code[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
    } else if (c == ',' && depth == 0) {
      break;
    }
    i++;
  }
  return i;
}

/// Every button label in [source] that names a fill token, as
/// `path:line  expression`.
List<String> _labelsInFillColours(String path, String source) {
  final String code = _code(source);
  final List<String> found = <String>[];
  for (final RegExpMatch m in _foregroundArg.allMatches(code)) {
    final String? call = _enclosingCall(code, m.start);
    if (call == null || !call.endsWith('styleFrom')) continue;
    final String expression = code.substring(m.end, _argumentEnd(code, m.end));
    if (_fillToken.hasMatch(expression)) {
      final int line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
      found.add(
        '$path:$line  ${expression.trim().replaceAll(RegExp(r'\s+'), ' ')}',
      );
    }
  }
  return found;
}

void main() {
  test('the check finds a button label in a fill colour, and only that', () {
    expect(
      _labelsInFillColours('a.dart', '''
OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: t.primary));
FilledButton(
  style: FilledButton.styleFrom(
    backgroundColor: tokens.primary,
    foregroundColor: tokens.onPrimary,
  ),
);
TextButton(style: TextButton.styleFrom(foregroundColor: tokens.errorText));
// styleFrom(foregroundColor: tokens.error) in a comment
'''),
      <String>['a.dart:1  t.primary'],
    );
  });

  test('no button under lib/ is labelled in a fill colour', () {
    final List<String> found = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path;
      if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
      found.addAll(_labelsInFillColours(path, entity.readAsStringSync()));
    }
    expect(
      found,
      isEmpty,
      reason:
          'use primaryText, errorText or successText for a label:\n'
          '${found.join('\n')}',
    );
  });
}
