library;

import 'package:flutter/material.dart';

/// The unread count on a notifications bell.
///
/// "9+" above nine, and the label sits out on the icon's top corner: the
/// Material default anchors it inside the glyph, so a two-digit count hid
/// the bell it was counting for (UI-05).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, required this.child});

  /// How many are unread; nothing shows at zero.
  final int count;

  /// The icon the count belongs to.
  final Widget child;

  /// The label for [count]: the number up to nine, then "9+".
  static String labelFor(int count) => count > 9 ? '9+' : '$count';

  /// How far the label moves out past the icon's top corner.
  static const double _outward = 12;
  static const double _up = 6;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Badge(
      isLabelVisible: count > 0,
      label: Text(labelFor(count)),
      offset: Offset(rtl ? -_outward : _outward, -_up),
      child: child,
    );
  }
}
