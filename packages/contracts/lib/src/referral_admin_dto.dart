/// One invitation on the admin page (migration 0075).
final class ReferralInvitationDto {
  /// Creates the row.
  const ReferralInvitationDto({
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

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferralInvitationDto.fromJson(Map<String, Object?> json) =>
      ReferralInvitationDto(
        inviteeId: (json['invitee_id'] as String?) ?? '',
        inviteeName: (json['invitee_name'] as String?) ?? '',
        inviteeStatus: (json['invitee_status'] as String?) ?? '',
        referrerId: (json['referrer_id'] as String?) ?? '',
        referrerName: (json['referrer_name'] as String?) ?? '',
        claimedAt: (json['claimed_at'] as String?) ?? '',
        state: (json['state'] as String?) ?? '',
        holdReasons: [
          for (final Object? r
              in (json['hold_reasons'] as List<Object?>?) ?? [])
            if (r is String) r,
        ],
        paidAt: json['paid_at'] as String?,
        heldAt: json['held_at'] as String?,
        revokedAt: json['revoked_at'] as String?,
        revokeReason: json['revoke_reason'] as String?,
        lastPredictionAt: json['last_prediction_at'] as String?,
      );

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

  /// When the invitation was claimed (ISO-8601 UTC).
  final String claimedAt;

  /// `pending`, `held`, `paid`, `revoked` or `rejected`.
  final String state;

  /// Why it was held.
  final List<String> holdReasons;

  /// When it was paid (ISO-8601 UTC).
  final String? paidAt;

  /// When it was held (ISO-8601 UTC).
  final String? heldAt;

  /// When it was revoked (ISO-8601 UTC).
  final String? revokedAt;

  /// Why it was revoked (`inactive_7_days`, or an admin's reason).
  final String? revokeReason;

  /// The invitee's last prediction (ISO-8601 UTC).
  final String? lastPredictionAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'invitee_id': inviteeId,
    'invitee_name': inviteeName,
    'invitee_status': inviteeStatus,
    'referrer_id': referrerId,
    'referrer_name': referrerName,
    'claimed_at': claimedAt,
    'state': state,
    'hold_reasons': holdReasons,
    'paid_at': paidAt,
    'held_at': heldAt,
    'revoked_at': revokedAt,
    'revoke_reason': revokeReason,
    'last_prediction_at': lastPredictionAt,
  };
}

/// One inviter's totals on the admin page.
final class ReferrerTotalsDto {
  /// Creates the totals.
  const ReferrerTotalsDto({
    required this.referrerId,
    required this.referrerName,
    required this.invited,
    required this.paid,
    required this.pending,
    required this.held,
    required this.refused,
    required this.monthPoints,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferrerTotalsDto.fromJson(Map<String, Object?> json) =>
      ReferrerTotalsDto(
        referrerId: (json['referrer_id'] as String?) ?? '',
        referrerName: (json['referrer_name'] as String?) ?? '',
        invited: (json['invited'] as int?) ?? 0,
        paid: (json['paid'] as int?) ?? 0,
        pending: (json['pending'] as int?) ?? 0,
        held: (json['held'] as int?) ?? 0,
        refused: (json['refused'] as int?) ?? 0,
        monthPoints: (json['month_points'] as int?) ?? 0,
      );

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

  /// Invitation points of the month open now.
  final int monthPoints;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'referrer_id': referrerId,
    'referrer_name': referrerName,
    'invited': invited,
    'paid': paid,
    'pending': pending,
    'held': held,
    'refused': refused,
    'month_points': monthPoints,
  };
}

/// Body of `GET /admin/referral-overview`: the switch, the totals per state,
/// the inviters and the newest invitations.
final class AdminReferralOverviewDto {
  /// Creates the overview.
  const AdminReferralOverviewDto({
    required this.enabled,
    required this.stateCounts,
    required this.referrers,
    required this.invitations,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminReferralOverviewDto.fromJson(Map<String, Object?> json) {
    final Object? rawCounts = json['state_counts'];
    return AdminReferralOverviewDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      enabled: (json['enabled'] as bool?) ?? false,
      stateCounts: <String, int>{
        if (rawCounts is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in rawCounts.entries)
            if (e.value is int) e.key: e.value! as int,
      },
      referrers: [
        for (final Object? r in (json['referrers'] as List<Object?>?) ?? [])
          if (r is Map<String, Object?>) ReferrerTotalsDto.fromJson(r),
      ],
      invitations: [
        for (final Object? r in (json['invitations'] as List<Object?>?) ?? [])
          if (r is Map<String, Object?>) ReferralInvitationDto.fromJson(r),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether the invitation system is on.
  final bool enabled;

  /// Invitations per state, over every invitation.
  final Map<String, int> stateCounts;

  /// The inviters, most invitations first.
  final List<ReferrerTotalsDto> referrers;

  /// The invitations, newest first.
  final List<ReferralInvitationDto> invitations;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'enabled': enabled,
    'state_counts': stateCounts,
    'referrers': [for (final ReferrerTotalsDto r in referrers) r.toJson()],
    'invitations': [
      for (final ReferralInvitationDto i in invitations) i.toJson(),
    ],
  };
}

/// Body of `PUT /admin/referral-switch` and of its answer: the switch.
final class ReferralSwitchDto {
  /// Creates the body.
  const ReferralSwitchDto({
    required this.enabled,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map; a missing or non-boolean value reads as
  /// null so the use-case refuses it rather than guessing.
  static bool? enabledOf(Map<String, Object?> json) {
    final Object? raw = json['enabled'];
    return raw is bool ? raw : null;
  }

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ReferralSwitchDto.fromJson(Map<String, Object?> json) =>
      ReferralSwitchDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        enabled: enabledOf(json) ?? false,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether the invitation system is on.
  final bool enabled;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'enabled': enabled,
  };
}
