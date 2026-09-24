/// The admin dashboard's smoothness card, through the real
/// [AdminFrameStatsCard] and [adminFrameStatsProvider]: the share of slow
/// frames leads, coloured by verdict; each build gets a line; an empty
/// week says so instead of showing zeros.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/widgets/admin_frame_stats_card.dart';

FrameTotalsDto _totals(
  String? build, {
  required int frames,
  required int slow,
}) => FrameTotalsDto(
  build: build,
  reports: 4,
  users: 3,
  frames: frames,
  slowFrames: slow,
  frozenFrames: 3,
  worstFrameMs: 1500,
  lastReportedAt: '2026-09-24T09:00:00.000Z',
);

Future<void> _pump(WidgetTester tester, AdminFrameStatsDto stats) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminFrameStatsProvider.overrideWith((ref) async => stats)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: AdminFrameStatsCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leads with the slow share, one line per build', (tester) async {
    await _pump(
      tester,
      AdminFrameStatsDto(
        windowDays: 7,
        overall: _totals(null, frames: 8000, slow: 200),
        builds: [
          _totals('new1234', frames: 5000, slow: 50),
          _totals('old1234', frames: 3000, slow: 600),
        ],
        devices: const [
          DeviceTotalsDto(
            deviceModel: 'samsung SM-A105F',
            reports: 9,
            users: 4,
            frames: 9000,
            slowFrames: 1800,
            frozenFrames: 2,
          ),
        ],
      ),
    );

    final Text lead = tester.widget<Text>(
      find.byKey(const Key('admin.frameStats.slow')),
    );
    expect(lead.data, '2.5% إطارات بطيئة');
    expect(lead.style?.color, AppTokens.dark.success);
    expect(
      find.byKey(const Key('admin.frameStats.build.new1234')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.frameStats.build.old1234')),
      findsOneWidget,
    );
    expect(
      find.text('20%'),
      findsNWidgets(2),
      reason: 'the old build (600 of 3000) and the device (1800 of 9000)',
    );
    final Finder device = find.byKey(
      const Key('admin.frameStats.device.samsung SM-A105F'),
    );
    expect(device, findsOneWidget);
    expect(
      find.descendant(of: device, matching: find.text('4 مستخدم')),
      findsOneWidget,
    );
  });

  testWidgets('an empty week says so', (tester) async {
    await _pump(
      tester,
      AdminFrameStatsDto(
        windowDays: 7,
        overall: _totals(null, frames: 0, slow: 0),
        builds: const [],
      ),
    );

    expect(find.byKey(const Key('admin.frameStats.empty')), findsOneWidget);
    expect(find.byKey(const Key('admin.frameStats.slow')), findsNothing);
  });
}
