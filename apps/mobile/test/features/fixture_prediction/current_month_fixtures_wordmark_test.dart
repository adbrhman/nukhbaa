/// The matches header's wordmark is the mark and the letters, plain: no speed
/// strokes beside the N or behind the ball (owner decision 2026-11-25).
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// NK320_02
void main() {
  testWidgets('the wordmark has no loose strokes around the mark', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final ByteData data = await rootBundle.load(
        'assets/branding/nukhbaa_wordmark.png',
      );
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final ui.Image image = (await codec.getNextFrame()).image;
      final ByteData rgba = (await image.toByteData())!;
      final int w = image.width;
      final int h = image.height;
      bool ink(int x, int y) => rgba.getUint8((y * w + x) * 4 + 3) > 40;

      expect(<int>[w, h], <int>[491, 84]);

      // Pieces of ink, side by side or above and below count as one: the N,
      // the ball and the six letters.
      final List<bool> seen = List<bool>.filled(w * h, false);
      int pieces = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (!ink(x, y) || seen[y * w + x]) continue;
          pieces++;
          final List<int> stack = <int>[y * w + x];
          seen[y * w + x] = true;
          while (stack.isNotEmpty) {
            final int at = stack.removeLast();
            final int cx = at % w;
            final int cy = at ~/ w;
            for (final List<int> d in const <List<int>>[
              <int>[1, 0],
              <int>[-1, 0],
              <int>[0, 1],
              <int>[0, -1],
            ]) {
              final int nx = cx + d[0];
              final int ny = cy + d[1];
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              if (!ink(nx, ny) || seen[ny * w + nx]) continue;
              seen[ny * w + nx] = true;
              stack.add(ny * w + nx);
            }
          }
        }
      }
      expect(pieces, 7);

      // The blue of the mark ends where the letters' colour begins: those
      // columns, between the mark and the first letter, hold no ink.
      for (int x = 138; x < 152; x++) {
        for (int y = 0; y < h; y++) {
          expect(ink(x, y), isFalse, reason: 'ink at $x,$y');
        }
      }
    });
  });
}
