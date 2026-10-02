import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Where a claim of an invitation code ended (migration 0073,
/// `gamification.claim_referral`).
enum ReferralClaimOutcome {
  /// The invitation is recorded: this account names its inviter for good.
  claimed('claimed'),

  /// This account already names an inviter; nothing changed.
  alreadyClaimed('already_claimed'),

  /// Invitations are switched off (feature flag `referrals`).
  disabled('disabled'),

  /// The code does not have the shape of an invitation code.
  invalidCode('invalid_code'),

  /// No user holds this code.
  unknownCode('unknown_code'),

  /// The code is the caller's own.
  selfReferral('self_referral'),

  /// The account is older than 24 hours, or the inviter is newer than it.
  windowClosed('window_closed'),

  /// The claim came from the browser, where a phone cannot be told apart
  /// (migration 0086): only the app counts an invitation.
  appRequired('app_required'),

  /// The claim came from a phone the inviter uses (migration 0086).
  sameDevice('same_device');

  const ReferralClaimOutcome(this.wireName);

  /// The value the database returns and the API sends.
  final String wireName;

  /// The outcome named [raw], or null for an unknown value.
  static ReferralClaimOutcome? fromWire(String? raw) {
    for (final ReferralClaimOutcome outcome in values) {
      if (outcome.wireName == raw) {
        return outcome;
      }
    }
    return null;
  }
}

/// What an admin decides about an invitation.
enum ReferralDecision {
  /// Pay a held invitation.
  approve('approve'),

  /// Refuse a held invitation for good.
  reject('reject'),

  /// Take back a paid invitation (a compensating event, never a delete).
  revoke('revoke');

  const ReferralDecision(this.wireName);

  /// The value the API receives and the database takes.
  final String wireName;

  /// The decision named [raw], or null for an unknown value.
  static ReferralDecision? fromWire(String? raw) {
    for (final ReferralDecision decision in values) {
      if (decision.wireName == raw) {
        return decision;
      }
    }
    return null;
  }
}

/// Where an admin decision ended (`gamification.review_referral`).
enum ReferralReviewOutcome {
  /// The held invitation is paid.
  approved('approved'),

  /// The held invitation is refused.
  rejected('rejected'),

  /// The paid invitation is taken back.
  revoked('revoked'),

  /// Only a held invitation can be approved or rejected.
  notHeld('not_held'),

  /// Only a paid invitation can be revoked.
  notPaid('not_paid'),

  /// The invitation was already decided.
  alreadyDecided('already_decided'),

  /// No invitation names this invitee.
  unknownInvitation('unknown_invitation'),

  /// The reason is missing or too short.
  reasonRequired('reason_required'),

  /// The decision is not one of approve, reject, revoke.
  invalidDecision('invalid_decision');

  const ReferralReviewOutcome(this.wireName);

  /// The value the database returns and the API sends.
  final String wireName;

  /// The outcome named [raw], or null for an unknown value.
  static ReferralReviewOutcome? fromWire(String? raw) {
    for (final ReferralReviewOutcome outcome in values) {
      if (outcome.wireName == raw) {
        return outcome;
      }
    }
    return null;
  }
}

/// A user's invitation counters.
final class ReferralCounts {
  /// Creates the counters.
  const ReferralCounts({
    required this.monthPoints,
    required this.seasonPoints,
    required this.invitedCount,
    required this.pendingCount,
  });

  /// Invitation points of the monthly contest open now (capped at 20).
  final int monthPoints;

  /// Invitation points of the sporting season open now.
  final int seasonPoints;

  /// Accounts that named this user as their inviter.
  final int invitedCount;

  /// Of those, the ones not paid and not refused yet (still playing their
  /// first graded match, or held for review).
  final int pendingCount;
}

/// A held invitation waiting for an admin.
final class HeldReferral {
  /// Creates the row.
  const HeldReferral({
    required this.inviteeId,
    required this.inviteeName,
    required this.referrerId,
    required this.referrerName,
    required this.claimedAt,
    required this.heldAt,
    required this.reasons,
  });

  /// The invited account.
  final String inviteeId;

  /// Its display name.
  final String inviteeName;

  /// The inviter.
  final String referrerId;

  /// The inviter's display name.
  final String referrerName;

  /// When the invitation was claimed.
  final DateTime claimedAt;

  /// When it was held.
  final DateTime heldAt;

  /// Why it was held: `shared_network`, `shared_install`, `inviter_install`,
  /// `burst`.
  final List<String> reasons;
}

/// The invitations store (migration 0073). Every rule lives in the
/// database functions this port calls; the port only carries values.
abstract interface class ReferralRepository {
  /// The user's fixed invitation code, created on first use.
  Future<Result<String>> ensureCode(UserId userId);

  /// Remembers an install the user was seen with (stored hashed).
  Future<Result<void>> markInstall({
    required UserId userId,
    required String installId,
    required DateTime now,
  });

  /// The user's counters for the month and the sporting season open at
  /// [now]; [seasonStartYear] names that sporting season.
  Future<Result<ReferralCounts>> counts({
    required UserId userId,
    required DateTime now,
    required int seasonStartYear,
  });

  /// Records that [invitee] was invited by the holder of [code].
  Future<Result<ReferralClaimOutcome>> claim({
    required UserId invitee,
    required String code,
    required String? ip,
    required String? installId,
    required DateTime now,
  });

  /// Pays or holds every invitation that became eligible; returns the
  /// number of events written. Safe to re-run.
  Future<Result<int>> qualify({required DateTime now});

  /// The held invitations, oldest first.
  Future<Result<List<HeldReferral>>> held({required int limit});

  /// Applies an admin decision.
  Future<Result<ReferralReviewOutcome>> review({
    required UserId invitee,
    required ReferralDecision decision,
    required UserId admin,
    required String reason,
    required DateTime now,
  });
}
