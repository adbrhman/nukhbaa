import 'package:shared/shared.dart';

/// One invitation as the admin sees it (`gamification.referral_invitations`,
/// migration 0075).
final class ReferralInvitation {
  /// Creates the row.
  const ReferralInvitation({
    required this.inviteeId,
    required this.inviteeName,
    required this.inviteeStatus,
    required this.referrerId,
    required this.referrerName,
    required this.claimedAt,
    required this.state,
    required this.holdReasons,
    this.paidAt,
    this.heldAt,
    this.revokedAt,
    this.revokeReason,
    this.lastPredictionAt,
  });

  /// The invited account.
  final String inviteeId;

  /// Its display name.
  final String inviteeName;

  /// `active` or `suspended`.
  final String inviteeStatus;

  /// The inviter.
  final String referrerId;

  /// The inviter's display name.
  final String referrerName;

  /// When the invitation was claimed.
  final DateTime claimedAt;

  /// `pending`, `held`, `paid`, `revoked` or `rejected`.
  final String state;

  /// Why it was held, if it was.
  final List<String> holdReasons;

  /// When it was paid.
  final DateTime? paidAt;

  /// When it was held.
  final DateTime? heldAt;

  /// When it was revoked.
  final DateTime? revokedAt;

  /// Why it was revoked (`inactive_7_days`, or an admin's reason).
  final String? revokeReason;

  /// The invitee's last prediction.
  final DateTime? lastPredictionAt;
}

/// One inviter's totals.
final class ReferrerTotals {
  /// Creates the totals.
  const ReferrerTotals({
    required this.referrerId,
    required this.referrerName,
    required this.invited,
    required this.paid,
    required this.pending,
    required this.held,
    required this.refused,
    required this.monthPoints,
  });

  /// The inviter.
  final String referrerId;

  /// The inviter's display name.
  final String referrerName;

  /// Every account that named this inviter.
  final int invited;

  /// Paid and not taken back.
  final int paid;

  /// Waiting for a first graded prediction.
  final int pending;

  /// Held for review.
  final int held;

  /// Revoked or rejected.
  final int refused;

  /// Invitation points of the month open now (capped at 20).
  final int monthPoints;
}

/// Everything the admin page draws.
final class ReferralOverview {
  /// Creates the overview.
  const ReferralOverview({
    required this.enabled,
    required this.stateCounts,
    required this.referrers,
    required this.invitations,
  });

  /// Whether the `referrals` switch is on.
  final bool enabled;

  /// Invitations per state, over every invitation.
  final Map<String, int> stateCounts;

  /// The inviters, most invitations first.
  final List<ReferrerTotals> referrers;

  /// The invitations, newest first.
  final List<ReferralInvitation> invitations;
}

/// The admin side of the invitations store (migration 0075).
abstract interface class ReferralAdminRepository {
  /// The overview at [now]: at most [referrerLimit] inviters and
  /// [invitationLimit] invitations.
  Future<Result<ReferralOverview>> overview({
    required DateTime now,
    required int referrerLimit,
    required int invitationLimit,
  });

  /// Turns the `referrals` switch on or off; answers what was stored.
  Future<Result<bool>> setEnabled({required bool enabled});
}
