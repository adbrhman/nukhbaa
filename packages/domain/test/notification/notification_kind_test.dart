import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('NotificationKind', () {
    test('has exactly the ratified kinds (closed set)', () {
      expect(NotificationKind.values, hasLength(5));
      expect(NotificationKind.values.toSet(), {
        NotificationKind.roundScored,
        NotificationKind.groupMemberJoined,
        NotificationKind.reactionReceived,
        NotificationKind.fixtureScored,
        NotificationKind.adminAnnouncement,
      });
    });

    test('carries stable wire tokens', () {
      expect(NotificationKind.roundScored.wireValue, 'round_scored');
      expect(
        NotificationKind.groupMemberJoined.wireValue,
        'group_member_joined',
      );
      expect(NotificationKind.reactionReceived.wireValue, 'reaction_received');
      expect(NotificationKind.fixtureScored.wireValue, 'fixture_scored');
      expect(
        NotificationKind.adminAnnouncement.wireValue,
        'admin_announcement',
      );
    });

    test('tryParse round-trips every kind', () {
      for (final kind in NotificationKind.values) {
        final parsed = NotificationKind.tryParse(kind.wireValue);
        expect((parsed as Ok<NotificationKind>).value, kind);
      }
    });

    test('tryParse rejects an unknown/null token as validation', () {
      final r1 = NotificationKind.tryParse('comment_posted');
      final r2 = NotificationKind.tryParse(null);
      expect((r1 as Err<NotificationKind>).error.kind, ErrorKind.validation);
      expect(r1.error.code, 'notification.kind_unknown');
      expect(
        (r2 as Err<NotificationKind>).error.code,
        'notification.kind_unknown',
      );
    });
  });
}
