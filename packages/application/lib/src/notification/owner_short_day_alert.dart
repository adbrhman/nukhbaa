import 'package:application/src/admin/ports/user_admin_repository.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/ports/daily_selection_log.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/announcement_repository.dart';
import 'package:domain/domain.dart';
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

/// [DailyShortfallAlert] for the owner admin only (decided by the owner on
/// 2026-11-01, script 190): one in-app notification to the active admin
/// account whose e-mail is [email], never to the other admins. No push.
///
/// The words are kept as an announcement addressed to him alone, so the
/// inbox shows them as it shows an admin broadcast and the app needs no
/// update; nobody else's inbox gets a row.
final class OwnerShortDayAlert implements DailyShortfallAlert {
  /// Creates the alert.
  const OwnerShortDayAlert({
    required this.email,
    required UserAdminRepository users,
    required AnnouncementRepository announcements,
    required CreateNotification notify,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _users = users,
       _announcements = announcements,
       _notify = notify,
       _ids = idGenerator,
       _clock = clock;

  /// The owner admin's e-mail.
  final String email;

  final UserAdminRepository _users;
  final AnnouncementRepository _announcements;
  final CreateNotification _notify;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<void>> send({
    required DateTime day,
    required int fixtureCount,
    required int minimum,
    required DateTime? firstKickoff,
  }) async {
    final found = await _users.listUsers(search: email.trim(), limit: 5);
    if (found is Err<List<User>>) {
      return Result.err(found.error);
    }
    final owner = _ownerOf((found as Ok<List<User>>).value);
    if (owner == null) {
      return const Result.err(
        AppError.invariant(
          'notification.owner_admin_missing',
          'No active admin account has the alert e-mail',
        ),
      );
    }

    final idResult = AnnouncementId.tryParse(_ids.newUuid());
    if (idResult is Err<AnnouncementId>) {
      return Result.err(idResult.error);
    }
    final id = (idResult as Ok<AnnouncementId>).value;
    final text = shortDayText(
      day: day,
      fixtureCount: fixtureCount,
      minimum: minimum,
      firstKickoff: firstKickoff,
    );
    final built = Announcement.create(
      id: id,
      authorId: owner.id,
      title: text.title,
      body: text.body,
      createdAt: _clock.nowUtc(),
    );
    if (built is Err<Announcement>) {
      return Result.err(built.error);
    }
    final saved = await _announcements.save((built as Ok<Announcement>).value);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }
    final created = await _notify(
      recipientId: owner.id,
      kind: NotificationKind.adminAnnouncement,
      subject: NotificationSubject.adminAnnouncement(announcementId: id),
    );
    return switch (created) {
      Ok<bool>() => const Result.ok(null),
      Err<bool>(:final error) => Result.err(error),
    };
  }

  User? _ownerOf(List<User> users) {
    final wanted = email.trim().toLowerCase();
    for (final user in users) {
      if ((user.email ?? '').trim().toLowerCase() == wanted &&
          user.role == PlatformRole.admin &&
          user.status.canAct) {
        return user;
      }
    }
    return null;
  }
}
