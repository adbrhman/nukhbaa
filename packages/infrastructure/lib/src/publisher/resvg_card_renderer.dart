import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:image/image.dart' as img;
import 'package:infrastructure/src/publisher/svg_card_builder.dart';
import 'package:shared/shared.dart';

/// [PublisherCardRenderer] over resvg (approved by the owner on 2026-11-04):
/// the card's SVG ([SvgCardBuilder]) goes in on stdin, a PNG comes out on
/// stdout, and the PNG is written again as JPEG, the one format Instagram
/// takes.
///
/// resvg shapes Arabic with the bundled IBM Plex Sans Arabic only
/// (`--skip-system-fonts`), so a picture reads the same on every machine.
final class ResvgCardRenderer implements PublisherCardRenderer {
  /// Runs [executable] with the fonts of [fontsDir].
  ResvgCardRenderer({
    required this.executable,
    required this.fontsDir,
    this.timeout = const Duration(seconds: 30),
    this.quality = 88,
  });

  /// The renderer the server image carries (Dockerfile: `/app/bin/resvg`
  /// and `/app/fonts`), or the paths of `NUKHBA_RESVG` and
  /// `NUKHBA_CARD_FONTS`; null when either is missing, so a server without
  /// them draws nothing and posts nothing that needs a picture.
  static ResvgCardRenderer? fromEnv(Map<String, String> env) {
    final executable = (env['NUKHBA_RESVG'] ?? '/app/bin/resvg').trim();
    final fonts = (env['NUKHBA_CARD_FONTS'] ?? '/app/fonts').trim();
    if (!File(executable).existsSync() || !Directory(fonts).existsSync()) {
      return null;
    }
    return ResvgCardRenderer(executable: executable, fontsDir: fonts);
  }

  /// The resvg binary.
  final String executable;

  /// The folder of the fonts it may use.
  final String fontsDir;

  /// How long one picture may take.
  final Duration timeout;

  /// The JPEG quality.
  final int quality;

  @override
  Future<Result<List<int>>> render(CardSpec spec) async {
    final png = await renderPng(SvgCardBuilder.build(spec));
    if (png is Err<Uint8List>) {
      return Result.err(png.error);
    }
    try {
      final image = img.decodePng((png as Ok<Uint8List>).value);
      if (image == null) {
        return const Result.err(
          AppError.transient('publisher.render_failed', 'resvg gave no PNG'),
        );
      }
      return Result.ok(img.encodeJpg(image, quality: quality));
    } on Object catch (error) {
      return Result.err(
        AppError.transient('publisher.render_failed', 'JPEG failed', error),
      );
    }
  }

  /// The PNG of [svg]. Never throws.
  Future<Result<Uint8List>> renderPng(String svg) async {
    final Process process;
    try {
      process = await Process.start(executable, <String>[
        '--skip-system-fonts',
        '--use-fonts-dir',
        fontsDir,
        '--resources-dir',
        fontsDir,
        '-',
        '-c',
      ]);
    } on Object catch (error) {
      return Result.err(
        AppError.transient(
          'publisher.render_failed',
          'resvg did not start',
          error,
        ),
      );
    }
    final out = BytesBuilder(copy: false);
    final stdoutDone = process.stdout.listen(out.add).asFuture<void>();
    final stderrText = process.stderr.transform(utf8.decoder).join();
    try {
      process.stdin.add(utf8.encode(svg));
      await process.stdin.close();
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await stdoutDone;
      final errors = await stderrText;
      if (code != 0) {
        return Result.err(
          AppError.transient(
            'publisher.render_failed',
            'resvg exited $code: ${errors.trim()}',
          ),
        );
      }
      final bytes = out.takeBytes();
      if (bytes.isEmpty) {
        return const Result.err(
          AppError.transient('publisher.render_failed', 'resvg gave no PNG'),
        );
      }
      return Result.ok(bytes);
    } on Object catch (error) {
      process.kill();
      return Result.err(
        AppError.transient('publisher.render_failed', 'resvg failed', error),
      );
    }
  }
}
