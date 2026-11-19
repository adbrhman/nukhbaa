import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

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

/// The owner seats that can act, primary first (script 285).
final class _Seats implements OwnerRegistry {
  List<UserId> seats = const <UserId>[];

  @override
  Future<Result<List<UserId>>> activeOwners() async => Result.ok(seats);
}

// Script 190: a day short of matches is told to the owners alone; script
// 285: the owners are the seats, the primary and his backup, not an e-mail.
const _owner = uuidC;
const _backup = uuidA;
const _suleiman = uuidD;
final _day = DateTime.utc(2026, 11, 5);
final _firstKickoff = DateTime.utc(2026, 11, 5, 13);

void main() {
  late _Seats seats;
  late _Announcements announcements;
  late InMemoryNotificationRepository notifications;
  late OwnerShortDayAlert alert;

  setUp(() {
    seats = _Seats();
    announcements = _Announcements();
    notifications = InMemoryNotificationRepository();
    final ids = FakeIdGenerator(const [uuidB]);
    final clock = FakeClock(DateTime.utc(2026, 11, 3, 21, 5));
    // NK285_04
    alert = OwnerShortDayAlert(
      owner: OwnerInbox(
        owners: seats,
        announcements: announcements,
        notify: CreateNotification(
          notifications: notifications,
          idGenerator: ids,
          clock: clock,
        ),
        idGenerator: ids,
        clock: clock,
      ),
    );
  });

  test('the primary and the backup get it, never another admin', () async {
    seats.seats = const <UserId>[UserId(_owner), UserId(_backup)];

    final result = await alert.send(
      day: _day,
      fixtureCount: 7,
      minimum: 10,
      firstKickoff: _firstKickoff,
    );

    expect(result, isA<Ok<void>>());
    expect(notifications.countFor(_owner), 1);
    expect(notifications.countFor(_backup), 1);
    expect(notifications.countFor(_suleiman), 0);
    expect(announcements.audienceReads, 0);
    final saved = announcements.saved.single;
    expect(saved.authorId, const UserId(_owner));
    expect(saved.title, 'يوم ناقص المباريات: الخميس 2026-11-05');
    expect(saved.body, contains('عدد المباريات 7'));
    expect(saved.body, contains('والناقص 3'));
    expect(saved.body, contains('16:00 بتوقيت الرياض'));
    expect(saved.body, contains('من بطولات أخرى'));
  });

  test('no seat that can act tells nobody', () async {
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
