import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('NotificationKind', () {
    test('has exactly the ratified kinds (closed set)', () {
      expect(NotificationKind.values, hasLength(10));
      expect(NotificationKind.values.toSet(), {
        NotificationKind.roundScored,
        NotificationKind.groupMemberJoined,
        NotificationKind.reactionReceived,
        NotificationKind.fixtureScored,
        NotificationKind.adminAnnouncement,
        NotificationKind.duelChallenged,
        NotificationKind.duelAccepted,
        NotificationKind.predictionReaction,
        NotificationKind.groupInvited,
        NotificationKind.doubleReleased,
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
      expect(NotificationKind.doubleReleased.wireValue, 'double_released');
    });

    test('a released double is one per player and hidden fixture', () {
      const fixture = FixtureRef('66666666-6666-4666-8666-666666666666');
      final subject = NotificationSubject.doubleReleased(fixture: fixture);
      expect(subject.kind, NotificationKind.doubleReleased);
      expect(subject.fixture, fixture);
      expect(
        subject.dedupeRef,
        'double_released:66666666-6666-4666-8666-666666666666',
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
