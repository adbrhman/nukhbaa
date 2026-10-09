/// A kickoff's time is the viewer's own clock, and the viewer's weekday
/// follows it only when the viewer's date is not the Riyadh day the match
/// is filed under.
///
/// Both cases are driven whatever the device zone: 00:30 Riyadh falls on
/// the day before west of Riyadh, 23:30 Riyadh on the day after east of it.
/// `50_kickoff_time.sh` also runs this under TZ=UTC, where the first one
/// must carry its weekday.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:mobile/core/format/timestamps.dart';
import 'package:mobile/l10n/app_localizations.dart';

Future<String> _shown(WidgetTester tester, DateTime kickoffUtc) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (BuildContext context) {
          out = formatKickoffTime(context, kickoffUtc.toIso8601String());
          return const SizedBox();
        },
      ),
    ),
  );
  return out;
}

String _expected(DateTime kickoffUtc, int riyadhDay) {
  final DateTime local = kickoffUtc.toLocal();
  final String time = intl.DateFormat.jm('en').format(local);
  final bool sameDate =
      local.year == 2026 && local.month == 10 && local.day == riyadhDay;
  return sameDate
      ? time
      : '$time (${intl.DateFormat.EEEE('en').format(local)})';
}

void main() {
  testWidgets('the weekday follows only when the dates differ', (tester) async {
    // 00:30 Riyadh on Thursday 15 October 2026.
    final DateTime earlyThursday = DateTime.utc(2026, 10, 14, 21, 30);
    // 23:30 Riyadh on Wednesday 14 October 2026.
    final DateTime lateWednesday = DateTime.utc(2026, 10, 14, 20, 30);

    expect(await _shown(tester, earlyThursday), _expected(earlyThursday, 15));
    expect(await _shown(tester, lateWednesday), _expected(lateWednesday, 14));

    // Spelled out for the two zones the script runs this in (the clock
    // text itself is left to intl: its AM/PM spacing is CLDR's).
    if (DateTime.now().timeZoneOffset == Duration.zero) {
      expect(await _shown(tester, earlyThursday), endsWith(' (Wednesday)'));
      expect(await _shown(tester, lateWednesday), isNot(contains('(')));
    }
    if (DateTime.now().timeZoneOffset == const Duration(hours: 3)) {
      expect(await _shown(tester, earlyThursday), isNot(contains('(')));
      expect(await _shown(tester, lateWednesday), isNot(contains('(')));
    }
  });

  testWidgets('an unreadable time is shown as it came', (tester) async {
    late String out;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            out = formatKickoffTime(context, 'not a time');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(out, 'not a time');
  });
}
