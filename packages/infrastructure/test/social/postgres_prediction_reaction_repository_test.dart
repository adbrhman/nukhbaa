import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_notification_repository.dart';
import 'package:infrastructure/src/social/postgres_prediction_reaction_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
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

const _season = '11111111-1111-4111-8111-111111111111';
const _fixture = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _target = '44444444-4444-4444-8444-444444444444';
const _other = '55555555-5555-4555-8555-555555555555';
const _owner = '66666666-6666-4666-8666-666666666666';
const _reactor = '22222222-2222-4222-8222-222222222222';

SeasonId _seasonId() => (SeasonId.tryParse(_season) as Ok<SeasonId>).value;
FixtureRef _ref() => (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value;
ParticipantId _participant(String id) =>
    (ParticipantId.tryParse(id) as Ok<ParticipantId>).value;

/// Hermetic tests of the binding and row mapping. The statements run
/// against migration 0094 in supabase/tests/0094_prediction_reactions_test.sql.
void main() {
  final at = DateTime.utc(2026, 10, 6, 19);

  group('upsert', () {
    test('binds every value and reads a first reaction back', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'inserted': true, 'target_user_id': _owner},
        ]),
      );

      final result = await PostgresPredictionReactionRepository(connection)
          .upsert(
            id: 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1',
            seasonId: _seasonId(),
            fixture: _ref(),
            target: _participant(_target),
            reactor: const UserId(_reactor),
            kind: ReactionKind.fire,
            reactedAt: at,
          );

      final write = (result as Ok<PredictionReactionWrite>).value;
      expect(write.inserted, isTrue);
      expect(write.targetUserId, const UserId(_owner));
      expect(
        connection.sqls.single,
        PostgresPredictionReactionRepository.upsertSql,
      );
      expect(connection.params.single, {
        'id': 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1',
        'season_id': _season,
        'fixture_id': _fixture,
        'target_participant_id': _target,
        'user_id': _reactor,
        'emoji': 'fire',
        'reacted_at': at,
      });
    });

    test('a row without a boolean is corrupt, not a guess', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'inserted': 'yes', 'target_user_id': _owner},
        ]),
      );

      final result = await PostgresPredictionReactionRepository(connection)
          .upsert(
            id: 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1',
            seasonId: _seasonId(),
            fixture: _ref(),
            target: _participant(_target),
            reactor: const UserId(_reactor),
            kind: ReactionKind.fire,
            reactedAt: at,
          );

      expect(
        (result as Err<PredictionReactionWrite>).error.code,
        'social.prediction_reaction_row_corrupt',
      );
    });
  });

  test('remove answers whether a reaction was there', () async {
    final removed = _FakeConnection(
      const Result.ok([
        {'id': 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1'},
      ]),
    );
    final none = _FakeConnection(const Result.ok([]));

    final yes = await PostgresPredictionReactionRepository(removed).remove(
      fixture: _ref(),
      target: _participant(_target),
      reactor: const UserId(_reactor),
    );
    final no = await PostgresPredictionReactionRepository(none).remove(
      fixture: _ref(),
      target: _participant(_target),
      reactor: const UserId(_reactor),
    );

    expect((yes as Ok<bool>).value, isTrue);
    expect((no as Ok<bool>).value, isFalse);
    expect(removed.params.single, {
      'fixture_id': _fixture,
      'target_participant_id': _target,
      'user_id': _reactor,
    });
  });

  test('tallies group the rows of each prediction', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {
          'target_participant_id': _target,
          'emoji': 'fire',
          'reactions': 2,
          'mine': true,
        },
        {
          'target_participant_id': _target,
          'emoji': 'clap',
          'reactions': 1,
          'mine': false,
        },
        {
          'target_participant_id': _other,
          'emoji': 'sad',
          'reactions': 3,
          'mine': false,
        },
      ]),
    );

    final result = await PostgresPredictionReactionRepository(connection)
        .tallies(
          seasonId: _seasonId(),
          fixture: _ref(),
          viewer: const UserId(_reactor),
        );

    final tallies = (result as Ok<List<PredictionReactionTally>>).value;
    final byTarget = {for (final t in tallies) t.targetParticipantId.value: t};
    expect(byTarget[_target]!.counts, {
      ReactionKind.fire: 2,
      ReactionKind.clap: 1,
    });
    expect(byTarget[_target]!.mine, ReactionKind.fire);
    expect(byTarget[_target]!.total, 3);
    expect(byTarget[_other]!.counts, {ReactionKind.sad: 3});
    expect(byTarget[_other]!.mine, isNull);
    expect(connection.params.single, {
      'season_id': _season,
      'fixture_id': _fixture,
      'viewer': _reactor,
    });
  });

  test('an unknown reaction kind in a row is corrupt', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {
          'target_participant_id': _target,
          'emoji': 'heart',
          'reactions': 1,
          'mine': false,
        },
      ]),
    );

    final result = await PostgresPredictionReactionRepository(connection)
        .tallies(
          seasonId: _seasonId(),
          fixture: _ref(),
          viewer: const UserId(_reactor),
        );

    expect(
      (result as Err<List<PredictionReactionTally>>).error.code,
      'social.prediction_reaction_row_corrupt',
    );
  });

  test('a prediction_reaction notification reads back its subject', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {
          'id': 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1',
          'recipient_id': _owner,
          'kind': 'prediction_reaction',
          'round_id': null,
          'group_id': null,
          'actor_user_id': _reactor,
          'fixture_id': _fixture,
          'announcement_id': null,
          'duel_challenge_id': null,
          'read_at': null,
          'created_at': '2026-10-06T19:00:00.000Z',
        },
      ]),
    );

    final result = await PostgresNotificationRepository(
      connection,
    ).listForRecipient(const UserId(_owner), limit: 10);

    final row = (result as Ok<List<Notification>>).value.single;
    expect(row.kind, NotificationKind.predictionReaction);
    expect(row.subject.fixture, _ref());
    expect(row.subject.actorUserId, const UserId(_reactor));
  });
}
