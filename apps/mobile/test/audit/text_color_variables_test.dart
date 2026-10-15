/// A text colour named through a variable or a helper: the colour audit
/// (CA-08) found invitation states, frame verdicts and medal places drawn
/// in fill tokens by way of `final Color x = ...` or `Color f() => ...`,
/// which text_color_tokens_test.dart does not follow. This reads every file
/// under lib/ for a `Color` variable or arrow function whose value names a
/// fill token and fails where a `TextStyle`, a `TextSpan` or a `copyWith`
/// takes its `color:` from one; the same name may still colour an icon, a
/// rim or a fill.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

final RegExp _fillToken = RegExp(
  r'\b(?:tokens|t)\.(?:error|success|primary|primaryLight|goldAccent|silver|bronze)\b'
  r'|\b(?:scheme|colorScheme)\.(?:primary|error|secondary)\b',
);
final RegExp _colorVariable = RegExp(r'\bColor\??\s+(\w+)\s*=(?!=)');
final RegExp _colorFunction = RegExp(r'\bColor\??\s+(\w+)\s*\([^()]*\)\s*=>');
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

/// Where the statement starting at [start] ends: the next semicolon, or
/// the closing bracket, at its own depth.
int _statementEnd(String code, int start) {
  int depth = 0;
  int i = start;
  while (i < code.length) {
    final String c = code[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
    } else if (c == ';' && depth == 0) {
      break;
    }
    i++;
  }
  return i;
}

/// Every text colour in [source] taken from a variable or an arrow
/// function whose value names a fill token, as `path:line  expression`.
List<String> _textInFillVariables(String path, String source) {
  final String code = _code(source);
  final Map<String, bool> named = <String, bool>{};
  for (final (RegExp pattern, bool isFunction) in <(RegExp, bool)>[
    (_colorVariable, false),
    (_colorFunction, true),
  ]) {
    for (final RegExpMatch m in pattern.allMatches(code)) {
      final String value = code.substring(m.end, _statementEnd(code, m.end));
      if (_fillToken.hasMatch(value)) named[m.group(1)!] = isFunction;
    }
  }
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
    for (final MapEntry<String, bool> name in named.entries) {
      final RegExp use = RegExp(
        '\\b${RegExp.escape(name.key)}${name.value ? r'\s*\(' : r'\b'}',
      );
      if (!use.hasMatch(expression)) continue;
      final int line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
      found.add(
        '$path:$line  ${expression.trim().replaceAll(RegExp(r'\s+'), ' ')}',
      );
      break;
    }
  }
  return found;
}

void main() {
  test('the check follows a colour through a variable or a helper', () {
    expect(
      _textInFillVariables('a.dart', '''
final Color a = ok ? t.success : t.textMuted;
Text('x', style: TextStyle(color: a));
Color verdict(double v) => v > 1 ? t.error : t.textPrimary;
Text('y', style: s.copyWith(color: verdict(2)));
final Color b = t.primary;
Icon(Icons.add, color: b);
final Color c = t.errorText;
Text('z', style: TextStyle(color: c));
'''),
      <String>['a.dart:2  a', 'a.dart:4  verdict(2)'],
    );
  });

  test('no text under lib/ takes a fill colour through a variable', () {
    final List<String> found = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path;
      if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
      found.addAll(_textInFillVariables(path, entity.readAsStringSync()));
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
