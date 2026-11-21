/// Every time in the app is Riyadh's, on the 24-hour clock, whatever the
/// device's zone (owner decision 2026-11-21, script 299). A kickoff's time
/// carries no weekday any more: it always falls on the Riyadh day it is
/// filed under.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/format/timestamps.dart';
import 'package:mobile/l10n/app_localizations.dart';

// NK299_07
Future<String> _shown(
  WidgetTester tester,
  String Function(BuildContext context) format,
) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (BuildContext context) {
          out = format(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return out;
}

void main() {
  testWidgets('a kickoff reads on Riyadh 24-hour clock', (tester) async {
    // 00:30 Riyadh on Thursday 15 October 2026, and 23:05 the day before.
    final String early = DateTime.utc(2026, 10, 14, 21, 30).toIso8601String();
    final String late = DateTime.utc(2026, 10, 14, 20, 5).toIso8601String();

    expect(await _shown(tester, (c) => formatKickoffTime(c, early)), '00:30');
    expect(await _shown(tester, (c) => formatKickoffTime(c, late)), '23:05');
    expect(await _shown(tester, (c) => formatTimeOfDay(c, late)), '23:05');
  });

  testWidgets('a date and time carry the 24-hour Riyadh time', (tester) async {
    final String at = DateTime.utc(2026, 11, 17, 19).toIso8601String();

    final String stamp = await _shown(tester, (c) => formatTimestamp(c, at));
    expect(stamp, endsWith('22:00'));
    expect(stamp, contains('17'));
    expect(stamp, isNot(contains('PM')));
    final String day = await _shown(tester, (c) => formatDayAndTime(c, at));
    expect(day, endsWith('22:00'));
  });

  testWidgets('an unreadable time is shown as it came', (tester) async {
    expect(
      await _shown(tester, (c) => formatKickoffTime(c, 'not a time')),
      'not a time',
    );
  });
}
