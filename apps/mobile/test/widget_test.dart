// اختبار دخان بسيط: يتأكد أن التطبيق يُقلَع بلا استثناء غير مُتوقَّع.
// (كان يشير خطأً لكلاس افتراضي غير موجود اسمه MyApp؛ اسم كلاس الجذر
// الفعلي في lib/app.dart هو NukhbaApp).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/app.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/providers.dart';

void main() {
  testWidgets('NukhbaApp يُقلَع بلا استثناء', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(apiBaseUrl: Uri.parse('http://localhost:8080')),
          ),
        ],
        child: const NukhbaApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
