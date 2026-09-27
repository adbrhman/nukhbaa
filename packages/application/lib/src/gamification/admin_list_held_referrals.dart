/// Use-case: the invitations held for review (migration 0073). Admin only.
library;

import 'package:application/src/gamification/ports/referral_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lists the held invitations, oldest first. Admin only.
/// Never throws; returns a typed [Result].
final class AdminListHeldReferrals {
  /// Creates the use-case over its store.
  const AdminListHeldReferrals({required ReferralRepository referrals})
    : _referrals = referrals;

  final ReferralRepository _referrals;

  /// The page when none (or a nonsense one) is asked for.
  static const int defaultLimit = 50;

  /// The largest page.
  static const int maxLimit = 100;

  /// Runs the use-case for [principal].
  Future<Result<List<HeldReferral>>> call({
    required AuthenticatedUser principal,
    int? limit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final int page = limit == null || limit < 1
        ? defaultLimit
        : (limit > maxLimit ? maxLimit : limit);
    return _referrals.held(limit: page);
  }
}
