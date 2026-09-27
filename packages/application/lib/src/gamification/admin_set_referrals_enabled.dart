/// Use-case: the admin's switch of the invitation system (migration 0075).
/// Admin only.
library;

import 'package:application/src/gamification/ports/referral_admin_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Turns the invitation system on or off. Off means: no claim is accepted,
/// nothing is paid and nothing is taken back until it is on again; points
/// already paid stay as they are.
/// Never throws; returns a typed [Result].
final class AdminSetReferralsEnabled {
  /// Creates the use-case over its store.
  const AdminSetReferralsEnabled({required ReferralAdminRepository referrals})
    : _referrals = referrals;

  final ReferralAdminRepository _referrals;

  /// Runs the use-case for [principal].
  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required bool? enabled,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (enabled == null) {
      return const Result.err(
        AppError.validation(
          'referral.enabled_required',
          'Field "enabled" must be true or false',
        ),
      );
    }
    return _referrals.setEnabled(enabled: enabled);
  }
}
