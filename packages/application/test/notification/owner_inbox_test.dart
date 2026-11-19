import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// The owner seats that can act, primary first, or a failed read.
final class _Seats implements OwnerRegistry {
  List<UserId> seats = const <UserId>[];
  AppError? failure;
  int reads = 0;

  @override
  Future<Result<List<UserId>>> activeOwners() async {
    reads++;
    final AppError? error = failure;
    return error == null ? Result.ok(seats) : Result.err(error);
  }
}

/// Keeps what is saved.
final class _Announcements implements AnnouncementRepository {
  final List<Announcement> saved = [];

  @override
  Future<Result<void>> save(Announcement announcement) async {
    saved.add(announcement);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<Announcement>>> findByIds(
    List<AnnouncementId> ids,
  ) async => const Result.ok(<Announcement>[]);

  @override
  Future<Result<List<AnnouncementRecipient>>> audience() async =>
      const Result.ok(<AnnouncementRecipient>[]);
}

const _primary = uuidC;
const _backup = uuidA;
const _admin = uuidD;

// Script 285 (decision Q01): the owners are the seats of
// admin.platform_owners, by account id, not an e-mail in the code.
void main() {
  late _Seats seats;
  late _Announcements announcements;
  late InMemoryNotificationRepository notifications;
  late OwnerInbox inbox;

  setUp(() {
    seats = _Seats();
    announcements = _Announcements();
    notifications = InMemoryNotificationRepository();
    final ids = FakeIdGenerator(const [uuidB]);
    final clock = FakeClock(DateTime.utc(2026, 11, 20, 9));
    inbox = OwnerInbox(
      owners: seats,
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

  test('the server acts as the primary when he can act', () async {
    seats.seats = const <UserId>[UserId(_primary), UserId(_backup)];

    expect(
      (await inbox.ownerId() as Ok<UserId?>).value,
      const UserId(_primary),
    );
  });

  test('the backup takes over when the primary cannot act', () async {
    seats.seats = const <UserId>[UserId(_backup)];

    expect((await inbox.ownerId() as Ok<UserId?>).value, const UserId(_backup));
  });

  test('no seat that can act is no owner', () async {
    expect((await inbox.ownerId() as Ok<UserId?>).value, isNull);
    expect(
      (await inbox.isOwner(const UserId(_primary)) as Ok<bool>).value,
      isFalse,
    );
  });

  test('both seats are owners, another admin is not', () async {
    seats.seats = const <UserId>[UserId(_primary), UserId(_backup)];

    expect(
      (await inbox.isOwner(const UserId(_primary)) as Ok<bool>).value,
      isTrue,
    );
    expect(
      (await inbox.isOwner(const UserId(_backup)) as Ok<bool>).value,
      isTrue,
    );
    expect(
      (await inbox.isOwner(const UserId(_admin)) as Ok<bool>).value,
      isFalse,
    );
  });

  test('a failed read is passed on, never read as an owner', () async {
    seats.failure = const AppError.transient('db.down', 'down');

    expect(
      (await inbox.isOwner(const UserId(_primary)) as Err<bool>).error.code,
      'db.down',
    );
    expect((await inbox.ownerId() as Err<UserId?>).error.code, 'db.down');
    final told = await inbox.tell(title: 'عنوان', body: 'نص');
    expect((told as Err<void>).error.code, 'db.down');
    expect(announcements.saved, isEmpty);
  });

  test('a message reaches every seat once, and no other admin', () async {
    seats.seats = const <UserId>[UserId(_primary), UserId(_backup)];

    final told = await inbox.tell(title: 'تتويج الشهر', body: 'تم التتويج');

    expect(told, isA<Ok<void>>());
    expect(notifications.countFor(_primary), 1);
    expect(notifications.countFor(_backup), 1);
    expect(notifications.countFor(_admin), 0);
    expect(announcements.saved.single.authorId, const UserId(_primary));
    expect(seats.reads, 1);
  });
}
