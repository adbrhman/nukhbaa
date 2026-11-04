import 'dart:math' as math;

/// A club as the publisher draws it: its name on a disc of its colour, in
/// place of its crest (decided by the owner on 2026-11-04: crests are the
/// clubs' trademarks and none is licensed to Nukhba).
///
/// A club with no colours set is drawn in Nukhba's navy. An admin sets a
/// club's colours, and its label, from the admin panel.
final class ClubBadge {
  /// Creates the badge. [fill] and [ink] are `#RRGGBB`.
  const ClubBadge({required this.label, required this.fill, required this.ink});

  /// A badge for [clubName] with no colours set: Nukhba's navy, white ink.
  factory ClubBadge.fallback(String clubName) => ClubBadge(
    label: shortLabel(clubName),
    fill: defaultFill,
    ink: defaultInk,
  );

  /// A badge in [fill] for [clubName] (or [label] when given), its ink the
  /// one of white and navy that reads better on it. A [fill] that is not
  /// `#RRGGBB` gives Nukhba's navy.
  factory ClubBadge.ofColour({
    required String clubName,
    required String fill,
    String? label,
  }) {
    final words = label == null || label.trim().isEmpty
        ? shortLabel(clubName)
        : label.trim();
    if (!isColour(fill)) {
      return ClubBadge(label: words, fill: defaultFill, ink: defaultInk);
    }
    return ClubBadge(label: words, fill: fill.toUpperCase(), ink: inkFor(fill));
  }

  /// Nukhba's navy (the app's page colour).
  static const String defaultFill = '#071426';

  /// White.
  static const String defaultInk = '#FFFFFF';

  /// The words on the disc.
  final String label;

  /// The disc's colour.
  final String fill;

  /// The words' colour.
  final String ink;

  /// The label for [clubName]: a single word that starts with the article
  /// «ال» and is longer than five letters loses it («الهلال» is «هلال»);
  /// any other name stays whole («النصر», «ريال مدريد»).
  static String shortLabel(String clubName) {
    final name = clubName.trim();
    if (!name.contains(' ') && name.startsWith('ال') && name.length > 5) {
      return name.substring(2);
    }
    return name;
  }

  static final RegExp _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// Whether [value] is a colour this badge takes: `#RRGGBB`.
  static bool isColour(String value) => _hex.hasMatch(value);

  /// The one of white and navy with the higher contrast on [fill]
  /// (WCAG 2 relative luminance).
  static String inkFor(String fill) {
    final background = luminance(fill);
    final onWhite = contrast(background, luminance(defaultInk));
    final onNavy = contrast(background, luminance(defaultFill));
    return onWhite >= onNavy ? defaultInk : defaultFill;
  }

  /// The WCAG 2 relative luminance of `#RRGGBB` [colour].
  static double luminance(String colour) {
    if (!isColour(colour)) {
      throw ArgumentError.value(colour, 'colour', 'not #RRGGBB');
    }
    double channel(int start) {
      final value = int.parse(colour.substring(start, start + 2), radix: 16);
      final c = value / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
  }

  /// The WCAG 2 contrast ratio of two luminances.
  static double contrast(double a, double b) {
    final lighter = math.max(a, b);
    final darker = math.min(a, b);
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  bool operator ==(Object other) =>
      other is ClubBadge &&
      other.label == label &&
      other.fill == fill &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(label, fill, ink);
}
