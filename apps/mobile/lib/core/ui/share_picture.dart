/// Hands a card drawn on screen to the phone's share sheet, as a picture
/// with a line of text: the exact-hit card, the day's hero and the month's
/// champion. One place, so each says when it could not (audit L-18): a
/// share that silently did nothing read as a dead button.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../design/app_typography.dart';

/// What a share dialog says when [sharePicture] returned false.
const String sharePictureFailedText = 'تعذّرت المشاركة. حاول مرة أخرى.';

/// The share sheet itself; a test passes its own.
typedef ShareSheet = Future<Object?> Function(ShareParams params);

/// Adds a readable RTL caption beneath the captured card, in the same PNG.
/// Coordinates and font sizes use the same 3x scale as the card capture.
Future<ui.Image> _appendCaption(ui.Image captured, String caption) async {
  const double scale = 3;
  const double footerLogicalHeight = 112;
  final int footerHeight = (footerLogicalHeight * scale).round();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(
      0,
      0,
      captured.width.toDouble(),
      (captured.height + footerHeight).toDouble(),
    ),
  );
  canvas.drawImage(captured, ui.Offset.zero, ui.Paint());
  canvas.drawRect(
    ui.Rect.fromLTWH(
      0,
      captured.height.toDouble(),
      captured.width.toDouble(),
      footerHeight.toDouble(),
    ),
    ui.Paint()..color = const ui.Color(0xFF081729),
  );
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: caption,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: AppFontSize.s14 * scale,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
    maxLines: 4,
    ellipsis: '…',
  )..layout(maxWidth: captured.width.toDouble() - 48 * scale);
  painter.paint(
    canvas,
    ui.Offset(
      (captured.width - painter.width) / 2,
      captured.height + (footerHeight - painter.height) / 2,
    ),
  );
  return recorder.endRecording().toImage(
    captured.width,
    captured.height + footerHeight,
  );
}

/// Draws the picture under [boundaryKey] (a [RepaintBoundary]) and shares
/// it as [fileName] with [text]. True when the share sheet opened; false
/// when the picture could not be drawn or the sheet refused, never a throw.
/// [share] replaces the phone's sheet in a test.
Future<bool> sharePicture({
  required GlobalKey boundaryKey,
  required String text,
  required String fileName,
  String? captionOnImage,
  ShareSheet? share,
}) async {
  try {
    // A frame already scheduled is the card's own repaint (the tap that
    // opened the share, a pressed button inside the card): wait for it, so
    // the picture is the card as painted and `!debugNeedsPaint` holds. With
    // none scheduled the card is painted already, and waiting would hang a
    // caller inside tester.runAsync, where no frame is ever pumped (173).
    final WidgetsBinding binding = WidgetsBinding.instance;
    if (binding.hasScheduledFrame) await binding.endOfFrame;
    final RenderObject? object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return false;
    final ui.Image captured = await object.toImage(pixelRatio: 3);
    final ui.Image image = captionOnImage == null
        ? captured
        : await _appendCaption(captured, captionOnImage);
    if (!identical(image, captured)) captured.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return false;
    await (share ?? SharePlus.instance.share)(
      ShareParams(
        text: captionOnImage == null ? text : '',
        files: <XFile>[
          XFile.fromData(
            data.buffer.asUint8List(),
            mimeType: 'image/png',
            name: fileName,
          ),
        ],
        fileNameOverrides: <String>[fileName],
      ),
    );
    return true;
  } on Object catch (error) {
    debugPrint('sharePicture: $error');
    return false;
  }
}
