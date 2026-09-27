/// Use-case: an admin decides a held invitation or revokes a paid one
/// (migration 0073). Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/ports/referral_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Approves or rejects a held invitation, or revokes a paid one. The reason
/// is mandatory and kept in the event. Nothing is ever deleted: every
/// decision is a new event in `gamification.events`.
/// Never throws; returns a typed [Result].
final class AdminReviewReferral {
  /// Creates the use-case over its collaborators.
  const AdminReviewReferral({
    required ReferralRepository referrals,
    required Clock clock,
  }) : _referrals = referrals,
       _clock = clock;

  final ReferralRepository _referrals;
  final Clock _clock;

  /// The shortest reason accepted.
  static const int minReasonLength = 3;

  /// The longest reason accepted.
  static const int maxReasonLength = 500;

  /// Runs the use-case for [principal].
  Future<Result<ReferralReviewOutcome>> call({
    required AuthenticatedUser principal,
    required String inviteeId,
    required String? decision,
    required String? reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final invitee = UserId.tryParse(inviteeId);
    if (invitee is Err<UserId>) {
      return const Result.err(
        AppError.validation('referral.invitee_invalid', 'Invalid invitee id'),
      );
    }
    final ReferralDecision? parsed = ReferralDecision.fromWire(decision);
    if (parsed == null) {
      return const Result.err(
        AppError.validation(
          'referral.decision_invalid',
          'Decision must be approve, reject or revoke',
        ),
      );
    }
    final String trimmed = (reason ?? '').trim();
    if (trimmed.length < minReasonLength || trimmed.length > maxReasonLength) {
      return const Result.err(
        AppError.validation(
          'referral.reason_required',
          'A reason of 3 to 500 characters is required',
        ),
      );
    }
    return _referrals.review(
      invitee: (invitee as Ok<UserId>).value,
      decision: parsed,
      admin: principal.userId,
      reason: trimmed,
      now: _clock.nowUtc(),
    );
  }
}
