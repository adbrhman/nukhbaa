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
  }) async {
    sent.add(List<String>.unmodifiable(tokens));
    return const Result.ok(<String>[]);
  }
}

void main() {
  PublishAnnouncement build({
    required _FakeAnnouncements announcements,
    required InMemoryNotificationRepository notifications,
    required _RecordingSender sender,
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
  });
}
