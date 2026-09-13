import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _id = AnnouncementId('11111111-1111-4111-8111-111111111111');
const _author = UserId('22222222-2222-4222-8222-222222222222');
final _now = DateTime.utc(2026, 9, 13, 12);

void main() {
  group('Announcement.create', () {
    test('trims the title and body', () {
      final result = Announcement.create(
        id: _id,
        authorId: _author,
        title: '  تنبيه  ',
        body: '  التعليمات  ',
        createdAt: _now,
      );
      final announcement = (result as Ok<Announcement>).value;
      expect(announcement.title, 'تنبيه');
      expect(announcement.body, 'التعليمات');
    });

    test('refuses a blank title', () {
      final result = Announcement.create(
        id: _id,
        authorId: _author,
        title: '   ',
        body: 'التعليمات',
        createdAt: _now,
      );
      expect((result as Err<Announcement>).error.kind, ErrorKind.validation);
      expect(result.error.code, 'notification.announcement_title_empty');
    });

    test('refuses an over-long body', () {
      final result = Announcement.create(
        id: _id,
        authorId: _author,
        title: 'تنبيه',
        body: 'x' * (Announcement.maxBodyLength + 1),
        createdAt: _now,
      );
      expect(
        (result as Err<Announcement>).error.code,
        'notification.announcement_body_too_long',
      );
    });

    test('refuses a non-UTC createdAt', () {
      final result = Announcement.create(
        id: _id,
        authorId: _author,
        title: 'تنبيه',
        body: 'التعليمات',
        createdAt: DateTime(2026, 9, 13, 12),
      );
      expect(
        (result as Err<Announcement>).error.code,
        'notification.announcement_created_at_not_utc',
      );
    });
  });

  group('NotificationSubject.adminAnnouncement', () {
    test('dedupes on the announcement id', () {
      final subject = NotificationSubject.adminAnnouncement(
        announcementId: _id,
      );
      expect(subject.kind, NotificationKind.adminAnnouncement);
      expect(subject.announcementId, _id);
      expect(subject.dedupeRef, 'announcement:${_id.value}');
    });
  });
}
