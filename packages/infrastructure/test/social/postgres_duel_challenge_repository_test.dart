import 'dart:io';

import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/social/postgres_duel_challenge_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// The duel rules themselves run against a real Postgres in
// supabase/tests/0090_duels_test.sql (db-tests workflow). These tests pin
// what this adapter owns: which function it calls, the values it binds, the
// read-back of the stored row, and the constraint-name table, which is
// checked against every name migration 0090 raises.

const _season = '11111111-1111-4111-8111-111111111111';
const _fixture = '22222222-2222-4222-8222-222222222222';
const _challenger = '33333333-3333-4333-8333-333333333333';
const _opponent = '44444444-4444-4444-8444-444444444444';
const _user = '55555555-5555-4555-8555-555555555555';
const _target = '66666666-6666-4666-8666-666666666666';
const _challenge = '77777777-7777-4777-8777-777777777777';
const _duel = '88888888-8888-4888-8888-888888888888';

final DateTime _now = DateTime.utc(2026, 10, 5, 12);
final DateTime _stamp = DateTime.utc(2026, 10, 5, 12, 0, 1);

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;
  int transactions = 0;

  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    final response =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async {
    transactions++;
    return action(this);
  }

  @override
  Future<void> close() async {}
}

const Result<List<Map<String, dynamic>>> _failure = Result.err(
  AppError.transient('db.query_failed', 'Database query failed'),
);

Map<String, dynamic> _challengeRow({
  Object? target,
  Object capacity = 5,
  Object status = 'open',
}) => {
  'id': _challenge,
  'code': 'ABCDEFGHJKMN',
  'season_id': _season,
  'fixture_id': _fixture,
  'challenger_participant_id': _challenger,
  'target_user_id': target,
  'capacity': capacity,
  'status': status,
  'created_at': _stamp,
  'updated_at': _stamp,
};

Map<String, dynamic> _duelRow() => {
  'id': _duel,
  'challenge_id': _challenge,
  'fixture_id': _fixture,
  'challenger_participant_id': _challenger,
  'opponent_participant_id': _opponent,
  'accepted_at': _stamp,
  'created_at': _stamp,
};

void main() {
  group('createChallenge', () {
    test('calls create_duel_challenge then reads the row back in one '
        'transaction', () async {
      final conn = _FakeConnection([
        const Result.ok([
          {'id': _challenge},
        ]),
        Result.ok([_challengeRow()]),
      ]);
      final result = await PostgresDuelChallengeRepository(conn)
          .createChallenge(
            seasonId: const SeasonId(_season),
            fixture: const FixtureRef(_fixture),
            challengerParticipantId: const ParticipantId(_challenger),
            targetUserId: null,
            capacity: 5,
            nowUtc: _now,
          );

      final challenge = (result as Ok<DuelChallenge>).value;
      expect(challenge.id, const DuelChallengeId(_challenge));
      expect(challenge.code.value, 'ABCDEFGHJKMN');
      expect(challenge.seasonId, const SeasonId(_season));
      expect(challenge.fixture, const FixtureRef(_fixture));
      expect(
        challenge.challengerParticipantId,
        const ParticipantId(_challenger),
      );
      expect(challenge.targetUserId, isNull);
      expect(challenge.capacity, 5);
      expect(challenge.status, DuelChallengeStatus.open);
      expect(challenge.createdAt, _stamp);

      expect(conn.transactions, 1);
      expect(conn.sqls, hasLength(2));
      expect(conn.sqls.first, contains('social.create_duel_challenge('));
      expect(conn.sqls.first, contains('FROM competition.participants p'));
      expect(conn.parameters.first, {
        'challenger_participant_id': _challenger,
        'season_id': _season,
        'fixture_id': _fixture,
        'capacity': 5,
        'target_user_id': null,
        'now': _now,
      });
      expect(conn.sqls.last, contains('FROM social.duel_challenges c'));
      expect(conn.parameters.last, {'challenge_id': _challenge});
    });

    test('binds and maps a private target', () async {
      final conn = _FakeConnection([
        const Result.ok([
          {'id': _challenge},
        ]),
        Result.ok([_challengeRow(target: _target, capacity: 1)]),
      ]);
      final result = await PostgresDuelChallengeRepository(conn)
          .createChallenge(
            seasonId: const SeasonId(_season),
            fixture: const FixtureRef(_fixture),
            challengerParticipantId: const ParticipantId(_challenger),
            targetUserId: const UserId(_target),
            capacity: 1,
            nowUtc: _now,
          );

      final challenge = (result as Ok<DuelChallenge>).value;
      expect(challenge.targetUserId, const UserId(_target));
      expect(challenge.capacity, 1);
      expect(challenge.isPrivate, isTrue);
      expect(conn.parameters.first['target_user_id'], _target);
      expect(conn.parameters.first['capacity'], 1);
    });

    test(
      'a non-database failure stays transient and skips the read-back',
      () async {
        final conn = _FakeConnection([_failure]);
        final result = await PostgresDuelChallengeRepository(conn)
            .createChallenge(
              seasonId: const SeasonId(_season),
              fixture: const FixtureRef(_fixture),
              challengerParticipantId: const ParticipantId(_challenger),
              targetUserId: null,
              capacity: 5,
              nowUtc: _now,
            );

        final error = (result as Err<DuelChallenge>).error;
        expect(error.code, 'db.query_failed');
        expect(error.kind, ErrorKind.transient);
        expect(conn.sqls, hasLength(1));
      },
    );

    test('no id from the function is a corrupt result', () async {
      final conn = _FakeConnection([const Result.ok([])]);
      final result = await PostgresDuelChallengeRepository(conn)
          .createChallenge(
            seasonId: const SeasonId(_season),
            fixture: const FixtureRef(_fixture),
            challengerParticipantId: const ParticipantId(_challenger),
            targetUserId: null,
            capacity: 5,
            nowUtc: _now,
          );

      expect((result as Err<DuelChallenge>).error.code, 'social.row_corrupt');
      expect(conn.sqls, hasLength(1));
    });
  });

  group('findChallenge', () {
    test('returns null for a missing challenge', () async {
      final conn = _FakeConnection([const Result.ok([])]);
      final result = await PostgresDuelChallengeRepository(
        conn,
      ).findChallenge(const DuelChallengeId(_challenge));

      expect((result as Ok<DuelChallenge?>).value, isNull);
      expect(conn.parameters.single, {'challenge_id': _challenge});
    });

    test('maps a cancelled challenge', () async {
      final conn = _FakeConnection([
        Result.ok([_challengeRow(status: 'cancelled')]),
      ]);
      final result = await PostgresDuelChallengeRepository(
        conn,
      ).findChallenge(const DuelChallengeId(_challenge));

      final challenge = (result as Ok<DuelChallenge?>).value!;
      expect(challenge.status, DuelChallengeStatus.cancelled);
      expect(challenge.isOpen, isFalse);
    });

    test('an unknown status is a corrupt row, never a default', () async {
      final conn = _FakeConnection([
        Result.ok([_challengeRow(status: 'accepted')]),
      ]);
      final result = await PostgresDuelChallengeRepository(
        conn,
      ).findChallenge(const DuelChallengeId(_challenge));

      final error = (result as Err<DuelChallenge?>).error;
      expect(error.code, 'social.row_corrupt');
      expect(error.message, contains('status'));
    });

    test('a non-integer capacity is a corrupt row', () async {
      final conn = _FakeConnection([
        Result.ok([_challengeRow(capacity: '5')]),
      ]);
      final result = await PostgresDuelChallengeRepository(
        conn,
      ).findChallenge(const DuelChallengeId(_challenge));

      final error = (result as Err<DuelChallenge?>).error;
      expect(error.code, 'social.row_corrupt');
      expect(error.message, contains('capacity'));
    });
  });

  group('acceptChallenge', () {
    test('calls accept_duel_challenge then reads the duel back', () async {
      final conn = _FakeConnection([
        const Result.ok([
          {'id': _duel},
        ]),
        Result.ok([_duelRow()]),
      ]);
      final result = await PostgresDuelChallengeRepository(conn)
          .acceptChallenge(
            challengeId: const DuelChallengeId(_challenge),
            opponentUserId: const UserId(_user),
            nowUtc: _now,
          );

      final duel = (result as Ok<Duel>).value;
      expect(duel.id, const DuelId(_duel));
      expect(duel.challengeId, const DuelChallengeId(_challenge));
      expect(duel.fixture, const FixtureRef(_fixture));
      expect(duel.challengerParticipantId, const ParticipantId(_challenger));
      expect(duel.opponentParticipantId, const ParticipantId(_opponent));
      expect(duel.acceptedAt, _stamp);

      expect(conn.transactions, 1);
      expect(conn.sqls.first, contains('social.accept_duel_challenge('));
      expect(conn.parameters.first, {
        'challenge_id': _challenge,
        'opponent_user_id': _user,
        'now': _now,
      });
      expect(conn.sqls.last, contains('FROM social.duels d'));
      expect(conn.parameters.last, {'duel_id': _duel});
    });

    test('a missing read-back is a corrupt result', () async {
      final conn = _FakeConnection([
        const Result.ok([
          {'id': _duel},
        ]),
        const Result.ok([]),
      ]);
      final result = await PostgresDuelChallengeRepository(conn)
          .acceptChallenge(
            challengeId: const DuelChallengeId(_challenge),
            opponentUserId: const UserId(_user),
            nowUtc: _now,
          );

      expect((result as Err<Duel>).error.code, 'social.row_corrupt');
    });
  });

  group('cancel and decline', () {
    test('cancel calls cancel_duel_challenge with the challenger', () async {
      final conn = _FakeConnection([
        const Result.ok([
          {'done': 1},
        ]),
      ]);
      final result = await PostgresDuelChallengeRepository(conn)
          .cancelChallenge(
            challengeId: const DuelChallengeId(_challenge),
            challengerUserId: const UserId(_user),
          );

      expect(result, isA<Ok<void>>());
      expect(conn.sqls.single, contains('social.cancel_duel_challenge('));
      expect(conn.parameters.single, {
        'challenge_id': _challenge,
        'challenger_user_id': _user,
      });
    });

    test('decline calls decline_duel_challenge with the target', () async {
      final conn = _FakeConnection([
        const Result.ok([
          {'done': 1},
        ]),
      ]);
      final result = await PostgresDuelChallengeRepository(conn)
          .declineChallenge(
            challengeId: const DuelChallengeId(_challenge),
            targetUserId: const UserId(_target),
          );

      expect(result, isA<Ok<void>>());
      expect(conn.sqls.single, contains('social.decline_duel_challenge('));
      expect(conn.parameters.single, {
        'challenge_id': _challenge,
        'target_user_id': _target,
      });
    });

    test('a transient failure passes through unchanged', () async {
      final conn = _FakeConnection([_failure]);
      final result = await PostgresDuelChallengeRepository(conn)
          .declineChallenge(
            challengeId: const DuelChallengeId(_challenge),
            targetUserId: const UserId(_target),
          );

      expect((result as Err<void>).error.code, 'db.query_failed');
    });
  });

  group('constraint table', () {
    test('every constraint name raised by migration 0090 is mapped', () {
      final sql = File(
        '../../supabase/migrations/0090_duels.sql',
      ).readAsStringSync();
      final raised = RegExp(
        r"constraint\s*=\s*'([a-z_]+)'",
      ).allMatches(sql).map((m) => m.group(1)!).toSet();

      expect(raised, isNotEmpty);
      for (final name in raised) {
        expect(
          PostgresDuelChallengeRepository.errorForConstraint(name),
          isNotNull,
          reason: '$name is raised by 0090 but has no mapping',
        );
      }
    });

    test('codes match the application layer where both exist', () {
      AppError? of(String name) =>
          PostgresDuelChallengeRepository.errorForConstraint(name);

      expect(of('duel_wrong_target')!.kind, ErrorKind.authorization);
      expect(of('duel_wrong_target')!.code, 'social.duel_wrong_target');
      expect(
        of('duel_challenges_capacity_range')!.code,
        'social.duel_capacity_out_of_range',
      );
      expect(
        of('duel_challenges_private_capacity')!.code,
        'social.duel_private_capacity_invalid',
      );
      expect(of('duel_not_open')!.code, 'social.duel_challenge_not_open');
      expect(of('duel_not_found')!.code, 'social.duel_challenge_not_found');
      expect(
        of('duels_fixture_pair_uniq')!.code,
        'social.duel_pair_already_exists',
      );
      expect(of('some_other_constraint'), isNull);
    });
  });
}
