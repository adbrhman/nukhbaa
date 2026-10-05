import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_notification_repository.dart';
import 'package:infrastructure/src/social/postgres_duel_notice_reader.dart';
import 'package:infrastructure/src/social/postgres_duel_player_directory.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// Hermetic tests for the duel notification adapters (migration 0092): the
// SQL itself is checked against Postgres by supabase/tests; these pin the
// bindings and the row mapping.

const _challengeId = '11111111-1111-4111-8111-111111111111';
const _duelId = '22222222-2222-4222-8222-222222222222';
const _recipientId = '33333333-3333-4333-8333-333333333333';
const _actorId = '44444444-4444-4444-8444-444444444444';
const _notificationId = '55555555-5555-4555-8555-555555555555';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

_FakeConnection _rows(List<Map<String, dynamic>> rows) =>
    _FakeConnection(Result.ok(rows));

Map<String, dynamic> _noticeRow({String tokens = 'tok-1,tok-2'}) => {
  'recipient_id': _recipientId,
  'actor_id': _actorId,
  'actor_name': 'Ali',
  'code': 'ABCDEFGHJKMN',
  'home_team': 'Home',
  'away_team': 'Away',
  'utc_offset_minutes': 180,
  'tokens': tokens,
};

void main() {
  group('PostgresDuelNoticeReader', () {
    test('reads the private target of a challenge with its tokens', () async {
      final conn = _rows([_noticeRow()]);

      final result = await PostgresDuelNoticeReader(
        conn,
      ).challengedNotice(const DuelChallengeId(_challengeId));

      final notice = (result as Ok<DuelNotice?>).value!;
      expect(notice.recipientUserId, const UserId(_recipientId));
      expect(notice.actorUserId, const UserId(_actorId));
      expect(notice.actorName, 'Ali');
      expect(notice.code, 'ABCDEFGHJKMN');
      expect(notice.tokens, ['tok-1', 'tok-2']);
      expect(notice.utcOffsetMinutes, 180);
      expect(conn.sqls.single, contains('FROM social.duel_challenges c'));
      expect(conn.parameters.single, {'challenge_id': _challengeId});
    });

    test('a player with no device has no tokens', () async {
      final result = await PostgresDuelNoticeReader(
        _rows([_noticeRow(tokens: '')]),
      ).acceptedNotice(const DuelId(_duelId));

      expect((result as Ok<DuelNotice?>).value!.tokens, isEmpty);
    });

    test('reads the challenger behind a duel', () async {
      final conn = _rows([_noticeRow()]);

      await PostgresDuelNoticeReader(
        conn,
      ).acceptedNotice(const DuelId(_duelId));

      expect(conn.sqls.single, contains('FROM social.duels d'));
      expect(conn.parameters.single, {'duel_id': _duelId});
    });

    test('nothing found is Ok(null); a bad row is row_corrupt', () async {
      final none = await PostgresDuelNoticeReader(
        _rows(const []),
      ).challengedNotice(const DuelChallengeId(_challengeId));
      expect((none as Ok<DuelNotice?>).value, isNull);

      final bad = await PostgresDuelNoticeReader(
        _rows([
          {..._noticeRow(), 'code': null},
        ]),
      ).challengedNotice(const DuelChallengeId(_challengeId));
      expect((bad as Err<DuelNotice?>).error.code, 'social.row_corrupt');
    });
  });

  group('PostgresDuelPlayerDirectory', () {
    test('binds the query, the caller and the limit', () async {
      final conn = _rows([
        {'user_id': _recipientId, 'display_name': 'Badr'},
      ]);

      final result = await PostgresDuelPlayerDirectory(
        conn,
      ).search(query: 'Bad', excluding: const UserId(_actorId), limit: 20);

      final player = (result as Ok<List<DuelPlayer>>).value.single;
      expect(player.userId, const UserId(_recipientId));
      expect(player.displayName, 'Badr');
      expect(conn.parameters.single, {
        'query': 'Bad',
        'excluding': _actorId,
        'limit': 20,
      });
      expect(conn.sqls.single, contains("u.status = 'active'"));
    });

    test('a row without a name is row_corrupt', () async {
      final result = await PostgresDuelPlayerDirectory(
        _rows([
          {'user_id': _recipientId, 'display_name': null},
        ]),
      ).search(query: 'Bad', excluding: const UserId(_actorId), limit: 20);

      expect(
        (result as Err<List<DuelPlayer>>).error.code,
        'social.row_corrupt',
      );
    });
  });

  group('PostgresNotificationRepository with duel kinds', () {
    test('stores the challenge of a duel notification', () async {
      final conn = _rows([
        {'id': _notificationId},
      ]);

      final result = await PostgresNotificationRepository(conn).createIfAbsent(
        Notification.fromStored(
          id: const NotificationId(_notificationId),
          recipientId: const UserId(_recipientId),
          kind: NotificationKind.duelChallenged,
          subject: NotificationSubject.duelChallenged(
            challengeId: const DuelChallengeId(_challengeId),
            actorUserId: const UserId(_actorId),
          ),
          createdAt: DateTime.utc(2026, 10, 5, 12),
          readAt: null,
        ),
      );

      expect((result as Ok<bool>).value, isTrue);
      final params = conn.parameters.single;
      expect(params['kind'], 'duel_challenged');
      expect(params['duel_challenge_id'], _challengeId);
      expect(params['actor_user_id'], _actorId);
      expect(params['subject_ref'], 'duel_challenged:$_challengeId');
    });

    test('reads a duel_accepted row back', () async {
      final conn = _rows([
        {
          'id': _notificationId,
          'recipient_id': _recipientId,
          'kind': 'duel_accepted',
          'round_id': null,
          'group_id': null,
          'actor_user_id': _actorId,
          'fixture_id': null,
          'announcement_id': null,
          'duel_challenge_id': _challengeId,
          'read_at': null,
          'created_at': '2026-10-05T12:00:00.000Z',
        },
      ]);

      final result = await PostgresNotificationRepository(
        conn,
      ).listForRecipient(const UserId(_recipientId), limit: 10);

      final row = (result as Ok<List<Notification>>).value.single;
      expect(row.kind, NotificationKind.duelAccepted);
      expect(row.subject.duelChallengeId, const DuelChallengeId(_challengeId));
      expect(row.subject.actorUserId, const UserId(_actorId));
      expect(conn.sqls.single, contains('duel_challenge_id'));
    });

    test('a duel row without its challenge is row_corrupt', () async {
      final result = await PostgresNotificationRepository(
        _rows([
          {
            'id': _notificationId,
            'recipient_id': _recipientId,
            'kind': 'duel_challenged',
            'actor_user_id': _actorId,
            'duel_challenge_id': null,
            'read_at': null,
            'created_at': '2026-10-05T12:00:00.000Z',
          },
        ]),
      ).listForRecipient(const UserId(_recipientId), limit: 10);

      expect(
        (result as Err<List<Notification>>).error.code,
        'notification.row_corrupt',
      );
    });
  });
}
