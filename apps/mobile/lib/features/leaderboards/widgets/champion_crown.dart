/// The champion's crown, drawn rather than taken from a font: an emoji
/// depends on the device's (or the browser's) emoji font, and a crown that
/// turns into an empty box on one phone is worse than none.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_tokens.dart';

/// A gold crown [size] wide, three points topped with jewels over a band.
class ChampionCrown extends StatelessWidget {
  /// Creates the crown.
  const ChampionCrown({required this.size, this.semanticLabel, super.key});

  /// The crown's width; its height is three quarters of it.
  final double size;

  /// Read out by a screen reader; null leaves the crown decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Widget crown = CustomPaint(
      size: Size(size, size * 0.75),
      painter: _CrownPainter(
        light: Color.lerp(t.gold, Colors.white, 0.35)!,
        dark: t.gold,
      ),
    );
    final String? label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: crown);
    return Semantics(label: label, image: true, child: crown);
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[light, dark],
      ).createShader(Offset.zero & size);

    final Path body = Path()
      ..moveTo(w * 0.12, h * 0.78)
      ..lineTo(w * 0.05, h * 0.28)
      ..lineTo(w * 0.31, h * 0.52)
      ..lineTo(w * 0.5, h * 0.14)
      ..lineTo(w * 0.69, h * 0.52)
      ..lineTo(w * 0.95, h * 0.28)
      ..lineTo(w * 0.88, h * 0.78)
      ..close();
    canvas.drawPath(body, fill);

    final RRect band = RRect.fromLTRBR(
      w * 0.12,
      h * 0.82,
      w * 0.88,
      h * 0.98,
      Radius.circular(h * 0.05),
    );
    canvas.drawRRect(band, fill);

    final double jewel = w * 0.065;
    for (final Offset tip in <Offset>[
      Offset(w * 0.05, h * 0.28),
      Offset(w * 0.5, h * 0.14),
      Offset(w * 0.95, h * 0.28),
    ]) {
      canvas.drawCircle(tip, jewel, fill);
    }
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark;
}
