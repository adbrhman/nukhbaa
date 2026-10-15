/// Hands a card drawn on screen to the phone's share sheet, as a picture
/// with a line of text: the exact-hit card, the day's hero and the month's
/// champion. One place, so each says when it could not (audit L-18): a
/// share that silently did nothing read as a dead button.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// What a share dialog says when [sharePicture] returned false.
const String sharePictureFailedText = 'تعذّرت المشاركة. حاول مرة أخرى.';

/// The share sheet itself; a test passes its own.
typedef ShareSheet = Future<Object?> Function(ShareParams params);

/// Draws the picture under [boundaryKey] (a [RepaintBoundary]) and shares
/// it as [fileName] with [text]. True when the share sheet opened; false
/// when the picture could not be drawn or the sheet refused, never a throw.
/// [share] replaces the phone's sheet in a test.
Future<bool> sharePicture({
  required GlobalKey boundaryKey,
  required String text,
  required String fileName,
  ShareSheet? share,
}) async {
  try {
    final RenderObject? object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return false;
    final ui.Image image = await object.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return false;
    await (share ?? SharePlus.instance.share)(
      ShareParams(
        text: text,
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
