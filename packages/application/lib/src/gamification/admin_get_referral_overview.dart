/// Use-case: the admin's page of the invitation system (migration 0075).
/// Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/ports/referral_admin_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the switch, the totals per state, the inviters and the newest
/// invitations. Admin only. Never throws; returns a typed [Result].
final class AdminGetReferralOverview {
  /// Creates the use-case over its collaborators.
  const AdminGetReferralOverview({
    required ReferralAdminRepository referrals,
    required Clock clock,
  }) : _referrals = referrals,
       _clock = clock;

  final ReferralAdminRepository _referrals;
  final Clock _clock;

  /// Inviters listed.
  static const int referrerLimit = 100;

  /// Invitations listed.
  static const int invitationLimit = 300;

  /// Runs the use-case for [principal].
  Future<Result<ReferralOverview>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _referrals.overview(
      now: _clock.nowUtc(),
      referrerLimit: referrerLimit,
      invitationLimit: invitationLimit,
    );
  }
}
