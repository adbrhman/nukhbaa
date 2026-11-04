import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('ClubBadge.shortLabel', () {
    test('drops the article from a single long word', () {
      expect(ClubBadge.shortLabel('الهلال'), 'هلال');
      expect(ClubBadge.shortLabel(' الاتحاد '), 'اتحاد');
    });

    test('keeps a short word and a name of several words whole', () {
      expect(ClubBadge.shortLabel('النصر'), 'النصر');
      expect(ClubBadge.shortLabel('ريال مدريد'), 'ريال مدريد');
      expect(ClubBadge.shortLabel('ليفربول'), 'ليفربول');
    });
  });

  group('ClubBadge.fallback', () {
    test('is Nukhba navy with white words', () {
      final badge = ClubBadge.fallback('الهلال');

      expect(badge.fill, ClubBadge.defaultFill);
      expect(badge.ink, ClubBadge.defaultInk);
      expect(badge.label, 'هلال');
    });
  });

  group('ClubBadge.ofColour', () {
    test('writes white on a dark fill and navy on a light one', () {
      expect(
        ClubBadge.ofColour(clubName: 'الهلال', fill: '#0b4fd8').ink,
        ClubBadge.defaultInk,
      );
      expect(
        ClubBadge.ofColour(clubName: 'النصر', fill: '#F5D000').ink,
        ClubBadge.defaultFill,
      );
    });

    test('keeps the fill in capitals and an admin label over the name', () {
      final badge = ClubBadge.ofColour(
        clubName: 'مانشستر يونايتد',
        fill: '#da291c',
        label: 'يونايتد',
      );

      expect(badge.fill, '#DA291C');
      expect(badge.label, 'يونايتد');
    });

    test('a fill that is not #RRGGBB falls back to navy', () {
      final badge = ClubBadge.ofColour(clubName: 'الهلال', fill: 'blue');

      expect(badge.fill, ClubBadge.defaultFill);
      expect(badge.ink, ClubBadge.defaultInk);
    });
  });

  group('contrast', () {
    test('white on navy is above the WCAG AAA ratio for text', () {
      final ratio = ClubBadge.contrast(
        ClubBadge.luminance(ClubBadge.defaultInk),
        ClubBadge.luminance(ClubBadge.defaultFill),
      );

      expect(ratio, greaterThan(7));
    });

    test('the ink chosen is never below 3:1 on a club colour', () {
      for (final fill in <String>[
        '#0B4FD8',
        '#F5D000',
        '#C8102E',
        '#FFFFFF',
        '#000000',
        '#00A651',
        '#808080',
      ]) {
        final ink = ClubBadge.inkFor(fill);
        final ratio = ClubBadge.contrast(
          ClubBadge.luminance(fill),
          ClubBadge.luminance(ink),
        );
        expect(ratio, greaterThanOrEqualTo(3), reason: fill);
      }
    });
  });
}
