import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-4333-8444-555555555555';
const _invitee = '66666666-7777-4888-8999-000000000000';

final class _FixedClock implements Clock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

final class _FakeReferrals implements ReferralRepository {
  final List<String> calls = [];
  String? claimedCode;
  String? claimedIp;
  String? claimedInstall;
  int? seasonYear;
  String? markedInstall;
  ReferralDecision? decided;
  String? decidedReason;
  int? heldLimit;
  ReferralClaimOutcome claimAnswer = ReferralClaimOutcome.claimed;
  ReferralReviewOutcome reviewAnswer = ReferralReviewOutcome.approved;
  bool failCode = false;

  @override
  Future<Result<String>> ensureCode(UserId userId) async {
    calls.add('ensureCode');
    if (failCode) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return const Result.ok('ABCDEFGH');
  }

  @override
  Future<Result<void>> markInstall({
    required UserId userId,
    required String installId,
    required DateTime now,
  }) async {
    calls.add('markInstall');
    markedInstall = installId;
    return const Result.ok(null);
  }

  @override
  Future<Result<ReferralCounts>> counts({
    required UserId userId,
    required DateTime now,
    required int seasonStartYear,
  }) async {
    calls.add('counts');
    seasonYear = seasonStartYear;
    return const Result.ok(
      ReferralCounts(
        monthPoints: 3,
        seasonPoints: 7,
        invitedCount: 5,
        pendingCount: 2,
      ),
    );
  }

  @override
  Future<Result<ReferralClaimOutcome>> claim({
    required UserId invitee,
    required String code,
    required String? ip,
    required String? installId,
    required DateTime now,
  }) async {
    calls.add('claim');
    claimedCode = code;
    claimedIp = ip;
    claimedInstall = installId;
    return Result.ok(claimAnswer);
  }

  @override
  Future<Result<int>> qualify({required DateTime now}) async {
    calls.add('qualify');
    return const Result.ok(4);
  }

  @override
  Future<Result<List<HeldReferral>>> held({required int limit}) async {
    calls.add('held');
    heldLimit = limit;
    return const Result.ok([]);
  }

  @override
  Future<Result<ReferralReviewOutcome>> review({
    required UserId invitee,
    required ReferralDecision decision,
    required UserId admin,
    required String reason,
    required DateTime now,
  }) async {
    calls.add('review');
    decided = decision;
    decidedReason = reason;
    return Result.ok(reviewAnswer);
  }
}

final class _Directory implements UserDirectory {
  int ensured = 0;
  bool fail = false;

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async {
    ensured++;
    if (fail) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return Result.ok(
      User(
        id: principal.userId,
        email: 'a@example.com',
        role: PlatformRole.user,
        status: UserStatus.active,
        displayName: 'A',
      ),
    );
  }

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

const _player = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);
const _admin = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.admin,
);
// 2026-10-15: inside the 2026/27 sporting season.
final _clock = _FixedClock(DateTime.utc(2026, 10, 15, 12));

void main() {
  group('GetMyReferral', () {
    test(
      'returns the fixed code and the counters of the open season',
      () async {
        final repo = _FakeReferrals();
        final result = await GetMyReferral(referrals: repo, clock: _clock)(
          principal: _player,
          installId: 'abcdef12-3456',
        );

        final summary = (result as Ok<ReferralSummary>).value;
        expect(summary.code, 'ABCDEFGH');
        expect(summary.counts.monthPoints, 3);
        expect(summary.counts.seasonPoints, 7);
        expect(summary.monthCap, 20);
        expect(repo.seasonYear, 2026);
        expect(repo.markedInstall, 'abcdef12-3456');
      },
    );

    test('a malformed install id is not remembered', () async {
      final repo = _FakeReferrals();
      await GetMyReferral(referrals: repo, clock: _clock)(
        principal: _player,
        installId: "x'; drop",
      );
      expect(repo.calls, isNot(contains('markInstall')));
    });

    test('a failed code read is the error, counters are not read', () async {
      final repo = _FakeReferrals()..failCode = true;
      final result = await GetMyReferral(referrals: repo, clock: _clock)(
        principal: _player,
      );
      expect(result, isA<Err<ReferralSummary>>());
      expect(repo.calls, ['ensureCode']);
    });
  });

  group('ClaimReferral', () {
    test(
      'ensures the platform row, then claims with the trimmed code',
      () async {
        final repo = _FakeReferrals();
        final directory = _Directory();
        final result =
            await ClaimReferral(
              referrals: repo,
              userDirectory: directory,
              clock: _clock,
            )(
              principal: _player,
              code: '  abcdefgh ',
              ip: '10.0.0.1',
              installId: 'inst-12345',
            );

        expect(
          (result as Ok<ReferralClaimOutcome>).value,
          ReferralClaimOutcome.claimed,
        );
        expect(directory.ensured, 1);
        expect(repo.claimedCode, 'abcdefgh');
        expect(repo.claimedIp, '10.0.0.1');
        expect(repo.claimedInstall, 'inst-12345');
      },
    );

    test('every database outcome is passed through as it is', () async {
      for (final ReferralClaimOutcome outcome in ReferralClaimOutcome.values) {
        final repo = _FakeReferrals()..claimAnswer = outcome;
        final result = await ClaimReferral(
          referrals: repo,
          userDirectory: _Directory(),
          clock: _clock,
        )(principal: _player, code: 'ABCDEFGH');
        expect((result as Ok<ReferralClaimOutcome>).value, outcome);
      }
    });

    test(
      'an empty or oversized code is invalid without a database call',
      () async {
        final repo = _FakeReferrals();
        final useCase = ClaimReferral(
          referrals: repo,
          userDirectory: _Directory(),
          clock: _clock,
        );
        final empty = await useCase(principal: _player, code: '   ');
        final huge = await useCase(principal: _player, code: 'A' * 40);
        expect(
          (empty as Ok<ReferralClaimOutcome>).value,
          ReferralClaimOutcome.invalidCode,
        );
        expect(
          (huge as Ok<ReferralClaimOutcome>).value,
          ReferralClaimOutcome.invalidCode,
        );
        expect(repo.calls, isEmpty);
      },
    );

    test(
      'a forged address or install id is dropped, the claim still runs',
      () async {
        final repo = _FakeReferrals();
        await ClaimReferral(
          referrals: repo,
          userDirectory: _Directory(),
          clock: _clock,
        )(principal: _player, code: 'ABCDEFGH', ip: '<script>', installId: 'x');
        expect(repo.claimedIp, isNull);
        expect(repo.claimedInstall, isNull);
        expect(repo.calls, ['claim']);
      },
    );

    test('a failed platform row read stops the claim', () async {
      final repo = _FakeReferrals();
      final result = await ClaimReferral(
        referrals: repo,
        userDirectory: _Directory()..fail = true,
        clock: _clock,
      )(principal: _player, code: 'ABCDEFGH');
      expect(result, isA<Err<ReferralClaimOutcome>>());
      expect(repo.calls, isEmpty);
    });
  });

  group('QualifyReferrals', () {
    test('runs one sweep and reports the events written', () async {
      final repo = _FakeReferrals();
      final result = await QualifyReferrals(referrals: repo)(
        now: DateTime.utc(2026, 10, 15),
      );
      expect((result as Ok<int>).value, 4);
      expect(repo.calls, ['qualify']);
    });
  });

  group('AdminListHeldReferrals', () {
    test('a player is refused', () async {
      final repo = _FakeReferrals();
      final result = await AdminListHeldReferrals(referrals: repo)(
        principal: _player,
      );
      expect(
        (result as Err<List<HeldReferral>>).error.code,
        'auth.insufficient_role',
      );
      expect(repo.calls, isEmpty);
    });

    test('the page is clamped', () async {
      final repo = _FakeReferrals();
      await AdminListHeldReferrals(referrals: repo)(
        principal: _admin,
        limit: 5000,
      );
      expect(repo.heldLimit, 100);
      await AdminListHeldReferrals(referrals: repo)(
        principal: _admin,
        limit: 0,
      );
      expect(repo.heldLimit, 50);
    });
  });

  group('AdminReviewReferral', () {
    test('an admin decision reaches the database with its reason', () async {
      final repo = _FakeReferrals();
      final result = await AdminReviewReferral(referrals: repo, clock: _clock)(
        principal: _admin,
        inviteeId: _invitee,
        decision: 'approve',
        reason: ' brothers, one house ',
      );
      expect(
        (result as Ok<ReferralReviewOutcome>).value,
        ReferralReviewOutcome.approved,
      );
      expect(repo.decided, ReferralDecision.approve);
      expect(repo.decidedReason, 'brothers, one house');
    });

    test(
      'a player, a bad id, a bad decision and no reason are refused',
      () async {
        final repo = _FakeReferrals();
        final useCase = AdminReviewReferral(referrals: repo, clock: _clock);
        final player = await useCase(
          principal: _player,
          inviteeId: _invitee,
          decision: 'approve',
          reason: 'fine',
        );
        final badId = await useCase(
          principal: _admin,
          inviteeId: 'nope',
          decision: 'approve',
          reason: 'fine',
        );
        final badDecision = await useCase(
          principal: _admin,
          inviteeId: _invitee,
          decision: 'pay',
          reason: 'fine',
        );
        final noReason = await useCase(
          principal: _admin,
          inviteeId: _invitee,
          decision: 'revoke',
          reason: ' ',
        );
        expect(
          (player as Err<ReferralReviewOutcome>).error.code,
          'auth.insufficient_role',
        );
        expect(
          (badId as Err<ReferralReviewOutcome>).error.code,
          'referral.invitee_invalid',
        );
        expect(
          (badDecision as Err<ReferralReviewOutcome>).error.code,
          'referral.decision_invalid',
        );
        expect(
          (noReason as Err<ReferralReviewOutcome>).error.code,
          'referral.reason_required',
        );
        expect(repo.calls, isEmpty);
      },
    );
  });
}
