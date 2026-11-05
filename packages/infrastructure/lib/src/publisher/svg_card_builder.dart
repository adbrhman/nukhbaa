import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';

/// Writes a publisher picture as SVG, for resvg to draw (pure).
///
/// 1080x1350 (4:5, as Instagram and Facebook show a portrait picture whole),
/// Nukhba's navy with its blue and its mark, each club a disc of its colour
/// with its name (no crest: decided by the owner on 2026-11-04).
///
/// resvg anchors a text by its own left and right whatever its direction,
/// and reorders `45+2` inside an Arabic run, so every number is a text of
/// its own, left to right, and every Arabic text is placed by the edge it
/// should stand on (`end` is its right edge).
final class SvgCardBuilder {
  const SvgCardBuilder._();

  /// Width in pixels.
  static const int width = 1080;

  /// Height in pixels.
  static const int height = 1350;

  /// The font the pictures are written in (bundled with the server).
  static const String font = 'IBM Plex Sans Arabic';

  static const String _navy = '#071426';
  static const String _navyTop = '#0B2A4A';
  static const String _blue = '#1978D1';
  static const String _sky = '#A8D3FF';
  static const String _white = '#FFFFFF';

  /// Nukhba's mark on its 2048-pixel canvas (the owner's file of
  /// 2026-11-04, traced: 99.4% of its pixels).
  static String _mark(String fill) =>
      '<polygon points="150,704 150,1420 437,1420 437,990 591,1420 '
      '1899,1420 1899,704 1610,704 1610,1245 806,1245 585,704" '
      'fill="$fill"/><circle cx="1121" cy="753" r="127.5" fill="$fill"/>';

  /// The SVG of [spec].
  static String build(CardSpec spec) => switch (spec.kind) {
    CardKind.goal => _frame(_goal(spec)),
    CardKind.finalResult => _frame(_final(spec)),
  };

  static String _goal(CardSpec spec) {
    final out = StringBuffer()
      ..write(_text(540, 270, clip(spec.league, 34), 42, _sky, weight: 600))
      ..write(_text(540, 400, spec.headline, 104, _white))
      ..write(_teams(spec, 620))
      ..write(
        '<rect x="140" y="930" width="800" height="230" rx="36" '
        'fill="$_blue"/>',
      );
    final side = spec.scoringHome == false ? spec.awayName : spec.homeName;
    out.write(_text(540, 1020, clip(spec.scorer ?? side, 28), 58, _white));
    final minute = spec.minuteLabel;
    if (minute != null && minute.isNotEmpty) {
      out
        ..write(
          _text(556, 1110, 'الدقيقة', 44, _sky, weight: 600, anchor: 'start'),
        )
        ..write(
          _text(
            540,
            1110,
            "$minute'",
            50,
            _white,
            anchor: 'end',
            direction: 'ltr',
          ),
        );
    }
    return out.toString();
  }

  static String _final(CardSpec spec) {
    final out = StringBuffer()
      ..write(_text(540, 270, clip(spec.league, 34), 42, _sky, weight: 600))
      ..write(_text(540, 400, spec.headline, 96, _white))
      ..write(_teams(spec, 620));
    final verdict = spec.verdict;
    if (verdict != null) {
      out.write(_text(540, 980, verdict, 56, _sky));
    }
    final columns = <(List<String>, int)>[
      (spec.homeScorers, 1000),
      (spec.awayScorers, 480),
    ];
    for (final (items, right) in columns) {
      for (var i = 0; i < items.length && i < 4; i++) {
        final y = 1060 + i * 52;
        if (i == 3 && items.length > 4) {
          out.write(
            _text(right, y, '…', 36, _white, weight: 500, anchor: 'end'),
          );
          continue;
        }
        final parts = items[i].split('|');
        final name = parts.first;
        final minute = parts.length > 1 ? parts[1] : '';
        out.write(
          _text(
            right,
            y,
            clip(name, 16),
            36,
            _white,
            weight: 500,
            anchor: 'end',
          ),
        );
        if (minute.isNotEmpty) {
          out.write(
            _text(
              right - 320,
              y,
              "$minute'",
              36,
              _sky,
              weight: 600,
              anchor: 'end',
              direction: 'ltr',
            ),
          );
        }
      }
    }
    return out.toString();
  }

  /// The two discs, the names under them and the score between them: the
  /// home side on the right, as an Arabic reader reads first.
  static String _teams(CardSpec spec, int y) {
    final out = StringBuffer()
      ..write(_badge(830, y, spec.homeBadge, spec.homeCrest))
      ..write(_badge(250, y, spec.awayBadge, spec.awayCrest))
      ..write(
        _text(830, y + 200, clip(spec.homeName, 18), 44, _white, weight: 600),
      )
      ..write(
        _text(250, y + 200, clip(spec.awayName, 18), 44, _white, weight: 600),
      )
      ..write(
        _text(640, y + 62, '${spec.score.home}', 180, _white, direction: 'ltr'),
      )
      ..write(_text(540, y + 50, '-', 120, _sky, direction: 'ltr'))
      ..write(
        _text(440, y + 62, '${spec.score.away}', 180, _white, direction: 'ltr'),
      );
    return out.toString();
  }

  /// The club's official crest (PNG bytes) on a white disc: the crests are
  /// drawn for a light ground, and a dark one would vanish on the navy.
  /// The picture is embedded as a data URI, so resvg reads no file.
  static String _crestDisc(int cx, int cy, List<int> png) {
    const box = 190;
    final left = cx - box ~/ 2;
    final top = cy - box ~/ 2;
    return '<circle cx="$cx" cy="$cy" r="132" fill="$_white" '
        'stroke="$_sky" stroke-opacity="0.9" stroke-width="8"/>'
        '<image xmlns:xlink="http://www.w3.org/1999/xlink" '
        'x="$left" y="$top" width="$box" height="$box" '
        'preserveAspectRatio="xMidYMid meet" '
        'xlink:href="data:image/png;base64,${base64Encode(png)}"/>';
  }

  static String _badge(int cx, int cy, ClubBadge badge, [List<int>? crest]) {
    if (crest != null && crest.isNotEmpty) {
      return _crestDisc(cx, cy, crest);
    }
    final label = clip(badge.label, 14);
    final size = badgeFontSize(label);
    final words = _text(cx, cy + (size * 0.36).round(), label, size, badge.ink);
    return '<circle cx="$cx" cy="$cy" r="132" fill="${badge.fill}" '
        'stroke="$_white" stroke-opacity="0.9" stroke-width="8"/>$words';
  }

  /// The disc's font size for [label]: smaller as the name gets longer.
  static int badgeFontSize(String label) {
    final n = label.runes.length;
    if (n <= 4) return 64;
    if (n <= 6) return 54;
    if (n <= 8) return 44;
    if (n <= 11) return 36;
    return 30;
  }

  static String _frame(String body) =>
      '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
      'height="$height" viewBox="0 0 $width $height">'
      '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
      '<stop offset="0" stop-color="$_navyTop"/>'
      '<stop offset="1" stop-color="$_navy"/></linearGradient></defs>'
      '<rect width="$width" height="$height" fill="url(#bg)"/>'
      '<rect width="$width" height="14" fill="$_blue"/>'
      '<rect x="470" y="48" width="140" height="140" rx="28" fill="$_blue"/>'
      '<g transform="translate(480 58) scale(0.0586)">${_mark(_white)}</g>'
      '$body'
      '<rect x="0" y="${height - 110}" width="$width" height="110" '
      'fill="$_blue"/>'
      '${_text(540, height - 42, 'توقّع النتائج ونافس على نُخبة', 40, _white, weight: 600)}'
      '</svg>';

  static String _text(
    int x,
    int y,
    String words,
    int size,
    String fill, {
    int weight = 700,
    String anchor = 'middle',
    String direction = 'rtl',
  }) =>
      '<text x="$x" y="$y" font-family="$font" font-weight="$weight" '
      'font-size="$size" fill="$fill" text-anchor="$anchor" '
      'direction="$direction">${escape(words)}</text>';

  /// [words] cut to [max] characters, with an ellipsis when cut.
  static String clip(String words, int max) {
    final runes = words.trim().runes.toList();
    if (runes.length <= max) {
      return words.trim();
    }
    return '${String.fromCharCodes(runes.take(max - 1)).trimRight()}…';
  }

  /// [words] safe inside an SVG text.
  static String escape(String words) => words
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
