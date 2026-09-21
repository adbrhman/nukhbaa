import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_announcement_repository.dart';
import 'package:infrastructure/src/notification/postgres_score_announcement_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _pA = '11111111-1111-4111-8111-111111111111';
const _pB = '22222222-2222-4222-8222-222222222222';
const _userA = '33333333-3333-4333-8333-333333333333';
const _userB = '44444444-4444-4444-8444-444444444444';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

/// Hermetic unit tests for the two readers that hand a push its audience:
/// each carries the reader's own clock (`identity.users.utc_offset_minutes`)
/// so the use-cases can hold a push back in the quiet hours (P3-2c). That the
/// join itself returns the right rows is checked by hand on the live database.
void main() {
  group('PostgresScoreAnnouncementRepository.targetsForParticipants', () {
    test('answers each target with the clock its user reported', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {
            'participant_id': _pA,
            'user_id': _userA,
            'token': 't1',
            'utc_offset_minutes': 180,
          },
          {
            'participant_id': _pA,
            'user_id': _userA,
            'token': 't2',
            'utc_offset_minutes': 180,
          },
          {
            'participant_id': _pB,
            'user_id': _userB,
            'token': 't3',
            'utc_offset_minutes': null,
          },
        ]),
      );

      final result = await PostgresScoreAnnouncementRepository(connection)
          .targetsForParticipants([
            (ParticipantId.tryParse(_pA) as Ok<ParticipantId>).value,
            (ParticipantId.tryParse(_pB) as Ok<ParticipantId>).value,
          ]);

      final targets = (result as Ok<List<ScoreNoticeTarget>>).value;
      expect(targets, hasLength(2));
      expect(targets[0].tokens, ['t1', 't2']);
      expect(targets[0].utcOffsetMinutes, 180);
      expect(targets[1].utcOffsetMinutes, isNull);
      expect(connection.sqls.single, contains('u.utc_offset_minutes'));
    });
  });

  group('PostgresAnnouncementRepository.audience', () {
    test('answers each recipient with the clock its user reported', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'user_id': _userA, 'token': 't1', 'utc_offset_minutes': 660},
          // No device on file: still part of the audience.
          {'user_id': _userB, 'token': null, 'utc_offset_minutes': null},
        ]),
      );

      final result = await PostgresAnnouncementRepository(
        connection,
      ).audience();

      final audience = (result as Ok<List<AnnouncementRecipient>>).value;
      expect(audience, hasLength(2));
      expect(audience[0].tokens, ['t1']);
      expect(audience[0].utcOffsetMinutes, 660);
      expect(audience[1].tokens, isEmpty);
      expect(audience[1].utcOffsetMinutes, isNull);
      expect(connection.sqls.single, contains('u.utc_offset_minutes'));
    });
  });
}
