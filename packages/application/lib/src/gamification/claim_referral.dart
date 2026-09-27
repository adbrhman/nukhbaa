/// Use-case: a new account names the code of the friend who invited it
/// (migration 0073).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/get_my_referral.dart';
import 'package:application/src/gamification/ports/referral_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Records the caller's inviter.
///
/// The rules are the database's (`gamification.claim_referral`): one
/// inviter per account and never changed, no self-invitation, only within
/// 24 hours of the account's creation, only while the `referrals` flag is
/// on. Signing up pays nothing: payment waits for the first graded
/// prediction (`QualifyReferrals`).
///
/// The platform row is ensured first, so a claim sent right after sign-up
/// never races the first `GET /me`. The caller's network address and install
/// id travel only to be hashed by the database; neither is kept raw.
/// Never throws; returns a typed [Result].
final class ClaimReferral {
  /// Creates the use-case over its collaborators.
  const ClaimReferral({
    required ReferralRepository referrals,
    required UserDirectory userDirectory,
    required Clock clock,
  }) : _referrals = referrals,
       _directory = userDirectory,
       _clock = clock;

  final ReferralRepository _referrals;
  final UserDirectory _directory;
  final Clock _clock;

  /// The longest code accepted before it is refused as malformed without a
  /// database round trip.
  static const int maxCodeLength = 32;

  /// The shape of a network address worth hashing.
  static final RegExp ipPattern = RegExp(r'^[0-9A-Fa-f:.]{2,64}$');

  /// Runs the use-case for [principal].
  Future<Result<ReferralClaimOutcome>> call({
    required AuthenticatedUser principal,
    required String code,
    String? ip,
    String? installId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final String trimmed = code.trim();
    if (trimmed.isEmpty || trimmed.length > maxCodeLength) {
      return const Result.ok(ReferralClaimOutcome.invalidCode);
    }
    final ensured = await _directory.ensureUser(principal);
    if (ensured is Err<User>) {
      return Result.err(ensured.error);
    }
    return _referrals.claim(
      invitee: principal.userId,
      code: trimmed,
      ip: ip != null && ipPattern.hasMatch(ip) ? ip : null,
      installId:
          installId != null &&
              GetMyReferral.installIdPattern.hasMatch(installId)
          ? installId
          : null,
      now: _clock.nowUtc(),
    );
  }
}
