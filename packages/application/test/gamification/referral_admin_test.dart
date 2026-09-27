import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-4333-8444-555555555555';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 15, 12);
}

final class _FakeAdmin implements ReferralAdminRepository {
  final List<String> calls = [];
  bool? stored;
  int? referrerLimit;
  int? invitationLimit;

  @override
  Future<Result<ReferralOverview>> overview({
    required DateTime now,
    required int referrerLimit,
    required int invitationLimit,
  }) async {
    calls.add('overview');
    this.referrerLimit = referrerLimit;
    this.invitationLimit = invitationLimit;
    return const Result.ok(
      ReferralOverview(
        enabled: true,
        stateCounts: {'paid': 3, 'held': 1},
        referrers: [],
        invitations: [],
      ),
    );
  }

  @override
  Future<Result<bool>> setEnabled({required bool enabled}) async {
    calls.add('setEnabled');
    stored = enabled;
    return Result.ok(enabled);
  }
}

const _player = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);
const _admin = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.admin,
);

void main() {
  group('AdminGetReferralOverview', () {
    test('an admin reads the overview within the limits', () async {
      final repo = _FakeAdmin();
      final result = await AdminGetReferralOverview(
        referrals: repo,
        clock: const _FixedClock(),
      )(principal: _admin);
      final overview = (result as Ok<ReferralOverview>).value;
      expect(overview.enabled, isTrue);
      expect(overview.stateCounts['paid'], 3);
      expect(repo.referrerLimit, AdminGetReferralOverview.referrerLimit);
      expect(repo.invitationLimit, AdminGetReferralOverview.invitationLimit);
    });

    test('a player is refused', () async {
      final repo = _FakeAdmin();
      final result = await AdminGetReferralOverview(
        referrals: repo,
        clock: const _FixedClock(),
      )(principal: _player);
      expect(
        (result as Err<ReferralOverview>).error.code,
        'auth.insufficient_role',
      );
      expect(repo.calls, isEmpty);
    });
  });

  group('AdminSetReferralsEnabled', () {
    test('an admin turns the system off and on', () async {
      final repo = _FakeAdmin();
      final useCase = AdminSetReferralsEnabled(referrals: repo);
      final off = await useCase(principal: _admin, enabled: false);
      expect((off as Ok<bool>).value, isFalse);
      expect(repo.stored, isFalse);
      final on = await useCase(principal: _admin, enabled: true);
      expect((on as Ok<bool>).value, isTrue);
    });

    test('a player or a missing value is refused, nothing stored', () async {
      final repo = _FakeAdmin();
      final useCase = AdminSetReferralsEnabled(referrals: repo);
      final player = await useCase(principal: _player, enabled: false);
      final missing = await useCase(principal: _admin, enabled: null);
      expect((player as Err<bool>).error.code, 'auth.insufficient_role');
      expect((missing as Err<bool>).error.code, 'referral.enabled_required');
      expect(repo.calls, isEmpty);
    });
  });
}
