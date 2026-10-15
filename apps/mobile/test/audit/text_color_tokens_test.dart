/// Text is drawn in a text colour. [AppTokens] keeps fill and icon colours
/// (`error`, `success`, `primary`, `primaryLight`, `goldAccent`, `silver`,
/// `bronze`) that miss 4.5:1 on some surface of one theme, and the text
/// shades made for them (`errorText`, `successText`, `primaryText`, `gold`)
/// that reach it everywhere (app_theme_components_contrast_test.dart). The
/// colour audit of 2026-10-15 found 38 texts in a fill colour; this reads
/// every file under lib/ and fails on a `TextStyle`, a `TextSpan` or a
/// `copyWith` whose `color:` names one, so none comes back.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

final RegExp _fillToken = RegExp(
  r'\b(?:tokens|t)\.(?:error|success|primary|primaryLight|goldAccent|silver|bronze)\b'
  r'|\b(?:scheme|colorScheme)\.(?:primary|error|secondary)\b',
);
final RegExp _colorArg = RegExp(r'\bcolor\s*:');
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

/// Every text colour in [source] that names a fill token, as
/// `path:line  expression`.
List<String> _textInFillColours(String path, String source) {
  final String code = _code(source);
  final List<String> found = <String>[];
  for (final RegExpMatch m in _colorArg.allMatches(code)) {
    final String? call = _enclosingCall(code, m.start);
    if (call == null) continue;
    if (call != 'TextStyle' &&
        call != 'TextSpan' &&
        !call.endsWith('copyWith')) {
      continue;
    }
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
  test('the check finds a text in a fill colour, and only that', () {
    expect(
      _textInFillColours('a.dart', '''
Text('x', style: TextStyle(color: tokens.error));
Text('y', style: text.bodySmall?.copyWith(
  fontWeight: FontWeight.w700,
  color: ok ? t.success : t.textMuted,
));
Icon(Icons.close, color: tokens.error);
Container(decoration: BoxDecoration(color: tokens.primary));
// TextStyle(color: tokens.error) in a comment
Text('z', style: TextStyle(color: tokens.errorText));
Text('w', style: TextStyle(color: t.primaryText));
'''),
      <String>[
        'a.dart:1  tokens.error',
        'a.dart:4  ok ? t.success : t.textMuted',
      ],
    );
  });

  test('no text under lib/ is drawn in a fill colour', () {
    final List<String> found = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path;
      if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
      found.addAll(_textInFillColours(path, entity.readAsStringSync()));
    }
    expect(
      found,
      isEmpty,
      reason:
          'use errorText, successText, primaryText or gold for text:\n'
          '${found.join('\n')}',
    );
  });
}
