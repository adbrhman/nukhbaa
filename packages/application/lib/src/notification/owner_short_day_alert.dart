import 'package:application/src/football_data/ports/daily_selection_log.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:shared/shared.dart';

const List<String> _weekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// The words of the short-day alert (script 190), for [OwnerShortDayAlert]
/// and its test.
({String title, String body}) shortDayText({
  required DateTime day,
  required int fixtureCount,
  required int minimum,
  required DateTime? firstKickoff,
}) {
  final weekday = _weekdays[day.weekday - 1];
  final date = isoDay(day);
  final missing = minimum - fixtureCount;
  final deadline = firstKickoff == null
      ? 'قبل بداية اليوم'
      : 'قبل أول مباراة في اليوم '
            '(${riyadhClock(firstKickoff).substring(11)} بتوقيت الرياض)، '
            'فعندها تُجمَّد قائمة الجولة';
  return (
    title: 'يوم ناقص المباريات: $weekday $date',
    body:
        'يوم $weekday $date (بتوقيت الرياض): عدد المباريات $fixtureCount، '
        'والحد الأدنى $minimum، والناقص $missing. أضاف النظام كل ما يناسب '
        'من البطولات التلقائية. أضف مباريات من بطولات أخرى من لوحة '
        'المشرف ← المباريات $deadline.',
  );
}

/// [DailyShortfallAlert] for the owners only (decided by the owner on
/// 2026-11-01, script 190): one in-app notification to each owner seat
/// that can act ([OwnerNotices], script 285), never to the other admins.
/// No push.
///
/// The words are kept as an announcement addressed to the owners alone, so
/// the inbox shows them as it shows an admin broadcast and the app needs no
/// update; nobody else's inbox gets a row.
final class OwnerShortDayAlert implements DailyShortfallAlert {
  /// Creates the alert.
  // NK285_03
  const OwnerShortDayAlert({required OwnerNotices owner}) : _owner = owner;

  final OwnerNotices _owner;

  @override
  Future<Result<void>> send({
    required DateTime day,
    required int fixtureCount,
    required int minimum,
    required DateTime? firstKickoff,
  }) {
    final text = shortDayText(
      day: day,
      fixtureCount: fixtureCount,
      minimum: minimum,
      firstKickoff: firstKickoff,
    );
    return _owner.tell(title: text.title, body: text.body);
  }
}
