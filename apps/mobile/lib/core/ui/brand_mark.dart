/// The Nukhbaa mark drawn as a vector: the N, the bowl of the nun around
/// the goal and its dot, the ball -- the shapes of
/// `assets/branding/nukhbaa_logo.png`, measured off its 512 px canvas.
///
/// The bottom bar carries the mark on every tab at 11-12 px, where the
/// 512 px picture scaled down read as a blurred blue square (the owner's
/// screenshot, 2026-10-27). Drawn as paths it stays sharp at any size and
/// on any pixel ratio, and costs no image decode.
library;

import 'package:flutter/widgets.dart';

/// The logo's own blue, picked from `nukhbaa_logo.png`.
const Color kBrandMarkBlue = Color(0xFF1978D1);

/// The mark in its blue tile ([tile]) or alone, in [markColor].
class BrandMark extends StatelessWidget {
  /// Creates the mark, [size] wide and high.
  const BrandMark({
    required this.size,
    this.tile = true,
    this.tileColor = kBrandMarkBlue,
    this.markColor = const Color(0xFFFFFFFF),
    this.cornerRadius = 0.24,
    super.key,
  });

  /// Width and height.
  final double size;

  /// Draws the rounded blue tile behind the mark.
  final bool tile;

  /// The tile's colour.
  final Color tileColor;

  /// The mark's colour.
  final Color markColor;

  /// The tile's corner radius, as a share of [size].
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: BrandMarkPainter(
          tile: tile,
          tileColor: tileColor,
          markColor: markColor,
          cornerRadius: cornerRadius,
        ),
      ),
    );
  }
}

/// Paints [BrandMark].
class BrandMarkPainter extends CustomPainter {
  /// Creates the painter.
  const BrandMarkPainter({
    required this.tile,
    required this.tileColor,
    required this.markColor,
    required this.cornerRadius,
  });

  /// Draws the tile.
  final bool tile;

  /// The tile's colour.
  final Color tileColor;

  /// The mark's colour.
  final Color markColor;

  /// The tile's corner radius, as a share of the side.
  final double cornerRadius;

  /// The mark's outline on the logo's 512 px canvas: the N's stem, its
  /// diagonal, the bowl's floor and its right wall, one closed shape.
  static const List<Offset> outline = <Offset>[
    Offset(98, 198),
    Offset(176, 198),
    Offset(216, 297),
    Offset(362, 297),
    Offset(362, 198),
    Offset(413, 198),
    Offset(413, 327),
    Offset(177, 327),
    Offset(149, 249),
    Offset(149, 327),
    Offset(98, 327),
  ];

  /// The dot -- the ball -- on the same canvas.
  static const Offset dotCentre = Offset(273, 206.5);

  /// The dot's radius on the same canvas.
  static const double dotRadius = 22.5;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & Size.square(side),
          Radius.circular(side * cornerRadius),
        ),
        Paint()..color = tileColor,
      );
    }
    // Alone, the mark fills the box: its 315 px of width on 330, its
    // centre (255.5, 255.5 on the canvas) on the box's.
    final double scale = tile ? side / 512 : side / 330;
    final double centring = side / 2 - 255.5 * scale;
    final Offset shift = tile ? Offset.zero : Offset(centring, centring);
    final Paint ink = Paint()
      ..color = markColor
      ..isAntiAlias = true;
    final Path path = Path()
      ..addPolygon(<Offset>[
        for (final Offset p in outline) p * scale + shift,
      ], true);
    canvas.drawPath(path, ink);
    canvas.drawCircle(dotCentre * scale + shift, dotRadius * scale, ink);
  }

  @override
  bool shouldRepaint(BrandMarkPainter oldDelegate) =>
      oldDelegate.tile != tile ||
      oldDelegate.tileColor != tileColor ||
      oldDelegate.markColor != markColor ||
      oldDelegate.cornerRadius != cornerRadius;
}
