library;

import 'dart:async';

import 'package:flutter/material.dart';

/// The unread count on a notifications bell.
///
/// "9+" above nine, and the label sits out on the icon's top corner: the
/// Material default anchors it inside the glyph, so a two-digit count hid
/// the bell it was counting for (UI-05).
///
/// While anything is unread the bell blinks (decided 2026-10-07), so a new
/// notification is noticed; opening the inbox marks everything read, the
/// count drops to zero and the bell is still again until the next one. The
/// count stays solid; only the glyph fades. A device that asks for less
/// motion gets the count alone.
class UnreadBadge extends StatefulWidget {
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

  /// One blink: the glyph fades out and back once per two periods.
  static const Duration blinkPeriod = Duration(milliseconds: 800);

  /// How dim the glyph gets at the low point of a blink.
  static const double dimOpacity = 0.3;

  @override
  State<UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<UnreadBadge> {
  // A timer, not a repeating animation controller: between two fades no
  // frame is scheduled, so the screen (and a test's settle) rests.
  Timer? _blink;
  bool _dim = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(UnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool blink =
        widget.count > 0 &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (blink && _blink == null) {
      _blink = Timer.periodic(UnreadBadge.blinkPeriod, (_) {
        if (mounted) setState(() => _dim = !_dim);
      });
    } else if (!blink && _blink != null) {
      _blink!.cancel();
      _blink = null;
      _dim = false;
    }
  }

  @override
  void dispose() {
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Badge(
      isLabelVisible: widget.count > 0,
      label: Text(UnreadBadge.labelFor(widget.count)),
      offset: Offset(
        rtl ? -UnreadBadge._outward : UnreadBadge._outward,
        -UnreadBadge._up,
      ),
      child: AnimatedOpacity(
        key: const Key('unreadBadge.bell'),
        opacity: _dim ? UnreadBadge.dimOpacity : 1,
        duration: const Duration(milliseconds: 300),
        child: widget.child,
      ),
    );
  }
}
