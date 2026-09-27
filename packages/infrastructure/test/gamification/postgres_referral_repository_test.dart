import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_referral_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// The rules themselves are exercised against a real Postgres by
// supabase/tests/0073_referrals_test.sql (db-tests workflow). These tests pin
// what this adapter owns: which function it calls, the values it binds, and
// how it maps the rows back.

const _user = '11111111-2222-4333-8444-555555555555';
const _invitee = '66666666-7777-4888-8999-000000000000';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;

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
  ) async => action(this);

  @override
  Future<void> close() async {}
}

_FakeConnection _rows(List<Map<String, dynamic>> rows) =>
    _FakeConnection([Result.ok(rows)]);

final DateTime _now = DateTime.utc(2026, 10, 15, 12);

void main() {
  test('ensureCode calls ensure_referral_code and returns the code', () async {
    final conn = _rows([
      {'code': 'ABCDEFGH'},
    ]);
    final result = await PostgresReferralRepository(
      conn,
    ).ensureCode(const UserId(_user));
    expect((result as Ok<String>).value, 'ABCDEFGH');
    expect(conn.sqls.single, contains('gamification.ensure_referral_code'));
    expect(conn.parameters.single, {'user_id': _user});
  });

  test('counts maps the four counters, bigint or int', () async {
    final conn = _rows([
      {
        'month_points': BigInt.from(20),
        'season_points': 21,
        'invited_count': BigInt.from(27),
        'pending_count': 1,
      },
    ]);
    final result = await PostgresReferralRepository(
      conn,
    ).counts(userId: const UserId(_user), now: _now, seasonStartYear: 2026);
    final counts = (result as Ok<ReferralCounts>).value;
    expect(counts.monthPoints, 20);
    expect(counts.seasonPoints, 21);
    expect(counts.invitedCount, 27);
    expect(counts.pendingCount, 1);
    expect(conn.sqls.single, contains('gamification.referral_month_points'));
    expect(conn.sqls.single, contains('gamification.referral_season_points'));
    expect(conn.parameters.single['season_start_year'], 2026);
  });

  test('claim binds the raw values for the database to hash', () async {
    final conn = _rows([
      {'outcome': 'self_referral'},
    ]);
    final result = await PostgresReferralRepository(conn).claim(
      invitee: const UserId(_invitee),
      code: 'ABCDEFGH',
      ip: '10.0.0.1',
      installId: null,
      now: _now,
    );
    expect(
      (result as Ok<ReferralClaimOutcome>).value,
      ReferralClaimOutcome.selfReferral,
    );
    expect(conn.sqls.single, contains('gamification.claim_referral'));
    expect(conn.parameters.single['ip'], '10.0.0.1');
    expect(conn.parameters.single['install_id'], isNull);
  });

  test('an unknown claim outcome is a corrupt row, not a guess', () async {
    final result =
        await PostgresReferralRepository(
          _rows([
            {'outcome': 'maybe'},
          ]),
        ).claim(
          invitee: const UserId(_invitee),
          code: 'ABCDEFGH',
          ip: null,
          installId: null,
          now: _now,
        );
    expect(
      (result as Err<ReferralClaimOutcome>).error.code,
      'referral.row_corrupt',
    );
  });

  test('qualify returns the events written', () async {
    final conn = _rows([
      {'written': BigInt.from(3)},
    ]);
    final result = await PostgresReferralRepository(conn).qualify(now: _now);
    expect((result as Ok<int>).value, 3);
    expect(conn.sqls.single, contains('gamification.qualify_referrals'));
  });

  test('held maps the rows and splits the reasons', () async {
    final conn = _rows([
      {
        'invitee_id': _invitee,
        'invitee_name': 'Badr',
        'referrer_id': _user,
        'referrer_name': 'Ali',
        'claimed_at': DateTime.utc(2026, 10, 5, 6),
        'held_at': DateTime.utc(2026, 10, 10, 9),
        'reasons': 'shared_network,burst',
      },
    ]);
    final result = await PostgresReferralRepository(conn).held(limit: 50);
    final held = (result as Ok<List<HeldReferral>>).value.single;
    expect(held.inviteeName, 'Badr');
    expect(held.referrerName, 'Ali');
    expect(held.reasons, ['shared_network', 'burst']);
    expect(conn.parameters.single, {'limit': 50});
  });

  test('review binds the decision by its wire name', () async {
    final conn = _rows([
      {'outcome': 'revoked'},
    ]);
    final result = await PostgresReferralRepository(conn).review(
      invitee: const UserId(_invitee),
      decision: ReferralDecision.revoke,
      admin: const UserId(_user),
      reason: 'fake account',
      now: _now,
    );
    expect(
      (result as Ok<ReferralReviewOutcome>).value,
      ReferralReviewOutcome.revoked,
    );
    expect(conn.parameters.single['decision'], 'revoke');
    expect(conn.sqls.single, contains('gamification.review_referral'));
  });

  test('a query failure is passed through unchanged', () async {
    final result = await PostgresReferralRepository(
      _FakeConnection([
        const Result.err(
          AppError.transient('db.query_failed', 'Database query failed'),
        ),
      ]),
    ).qualify(now: _now);
    expect((result as Err<int>).error.code, 'db.query_failed');
  });
}
