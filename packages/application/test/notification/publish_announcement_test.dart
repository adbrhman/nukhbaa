import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// A recording [AnnouncementRepository] over two in-memory lists.
final class _FakeAnnouncements implements AnnouncementRepository {
  _FakeAnnouncements(this._audience);

  final List<AnnouncementRecipient> _audience;

  /// Announcements saved by the use-case.
  final List<Announcement> saved = [];

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
  Future<Result<List<AnnouncementRecipient>>> audience() async =>
      Result.ok(_audience);
}

/// A [PushSender] that records what it was asked to send.
final class _RecordingSender implements PushSender {
  final List<List<String>> sent = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    sent.add(List<String>.unmodifiable(tokens));
    return const Result.ok(<String>[]);
  }
}

/// A [NotificationQueue] that records what it was asked to hold.
final class _FakeQueue implements NotificationQueue {
  final List<PushToQueue> queued = [];

  @override
  Future<Result<void>> enqueue(List<PushToQueue> pushes) async {
    queued.addAll(pushes);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  }) => throw StateError('publishing never claims');

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) =>
      throw StateError('publishing never forgets tokens');
}

void main() {
  PublishAnnouncement build({
    required _FakeAnnouncements announcements,
    required InMemoryNotificationRepository notifications,
    required _RecordingSender sender,
    _FakeQueue? queue,
  }) => PublishAnnouncement(
    announcements: announcements,
    create: CreateNotification(
      notifications: notifications,
      idGenerator: FakeIdGenerator([uuidC, uuidD]),
      clock: FakeClock(),
    ),
    sender: sender,
    idGenerator: FakeIdGenerator([uuidA]),
    clock: FakeClock(),
    queue: queue ?? _FakeQueue(),
  );

  group('PublishAnnouncement', () {
    test('refuses a non-admin caller', () async {
      final announcements = _FakeAnnouncements([]);
      final notifications = InMemoryNotificationRepository();
      final sender = _RecordingSender();
      final result =
          await build(
            announcements: announcements,
            notifications: notifications,
            sender: sender,
          )(
            principal: principalUser(userId: uuidB),
            title: 'تنبيه',
            body: 'نص',
          );

      expect(result, isA<Err<int>>());
      expect(announcements.saved, isEmpty);
      expect(sender.sent, isEmpty);
    });

    test('refuses a blank body before touching storage', () async {
      final announcements = _FakeAnnouncements([]);
      final notifications = InMemoryNotificationRepository();
      final sender = _RecordingSender();
      final result =
          await build(
            announcements: announcements,
            notifications: notifications,
            sender: sender,
          )(
            principal: principalUser(userId: uuidB, role: PlatformRole.admin),
            title: 'تنبيه',
            body: '   ',
          );

      expect((result as Err<int>).error.kind, ErrorKind.validation);
      expect(result.error.code, 'notification.announcement_body_empty');
      expect(announcements.saved, isEmpty);
    });

    test('stores the text once, notifies every recipient and pushes to their '
        'devices', () async {
      final announcements = _FakeAnnouncements([
        AnnouncementRecipient(userId: UserId(uuidC), tokens: const ['t1']),
        // No device on file: still gets the in-app notification.
        AnnouncementRecipient(userId: UserId(uuidD), tokens: const []),
      ]);
      final notifications = InMemoryNotificationRepository();
      final sender = _RecordingSender();

      final result =
          await build(
            announcements: announcements,
            notifications: notifications,
            sender: sender,
          )(
            principal: principalUser(userId: uuidB, role: PlatformRole.admin),
            title: '  تنبيه  ',
            body: '  مباريات الجمعة تبدأ مبكرًا  ',
          );

      expect((result as Ok<int>).value, 2);
      expect(announcements.saved, hasLength(1));
      expect(announcements.saved.single.title, 'تنبيه');
      expect(announcements.saved.single.body, 'مباريات الجمعة تبدأ مبكرًا');
      expect(notifications.countFor(uuidC), 1);
      expect(notifications.countFor(uuidD), 1);
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single, ['t1']);
    });

    test('a recipient in their quiet hours gets the push at 08:00', () async {
      // FakeClock is 12:00 UTC: 15:00 in Riyadh, 23:00 at UTC+11.
      final announcements = _FakeAnnouncements([
        const AnnouncementRecipient(
          userId: UserId(uuidC),
          tokens: ['t1'],
          utcOffsetMinutes: 180,
        ),
        const AnnouncementRecipient(
          userId: UserId(uuidD),
          tokens: ['t2'],
          utcOffsetMinutes: 660,
        ),
        // Quiet too, but no device to ring: the inbox row is all they get.
        const AnnouncementRecipient(
          userId: UserId(uuidA),
          tokens: [],
          utcOffsetMinutes: 660,
        ),
      ]);
      final notifications = InMemoryNotificationRepository();
      final sender = _RecordingSender();
      final queue = _FakeQueue();

      final result =
          await build(
            announcements: announcements,
            notifications: notifications,
            sender: sender,
            queue: queue,
          )(
            principal: principalUser(userId: uuidB, role: PlatformRole.admin),
            title: 'Notice',
            body: 'Body',
          );

      expect((result as Ok<int>).value, 3);
      expect(notifications.countFor(uuidD), 1);
      expect(notifications.countFor(uuidA), 1);
      expect(sender.sent.single, ['t1']);
      final push = queue.queued.single;
      expect(push.userId.value, uuidD);
      expect(push.title, 'Notice');
      expect(push.body, 'Body');
      // 23:00 on 5 July at UTC+11; 08:00 on the 6th there is 21:00 UTC.
      expect(push.deliverAfter, DateTime.utc(2026, 7, 5, 21));
    });

    test('a recipient who is awake queues nothing', () async {
      final queue = _FakeQueue();

      await build(
        announcements: _FakeAnnouncements([
          const AnnouncementRecipient(userId: UserId(uuidC), tokens: ['t1']),
        ]),
        notifications: InMemoryNotificationRepository(),
        sender: _RecordingSender(),
        queue: queue,
      )(
        principal: principalUser(userId: uuidB, role: PlatformRole.admin),
        title: 'Notice',
        body: 'Body',
      );

      expect(queue.queued, isEmpty);
    });
  });
}
