/// The cup drawn for the Hall of Fame: gold for a season, silver for a month.
///
/// Drawn in code, so it needs no picture file, follows the theme's metals and
/// stays sharp at any size.
library;

import 'package:flutter/material.dart';

/// A trophy cup [size] across, shaded from [light] to [dark].
class TrophyCup extends StatelessWidget {
  /// Creates a cup.
  const TrophyCup({
    required this.light,
    required this.dark,
    this.size = 64,
    super.key,
  });

  /// The metal where the light falls.
  final Color light;

  /// The metal in the shade.
  final Color dark;

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Decoration only: the card around it says what the cup is.
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CupPainter(light: light, dark: dark),
        ),
      ),
    );
  }
}

class _CupPainter extends CustomPainter {
  const _CupPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width, size.height);

    final Paint metal = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[light, dark, light],
      ).createShader(const Rect.fromLTWH(0, 0, 1, 1));

    final Paint handle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.055
      ..strokeCap = StrokeCap.round
      ..shader = metal.shader;

    final Path left = Path()
      ..moveTo(0.23, 0.18)
      ..cubicTo(0.02, 0.16, 0.04, 0.48, 0.28, 0.46);
    final Path right = Path()
      ..moveTo(0.77, 0.18)
      ..cubicTo(0.98, 0.16, 0.96, 0.48, 0.72, 0.46);
    canvas
      ..drawPath(left, handle)
      ..drawPath(right, handle);

    final Path bowl = Path()
      ..moveTo(0.2, 0.1)
      ..lineTo(0.8, 0.1)
      ..cubicTo(0.8, 0.5, 0.66, 0.64, 0.5, 0.64)
      ..cubicTo(0.34, 0.64, 0.2, 0.5, 0.2, 0.1)
      ..close();
    canvas.drawPath(bowl, metal);

    canvas
      ..drawRect(const Rect.fromLTWH(0.45, 0.62, 0.1, 0.17), metal)
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0.29, 0.78, 0.42, 0.09),
          const Radius.circular(0.03),
        ),
        metal,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0.22, 0.87, 0.56, 0.08),
          const Radius.circular(0.03),
        ),
        metal,
      );

    // A soft highlight down the left of the bowl.
    final Path shine = Path()
      ..moveTo(0.29, 0.16)
      ..cubicTo(0.29, 0.42, 0.37, 0.53, 0.45, 0.57)
      ..cubicTo(0.37, 0.46, 0.34, 0.34, 0.34, 0.16)
      ..close();
    canvas
      ..drawPath(shine, Paint()..color = const Color(0x55FFFFFF))
      ..restore();
  }

  @override
  bool shouldRepaint(_CupPainter old) => old.light != light || old.dark != dark;
}
