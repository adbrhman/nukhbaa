/// Sharing a card as a picture (audit L-18): the card drawn on screen goes
/// to the share sheet with its text, and a card that cannot be drawn or a
/// sheet that refuses is reported as false, never thrown, so the dialog
/// can say so.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/share_picture.dart';
import 'package:share_plus/share_plus.dart';

Future<GlobalKey> _card(WidgetTester tester) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: ColoredBox(color: Colors.blue),
        ),
      ),
    ),
  );
  return key;
}

void main() {
  testWidgets('the drawn card goes to the sheet with its text', (tester) async {
    final GlobalKey key = await _card(tester);
    final List<ShareParams> sent = <ShareParams>[];

    final bool? shared = await tester.runAsync(
      () => sharePicture(
        boundaryKey: key,
        text: 'hello',
        fileName: 'card.png',
        share: (ShareParams params) async {
          sent.add(params);
          return null;
        },
      ),
    );

    expect(shared, isTrue);
    expect(sent, hasLength(1));
    expect(sent.single.text, 'hello');
    expect(sent.single.files, hasLength(1));
    expect(sent.single.fileNameOverrides, <String>['card.png']);
  });

  testWidgets('caption is rendered into the shared PNG', (tester) async {
    final GlobalKey key = await _card(tester);
    final List<ShareParams> sent = <ShareParams>[];

    final bool? shared = await tester.runAsync(
      () => sharePicture(
        boundaryKey: key,
        text: 'caption',
        captionOnImage:
            'توقعت مواجهة: الرياض 1-4 القادسية في نُخبة\nتوقع معي: https://nukhbaa.app',
        fileName: 'card.png',
        share: (ShareParams params) async {
          sent.add(params);
          return null;
        },
      ),
    );

    expect(shared, isTrue);
    expect(sent, hasLength(1));
    final Uint8List png = await sent.single.files!.single.readAsBytes();
    expect(png.take(8).toList(), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final int height = ByteData.sublistView(png).getUint32(20);
    expect(
      height,
      greaterThan(60),
      reason: 'the caption adds a footer to the captured 20x20 card',
    );
  });

  testWidgets('a sheet that refuses is false, not a throw', (tester) async {
    final GlobalKey key = await _card(tester);

    final bool? shared = await tester.runAsync(
      () => sharePicture(
        boundaryKey: key,
        text: 'hello',
        fileName: 'card.png',
        share: (ShareParams params) async => throw Exception('no sheet'),
      ),
    );

    expect(shared, isFalse);
  });

  testWidgets('a card not on screen is false, and nothing is sent', (
    tester,
  ) async {
    var calls = 0;

    final bool? shared = await tester.runAsync(
      () => sharePicture(
        boundaryKey: GlobalKey(),
        text: 'hello',
        fileName: 'card.png',
        share: (ShareParams params) async {
          calls++;
          return null;
        },
      ),
    );

    expect(shared, isFalse);
    expect(calls, 0);
  });

  test('the failure line is Arabic', () {
    expect(sharePictureFailedText, 'تعذّرت المشاركة. حاول مرة أخرى.');
  });
}
