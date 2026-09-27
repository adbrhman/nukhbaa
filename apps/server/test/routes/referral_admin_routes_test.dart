import 'dart:io';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/referral-overview/index.dart' as overview_route;
// ignore: always_use_package_imports
import '../../routes/admin/referral-switch/index.dart' as switch_route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 15, 12);
}

/// Records the switch; answers one invitation of each kind the page draws.
final class _MemoryAdmin implements ReferralAdminRepository {
  bool enabled = true;
  int switches = 0;

  @override
  Future<Result<ReferralOverview>> overview({
    required DateTime now,
    required int referrerLimit,
    required int invitationLimit,
  }) async => Result.ok(
    ReferralOverview(
      enabled: enabled,
      stateCounts: const {'paid': 1, 'revoked': 1},
      referrers: const [
        ReferrerTotals(
          referrerId: kUserId,
          referrerName: 'Ali',
          invited: 2,
          paid: 1,
          pending: 0,
          held: 0,
          refused: 1,
          monthPoints: 1,
        ),
      ],
      invitations: [
        ReferralInvitation(
          inviteeId: 'i-1',
          inviteeName: 'Badr',
          inviteeStatus: 'suspended',
          referrerId: kUserId,
          referrerName: 'Ali',
          claimedAt: DateTime.utc(2026, 10, 1, 7),
          state: 'revoked',
          holdReasons: const [],
          revokedAt: DateTime.utc(2026, 10, 11, 9),
          revokeReason: 'inactive_7_days',
        ),
      ],
    ),
  );

  @override
  Future<Result<bool>> setEnabled({required bool enabled}) async {
    switches++;
    this.enabled = enabled;
    return Result.ok(enabled);
  }
}

CompositionRoot _root(_MemoryAdmin repo) => CompositionRoot.forTesting(
  adminGetReferralOverview: AdminGetReferralOverview(
    referrals: repo,
    clock: const _FixedClock(),
  ),
  adminSetReferralsEnabled: AdminSetReferralsEnabled(referrals: repo),
);

void main() {
  group('GET /admin/referral-overview', () {
    test('an admin reads the switch, the totals and the invitations', () async {
      final response = await overview_route.onRequest(
        wireContext(
          root: _root(_MemoryAdmin()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['enabled'], true);
      expect(body['state_counts'], {'paid': 1, 'revoked': 1});
      final invitation =
          (body['invitations']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(invitation['revoke_reason'], 'inactive_7_days');
      expect(invitation['invitee_status'], 'suspended');
    });

    test('a player is refused', () async {
      final response = await overview_route.onRequest(
        wireContext(
          root: _root(_MemoryAdmin()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('PUT /admin/referral-switch', () {
    test('an admin turns the system off', () async {
      final repo = _MemoryAdmin();
      final response = await switch_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'enabled': false},
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['enabled'], false);
      expect(repo.enabled, isFalse);
    });

    test('a value that is not a boolean is 400, nothing stored', () async {
      final repo = _MemoryAdmin();
      final response = await switch_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'enabled': 'off'},
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      expect(repo.switches, 0);
    });

    test('a player is refused, nothing stored', () async {
      final repo = _MemoryAdmin();
      final response = await switch_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: userPrincipal(),
          method: HttpMethod.put,
          body: const {'enabled': false},
        ),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
      expect(repo.switches, 0);
    });

    test('any other method is 405', () async {
      final response = await switch_route.onRequest(
        wireContext(
          root: _root(_MemoryAdmin()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
