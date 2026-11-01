import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryUserAdminRepository, storedUser;
import 'fakes.dart';

/// Keeps what is saved; the broadcast audience must never be read.
final class _Announcements implements AnnouncementRepository {
  final List<Announcement> saved = [];
  int audienceReads = 0;

  @override
  Future<Result<void>> save(Announcement announcement) async {
    saved.add(announcement);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<Announcement>>> findByIds(List<AnnouncementId> ids) async {
    final wanted = {for (final id in ids) id.value};
    return Result.ok([
      for (final a in saved)
        if (wanted.contains(a.id.value)) a,
    ]);
  }

  @override
  Future<Result<List<AnnouncementRecipient>>> audience() async {
    audienceReads++;
    return const Result.ok(<AnnouncementRecipient>[]);
  }
}

// Script 190: a day short of matches is told to the owner admin alone.
const _owner = uuidC;
const _suleiman = uuidD;
final _day = DateTime.utc(2026, 11, 5);
final _firstKickoff = DateTime.utc(2026, 11, 5, 13);

void main() {
  late InMemoryUserAdminRepository users;
  late _Announcements announcements;
  late InMemoryNotificationRepository notifications;
  late OwnerShortDayAlert alert;

  setUp(() {
    users = InMemoryUserAdminRepository();
    announcements = _Announcements();
    notifications = InMemoryNotificationRepository();
    final ids = FakeIdGenerator(const [uuidA, uuidB]);
    final clock = FakeClock(DateTime.utc(2026, 11, 3, 21, 5));
    alert = OwnerShortDayAlert(
      email: 'adbrhmanm@gmail.com',
      users: users,
      announcements: announcements,
      notify: CreateNotification(
        notifications: notifications,
        idGenerator: ids,
        clock: clock,
      ),
      idGenerator: ids,
      clock: clock,
    );
  });

  test('only the owner admin gets it, never another admin', () async {
    users
      ..seed(
        storedUser(
          id: _owner,
          role: PlatformRole.admin,
          email: 'AdbrhmanM@gmail.com',
        ),
      )
      ..seed(
        storedUser(
          id: _suleiman,
          role: PlatformRole.admin,
          email: 'suleiman@example.com',
        ),
      );

    final result = await alert.send(
      day: _day,
      fixtureCount: 7,
      minimum: 10,
      firstKickoff: _firstKickoff,
    );

    expect(result, isA<Ok<void>>());
    expect(notifications.countFor(_owner), 1);
    expect(notifications.countFor(_suleiman), 0);
    expect(announcements.audienceReads, 0);
    final saved = announcements.saved.single;
    expect(saved.title, 'يوم ناقص المباريات: الخميس 2026-11-05');
    expect(saved.body, contains('عدد المباريات 7'));
    expect(saved.body, contains('والناقص 3'));
    expect(saved.body, contains('16:00 بتوقيت الرياض'));
    expect(saved.body, contains('من بطولات أخرى'));
  });

  test('an account with the e-mail that is not an admin is not told', () async {
    users.seed(storedUser(id: _owner, email: 'adbrhmanm@gmail.com'));

    final result = await alert.send(
      day: _day,
      fixtureCount: 4,
      minimum: 10,
      firstKickoff: null,
    );

    expect(
      (result as Err<void>).error.code,
      'notification.owner_admin_missing',
    );
    expect(announcements.saved, isEmpty);
    expect(notifications.countFor(_owner), 0);
  });

  test('a day with no match yet says before the day begins', () {
    final text = shortDayText(
      day: _day,
      fixtureCount: 0,
      minimum: 10,
      firstKickoff: null,
    );
    expect(text.body, contains('قبل بداية اليوم'));
    expect(text.body, contains('والناقص 10'));
  });
}
