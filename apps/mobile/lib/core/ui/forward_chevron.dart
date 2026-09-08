/// The "this opens something" chevron.
library;

import 'package:flutter/material.dart';

/// Points the way the reader moves forward: LEFT in Arabic, right in English.
///
/// Material mirrors `Icons.chevron_left` / `chevron_right` automatically under
/// an RTL `Directionality`. That is why every Arabic row drew a backwards `>`
/// while the source plainly said `chevron_left` -- the glyph was flipped after
/// the fact, so writing the arrow you want produced the opposite one. Worse,
/// the app had it both ways: two screens said `chevron_right` and rendered
/// correctly, two said `chevron_left` and rendered backwards.
///
/// This picks the glyph from the ambient direction AND freezes the direction
/// around the [Icon], so the drawn arrow is the same either way and does not
/// depend on which icons Material happens to mark as mirrorable. One widget,
/// so a chevron cannot be wrong on one screen and right on the next.
class ForwardChevron extends StatelessWidget {
  /// Creates a forward chevron in [color] at [size] (both optional -- null
  /// takes the ambient icon theme, as any [Icon] would).
  const ForwardChevron({this.color, this.size, super.key});

  /// The glyph colour.
  final Color? color;

  /// The glyph size in logical pixels.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Icon(
        rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        color: color,
        size: size,
      ),
    );
  }
}
