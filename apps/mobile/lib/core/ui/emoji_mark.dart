/// A verdict mark -- ✅ ❌ 🔥 ⚡ -- that the web can always draw (audit L-53).
///
/// On Android the system's own emoji font draws the marks. On the web,
/// CanvasKit has no emoji font of its own: it fetches one from
/// fonts.gstatic.com, which some networks block (the app bundles its other
/// fonts for that reason), and the marks became empty boxes beside the
/// points. There each known mark is drawn as a Material icon, from the
/// icon font the app already ships; anything else is left out.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// [mark] as text on native, as icons on the web.
class EmojiMark extends StatelessWidget {
  /// Creates the mark. [asIcons] defaults to "on the web"; [textKey] is the
  /// key of the [Text] drawn on native, so a test can read it.
  const EmojiMark(
    this.mark, {
    this.style,
    this.textKey,
    bool? asIcons,
    super.key,
  }) : _asIcons = asIcons;

  /// The marks, as the screens write them ('⚡🔥', '✅', '').
  final String mark;

  /// The text style on native; its font size sizes the icons on the web.
  final TextStyle? style;

  /// The key of the native [Text].
  final Key? textKey;

  final bool? _asIcons;

  static const Map<int, IconData> _icons = <int, IconData>{
    0x2705: Icons.check_circle_rounded, // ✅
    0x274C: Icons.cancel_rounded, // ❌
    0x1F525: Icons.local_fire_department_rounded, // 🔥
    0x26A1: Icons.bolt_rounded, // ⚡
  };

  /// The icons [mark] is drawn with on the web, in order.
  static List<IconData> iconsFor(String mark) => <IconData>[
    for (final int rune in mark.runes)
      if (_icons[rune] case final IconData icon) icon,
  ];

  @override
  Widget build(BuildContext context) {
    if (!(_asIcons ?? kIsWeb)) {
      return Text(mark, key: textKey, style: style);
    }
    final AppTokens tokens = context.tokens;
    final double size =
        (style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14) +
        2;
    Color colorOf(int rune) => switch (rune) {
      0x2705 => tokens.successText,
      0x274C => tokens.errorText,
      _ => tokens.goldAccent,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final int rune in mark.runes)
          if (_icons[rune] case final IconData icon)
            Icon(icon, size: size, color: colorOf(rune)),
      ],
    );
  }
}
