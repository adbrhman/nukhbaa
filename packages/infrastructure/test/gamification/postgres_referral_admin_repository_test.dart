import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_referral_admin_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// The states themselves come from gamification.referral_invitations, tested
// against a real Postgres by supabase/tests/0075_referral_idle_test.sql.

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

void main() {
  test('overview reads the switch, the counts, the inviters and the '
      'invitations', () async {
    final conn = _FakeConnection([
      const Result.ok([
        {'enabled': true},
      ]),
      Result.ok([
        {'state': 'paid', 'n': BigInt.from(3)},
        {'state': 'held', 'n': BigInt.one},
      ]),
      Result.ok([
        {
          'referrer_id': 'r-1',
          'referrer_name': 'Ali',
          'invited': BigInt.from(4),
          'paid': BigInt.from(3),
          'pending': BigInt.zero,
          'held': BigInt.one,
          'refused': BigInt.zero,
          'month_points': BigInt.from(3),
        },
      ]),
      Result.ok([
        {
          'invitee_id': 'i-1',
          'invitee_name': 'Badr',
          'invitee_status': 'suspended',
          'referrer_id': 'r-1',
          'referrer_name': 'Ali',
          'claimed_at': DateTime.utc(2026, 10, 1, 7),
          'state': 'revoked',
          'paid_at': DateTime.utc(2026, 10, 3, 9),
          'held_at': null,
          'revoked_at': DateTime.utc(2026, 10, 11, 9),
          'hold_reasons': '',
          'revoke_reason': 'inactive_7_days',
          'last_prediction_at': DateTime.utc(2026, 10, 2, 9),
        },
      ]),
    ]);

    final result = await PostgresReferralAdminRepository(conn).overview(
      now: DateTime.utc(2026, 10, 15),
      referrerLimit: 100,
      invitationLimit: 300,
    );

    final overview = (result as Ok<ReferralOverview>).value;
    expect(overview.enabled, isTrue);
    expect(overview.stateCounts, {'paid': 3, 'held': 1});
    expect(overview.referrers.single.monthPoints, 3);
    final invitation = overview.invitations.single;
    expect(invitation.inviteeStatus, 'suspended');
    expect(invitation.revokeReason, 'inactive_7_days');
    expect(invitation.holdReasons, isEmpty);
    expect(conn.sqls[0], contains('gamification.feature_flags'));
    expect(conn.sqls[3], contains('gamification.referral_invitations'));
    expect(conn.parameters[3], {'limit': 300});
  });

  test('setEnabled answers what the database stored', () async {
    final conn = _FakeConnection([
      const Result.ok([
        {'enabled': false},
      ]),
    ]);
    final result = await PostgresReferralAdminRepository(
      conn,
    ).setEnabled(enabled: false);
    expect((result as Ok<bool>).value, isFalse);
    expect(conn.parameters.single, {'enabled': false});
    expect(conn.sqls.single, contains("flag_key = 'referrals'"));
  });

  test('a missing switch row is an error, not a silent success', () async {
    final result = await PostgresReferralAdminRepository(
      _FakeConnection([const Result.ok([])]),
    ).setEnabled(enabled: true);
    expect((result as Err<bool>).error.code, 'referral.switch_missing');
  });
}
