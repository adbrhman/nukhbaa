/// Body of `GET /me/referral` (migration 0073): the caller's invitation
/// code and counters. Invitation points never add to prediction points;
/// they only break a tie.
final class ReferralSummaryDto {
  /// Creates the summary.
  const ReferralSummaryDto({
    required this.code,
    required this.monthPoints,
    required this.seasonPoints,
    required this.invitedCount,
    required this.pendingCount,
    required this.monthCap,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferralSummaryDto.fromJson(Map<String, Object?> json) =>
      ReferralSummaryDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        code: (json['code'] as String?) ?? '',
        monthPoints: (json['month_points'] as int?) ?? 0,
        seasonPoints: (json['season_points'] as int?) ?? 0,
        invitedCount: (json['invited_count'] as int?) ?? 0,
        pendingCount: (json['pending_count'] as int?) ?? 0,
        monthCap: (json['month_cap'] as int?) ?? 20,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The caller's fixed invitation code.
  final String code;

  /// Invitation points of the monthly contest open now.
  final int monthPoints;

  /// Invitation points of the sporting season open now.
  final int seasonPoints;

  /// Accounts that named the caller as their inviter.
  final int invitedCount;

  /// Of those, the ones not paid and not refused yet.
  final int pendingCount;

  /// The most invitation points one month counts.
  final int monthCap;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'code': code,
    'month_points': monthPoints,
    'season_points': seasonPoints,
    'invited_count': invitedCount,
    'pending_count': pendingCount,
    'month_cap': monthCap,
  };
}

/// Body of `POST /me/referral/claim`: the inviter's code, and the app's
/// install id when it has one.
final class ReferralClaimRequestDto {
  /// Creates the request.
  const ReferralClaimRequestDto({
    required this.code,
    this.installId,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferralClaimRequestDto.fromJson(Map<String, Object?> json) =>
      ReferralClaimRequestDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        code: json['code'] is String ? json['code'] as String : '',
        installId: json['install_id'] is String
            ? json['install_id'] as String
            : null,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The inviter's code, as typed.
  final String code;

  /// The app's install id; omitted by the web.
  final String? installId;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'code': code,
    if (installId != null) 'install_id': installId,
  };
}

/// Body of the answer to `POST /me/referral/claim` and
/// `POST /admin/referrals/{inviteeId}`: where the request ended
/// (`claimed`, `already_claimed`, `disabled`, `invalid_code`, `unknown_code`,
/// `self_referral`, `window_closed`; or `approved`, `rejected`, `revoked`,
/// `not_held`, `not_paid`, `already_decided`, `unknown_invitation`).
final class ReferralStatusDto {
  /// Creates the answer.
  const ReferralStatusDto({
    required this.status,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferralStatusDto.fromJson(Map<String, Object?> json) =>
      ReferralStatusDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        status: (json['status'] as String?) ?? '',
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Where the request ended.
  final String status;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'status': status,
  };
}

/// One invitation held for review.
final class HeldReferralDto {
  /// Creates the row.
  const HeldReferralDto({
    required this.inviteeId,
    required this.inviteeName,
    required this.referrerId,
    required this.referrerName,
    required this.claimedAt,
    required this.heldAt,
    required this.reasons,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory HeldReferralDto.fromJson(Map<String, Object?> json) =>
      HeldReferralDto(
        inviteeId: (json['invitee_id'] as String?) ?? '',
        inviteeName: (json['invitee_name'] as String?) ?? '',
        referrerId: (json['referrer_id'] as String?) ?? '',
        referrerName: (json['referrer_name'] as String?) ?? '',
        claimedAt: (json['claimed_at'] as String?) ?? '',
        heldAt: (json['held_at'] as String?) ?? '',
        reasons: [
          for (final Object? r in (json['reasons'] as List<Object?>?) ?? [])
            if (r is String) r,
        ],
      );

  /// The invited account.
  final String inviteeId;

  /// Its display name.
  final String inviteeName;

  /// The inviter.
  final String referrerId;

  /// The inviter's display name.
  final String referrerName;

  /// When the invitation was claimed (ISO-8601 UTC).
  final String claimedAt;

  /// When it was held (ISO-8601 UTC).
  final String heldAt;

  /// Why it was held.
  final List<String> reasons;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'invitee_id': inviteeId,
    'invitee_name': inviteeName,
    'referrer_id': referrerId,
    'referrer_name': referrerName,
    'claimed_at': claimedAt,
    'held_at': heldAt,
    'reasons': reasons,
  };
}

/// Body of `GET /admin/referrals`: the invitations held for review.
final class AdminHeldReferralsDto {
  /// Creates the list.
  const AdminHeldReferralsDto({
    required this.items,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminHeldReferralsDto.fromJson(Map<String, Object?> json) =>
      AdminHeldReferralsDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        items: [
          for (final Object? item in (json['items'] as List<Object?>?) ?? [])
            if (item is Map<String, Object?>) HeldReferralDto.fromJson(item),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The held invitations, oldest first.
  final List<HeldReferralDto> items;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'items': [for (final HeldReferralDto item in items) item.toJson()],
  };
}

/// Body of `POST /admin/referrals/{inviteeId}`: the decision and its
/// mandatory reason.
final class ReferralReviewRequestDto {
  /// Creates the request.
  const ReferralReviewRequestDto({
    required this.decision,
    required this.reason,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferralReviewRequestDto.fromJson(Map<String, Object?> json) =>
      ReferralReviewRequestDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        decision: json['decision'] is String
            ? json['decision'] as String
            : null,
        reason: json['reason'] is String ? json['reason'] as String : null,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// `approve`, `reject` or `revoke`.
  final String? decision;

  /// Why (3 to 500 characters).
  final String? reason;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'decision': decision,
    'reason': reason,
  };
}
