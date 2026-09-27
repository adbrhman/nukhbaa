import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/referrals/[id]/index.dart' as review_route;
// ignore: always_use_package_imports
import '../../routes/admin/referrals/index.dart' as held_route;
// ignore: always_use_package_imports
import '../../routes/me/referral/claim/index.dart' as claim_route;
// ignore: always_use_package_imports
import '../../routes/me/referral/index.dart' as summary_route;
import 'competition_route_harness.dart';

const _invitee = '66666666-7777-4888-8999-000000000000';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 15, 12);
}

/// Records what reached the store; the rules themselves are the database's
/// and are tested against Postgres (supabase/tests/0073_referrals_test.sql).
final class _MemoryReferrals implements ReferralRepository {
  String? claimedCode;
  String? claimedIp;
  String? claimedInstall;
  String? markedInstall;
  ReferralDecision? decided;
  ReferralClaimOutcome claimAnswer = ReferralClaimOutcome.claimed;

  @override
  Future<Result<String>> ensureCode(UserId userId) async =>
      const Result.ok('ABCDEFGH');

  @override
  Future<Result<void>> markInstall({
    required UserId userId,
    required String installId,
    required DateTime now,
  }) async {
    markedInstall = installId;
    return const Result.ok(null);
  }

  @override
  Future<Result<ReferralCounts>> counts({
    required UserId userId,
    required DateTime now,
    required int seasonStartYear,
  }) async => const Result.ok(
    ReferralCounts(
      monthPoints: 3,
      seasonPoints: 7,
      invitedCount: 5,
      pendingCount: 2,
    ),
  );

  @override
  Future<Result<ReferralClaimOutcome>> claim({
    required UserId invitee,
    required String code,
    required String? ip,
    required String? installId,
    required DateTime now,
  }) async {
    claimedCode = code;
    claimedIp = ip;
    claimedInstall = installId;
    return Result.ok(claimAnswer);
  }

  @override
  Future<Result<int>> qualify({required DateTime now}) async =>
      const Result.ok(0);

  @override
  Future<Result<List<HeldReferral>>> held({required int limit}) async =>
      Result.ok([
        HeldReferral(
          inviteeId: _invitee,
          inviteeName: 'Badr',
          referrerId: kUserId,
          referrerName: 'Ali',
          claimedAt: DateTime.utc(2026, 10, 5, 6),
          heldAt: DateTime.utc(2026, 10, 10, 9),
          reasons: const ['shared_network'],
        ),
      ]);

  @override
  Future<Result<ReferralReviewOutcome>> review({
    required UserId invitee,
    required ReferralDecision decision,
    required UserId admin,
    required String reason,
    required DateTime now,
  }) async {
    decided = decision;
    return const Result.ok(ReferralReviewOutcome.approved);
  }
}

final class _Directory implements UserDirectory {
  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async =>
      Result.ok(
        User(
          id: principal.userId,
          email: 'a@example.com',
          role: PlatformRole.user,
          status: UserStatus.active,
          displayName: 'A',
        ),
      );

  @override
  Future<Result<User>> updateDisplayName(UserId userId, String displayName) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();

  @override
  Future<Result<User?>> findUser(UserId id) => throw UnimplementedError();
}

CompositionRoot _root(_MemoryReferrals repo) => CompositionRoot.forTesting(
  getMyReferral: GetMyReferral(referrals: repo, clock: const _FixedClock()),
  claimReferral: ClaimReferral(
    referrals: repo,
    userDirectory: _Directory(),
    clock: const _FixedClock(),
  ),
  adminListHeldReferrals: AdminListHeldReferrals(referrals: repo),
  adminReviewReferral: AdminReviewReferral(
    referrals: repo,
    clock: const _FixedClock(),
  ),
);

void main() {
  group('GET /me/referral', () {
    test('answers the fixed code and the counters', () async {
      final repo = _MemoryReferrals();
      final response = await summary_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: userPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'install': 'abcdef12-3456'},
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['code'], 'ABCDEFGH');
      expect(body['month_points'], 3);
      expect(body['season_points'], 7);
      expect(body['month_cap'], 20);
      expect(repo.markedInstall, 'abcdef12-3456');
    });

    test('any other method is 405', () async {
      final response = await summary_route.onRequest(
        wireContext(
          root: _root(_MemoryReferrals()),
          principal: userPrincipal(),
        ),
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /me/referral/claim', () {
    Future<Response> claim(
      _MemoryReferrals repo, {
      Object? body,
      Map<String, String> headers = const {},
    }) {
      final context = wireContext(
        root: _root(repo),
        principal: userPrincipal(),
        body: body,
      );
      // Take the request mock out first: stubbing through
      // context.request.headers would re-stub context.request itself.
      final Request request = context.request;
      when(() => request.headers).thenReturn(headers);
      return claim_route.onRequest(context);
    }

    test('claims with the proxy-added address, not a forged one', () async {
      final repo = _MemoryReferrals();
      final response = await claim(
        repo,
        body: const {'code': 'abcdefgh', 'install_id': 'inst-12345'},
        headers: const {'x-forwarded-for': '6.6.6.6, 10.0.0.1'},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['status'], 'claimed');
      expect(repo.claimedCode, 'abcdefgh');
      expect(repo.claimedIp, '10.0.0.1');
      expect(repo.claimedInstall, 'inst-12345');
    });

    test('a refused claim is 200 with its status', () async {
      final repo = _MemoryReferrals()
        ..claimAnswer = ReferralClaimOutcome.selfReferral;
      final response = await claim(repo, body: const {'code': 'ABCDEFGH'});
      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['status'], 'self_referral');
      expect(repo.claimedIp, isNull);
    });

    test('a body that is not an object is 400, nothing claimed', () async {
      final repo = _MemoryReferrals();
      final response = await claim(repo, body: const ['ABCDEFGH']);
      expect(response.statusCode, HttpStatus.badRequest);
      expect(repo.claimedCode, isNull);
    });
  });

  group('GET /admin/referrals', () {
    test('an admin reads the held invitations', () async {
      final response = await held_route.onRequest(
        wireContext(
          root: _root(_MemoryReferrals()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
      final items = (await decodeBody(response))['items']! as List<Object?>;
      final first = items.single! as Map<String, Object?>;
      expect(first['invitee_name'], 'Badr');
      expect(first['reasons'], ['shared_network']);
    });

    test('a player is refused', () async {
      final response = await held_route.onRequest(
        wireContext(
          root: _root(_MemoryReferrals()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('POST /admin/referrals/{inviteeId}', () {
    test('an admin approves with a reason', () async {
      final repo = _MemoryReferrals();
      final response = await review_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: adminPrincipal(),
          body: const {'decision': 'approve', 'reason': 'brothers, one house'},
        ),
        _invitee,
      );
      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['status'], 'approved');
      expect(repo.decided, ReferralDecision.approve);
    });

    test('no reason is 400, nothing decided', () async {
      final repo = _MemoryReferrals();
      final response = await review_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: adminPrincipal(),
          body: const {'decision': 'revoke'},
        ),
        _invitee,
      );
      expect(response.statusCode, HttpStatus.badRequest);
      expect(repo.decided, isNull);
    });

    test('a player is refused', () async {
      final repo = _MemoryReferrals();
      final response = await review_route.onRequest(
        wireContext(
          root: _root(repo),
          principal: userPrincipal(),
          body: const {'decision': 'approve', 'reason': 'fine by me'},
        ),
        _invitee,
      );
      expect(response.statusCode, HttpStatus.unauthorized);
      expect(repo.decided, isNull);
    });
  });
}
