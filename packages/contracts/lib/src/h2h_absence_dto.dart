/// Wire shapes of the admin's desk for relegation for absence in the
/// head-to-head league (NK183, migration 0189): `GET /admin/h2h/absence`,
/// `POST /admin/h2h/relegations` and `POST /admin/h2h/excusals`.
library;

List<Map<String, Object?>> _maps(Object? raw) => [
  for (final e in (raw as List<Object?>?) ?? const <Object?>[])
    if (e is Map<Object?, Object?>) e.cast<String, Object?>(),
];

/// A player as the desk names him.
final class H2hAbsencePlayerDto {
  /// Creates a player.
  const H2hAbsencePlayerDto({required this.userId, required this.displayName});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAbsencePlayerDto.fromJson(Map<String, Object?> json) =>
      H2hAbsencePlayerDto(
        userId: (json['user_id'] as String?) ?? '',
        displayName: json['display_name'] as String?,
      );

  /// The player (UUID string).
  final String userId;

  /// His name, or null when he has none.
  final String? displayName;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user_id': userId,
    'display_name': displayName,
  };
}

/// What a substitute was chosen on, over the window.
final class H2hAbsenceFactsDto {
  /// Creates the facts.
  const H2hAbsenceFactsDto({
    required this.missed,
    required this.points,
    required this.exact,
    required this.activeDays,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAbsenceFactsDto.fromJson(Map<String, Object?> json) =>
      H2hAbsenceFactsDto(
        missed: (json['missed'] as int?) ?? 0,
        points: (json['points'] as int?) ?? 0,
        exact: (json['exact'] as int?) ?? 0,
        activeDays: (json['active_days'] as int?) ?? 0,
      );

  /// Matches of the window not predicted.
  final int missed;

  /// Points of the window.
  final int points;

  /// Exact scorelines of the window.
  final int exact;

  /// Days of the window with a prediction.
  final int activeDays;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'missed': missed,
    'points': points,
    'exact': exact,
    'active_days': activeDays,
  };
}

/// One round of the month and its place in the absence count.
final class H2hAbsenceRoundDto {
  /// Creates a round.
  const H2hAbsenceRoundDto({
    required this.roundId,
    required this.round,
    required this.day,
    required this.locked,
    required this.counted,
    required this.absent,
    this.excusedReason,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAbsenceRoundDto.fromJson(Map<String, Object?> json) =>
      H2hAbsenceRoundDto(
        roundId: (json['round_id'] as String?) ?? '',
        round: (json['round'] as int?) ?? 0,
        day: (json['day'] as String?) ?? '',
        locked: (json['locked'] as bool?) ?? false,
        counted: (json['counted'] as bool?) ?? false,
        absent: (json['absent'] as int?) ?? 0,
        excusedReason: json['excused_reason'] as String?,
      );

  /// The round (UUID string).
  final String roundId;

  /// Its number in the month.
  final int round;

  /// Its Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// Whether it started.
  final bool locked;

  /// Whether it counts for absence (started, past its last kickoff, a match
  /// left, not excused).
  final bool counted;

  /// Elite players absent from it (counted rounds only).
  final int absent;

  /// The admin's reason when it was excused.
  final String? excusedReason;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'round_id': roundId,
    'round': round,
    'day': day,
    'locked': locked,
    'counted': counted,
    'absent': absent,
    'excused_reason': excusedReason,
  };
}

/// An elite player absent from the latest counted rounds.
final class H2hAbsenceWatchDto {
  /// Creates a watch row.
  const H2hAbsenceWatchDto({
    required this.player,
    required this.group,
    required this.absentRounds,
    required this.warned,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAbsenceWatchDto.fromJson(Map<String, Object?> json) =>
      H2hAbsenceWatchDto(
        player: H2hAbsencePlayerDto.fromJson(
          (json['player'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
              const {},
        ),
        group: (json['group'] as int?) ?? 0,
        absentRounds: [
          for (final r in (json['absent_rounds'] as List<Object?>?) ?? const [])
            if (r is int) r,
        ],
        warned: (json['warned'] as bool?) ?? false,
      );

  /// The player.
  final H2hAbsencePlayerDto player;

  /// His group as players see it (1..4).
  final int group;

  /// The numbers of the rounds he missed in a row, oldest first.
  final List<int> absentRounds;

  /// Whether the warning went out.
  final bool warned;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'player': player.toJson(),
    'group': group,
    'absent_rounds': absentRounds,
    'warned': warned,
  };
}

/// A possible substitute, in the order the rules take them.
final class H2hAbsenceCandidateDto {
  /// Creates a candidate.
  const H2hAbsenceCandidateDto({
    required this.player,
    required this.group,
    required this.facts,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAbsenceCandidateDto.fromJson(Map<String, Object?> json) =>
      H2hAbsenceCandidateDto(
        player: H2hAbsencePlayerDto.fromJson(
          (json['player'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
              const {},
        ),
        group: (json['group'] as int?) ?? 0,
        facts: H2hAbsenceFactsDto.fromJson(
          (json['facts'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
              const {},
        ),
      );

  /// The player.
  final H2hAbsencePlayerDto player;

  /// His group as players see it (5 and up).
  final int group;

  /// What he is ranked on.
  final H2hAbsenceFactsDto facts;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'player': player.toJson(),
    'group': group,
    'facts': facts.toJson(),
  };
}

/// A seat swap.
final class H2hSeatMoveDto {
  /// Creates a swap.
  const H2hSeatMoveDto({
    required this.id,
    required this.kind,
    required this.fromRound,
    required this.out,
    required this.into,
    required this.eliteGroup,
    required this.extraGroup,
    required this.absentRounds,
    required this.createdAt,
    this.facts,
    this.reason,
    this.decidedBy,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hSeatMoveDto.fromJson(Map<String, Object?> json) {
    final facts = json['facts'];
    final out = json['out'];
    final into = json['in'];
    final by = json['decided_by'];
    return H2hSeatMoveDto(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'absence',
      fromRound: (json['from_round'] as int?) ?? 0,
      out: H2hAbsencePlayerDto.fromJson(
        out is Map<Object?, Object?> ? out.cast<String, Object?>() : const {},
      ),
      into: H2hAbsencePlayerDto.fromJson(
        into is Map<Object?, Object?> ? into.cast<String, Object?>() : const {},
      ),
      eliteGroup: (json['elite_group'] as int?) ?? 0,
      extraGroup: (json['extra_group'] as int?) ?? 0,
      absentRounds: [
        for (final r in (json['absent_rounds'] as List<Object?>?) ?? const [])
          if (r is int) r,
      ],
      createdAt: (json['created_at'] as String?) ?? '',
      facts: facts is Map<Object?, Object?>
          ? H2hAbsenceFactsDto.fromJson(facts.cast<String, Object?>())
          : null,
      reason: json['reason'] as String?,
      decidedBy: by is Map<Object?, Object?>
          ? H2hAbsencePlayerDto.fromJson(by.cast<String, Object?>())
          : null,
    );
  }

  /// The swap (UUID string).
  final String id;

  /// `absence` or `admin`.
  final String kind;

  /// The first round played in the new seats.
  final int fromRound;

  /// The player who left the elite seat.
  final H2hAbsencePlayerDto out;

  /// The player who took it.
  final H2hAbsencePlayerDto into;

  /// The elite group (1..4).
  final int eliteGroup;

  /// The extra group the substitute left (5 and up).
  final int extraGroup;

  /// The rounds [out] missed in a row.
  final List<int> absentRounds;

  /// When it was made (ISO-8601, UTC).
  final String createdAt;

  /// What the substitute was chosen on.
  final H2hAbsenceFactsDto? facts;

  /// The admin's reason for a swap by hand.
  final String? reason;

  /// The admin who decided, or null for the system.
  final H2hAbsencePlayerDto? decidedBy;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'from_round': fromRound,
    'out': out.toJson(),
    'in': into.toJson(),
    'elite_group': eliteGroup,
    'extra_group': extraGroup,
    'absent_rounds': absentRounds,
    'created_at': createdAt,
    'facts': facts?.toJson(),
    'reason': reason,
    'decided_by': decidedBy?.toJson(),
  };
}

/// Response body of `GET /admin/h2h/absence`.
final class H2hAbsenceViewDto {
  /// Creates a view.
  const H2hAbsenceViewDto({
    required this.monthStart,
    required this.active,
    required this.rounds,
    required this.watch,
    required this.candidates,
    required this.moves,
    this.nextRound,
    this.relegatesAt,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAbsenceViewDto.fromJson(Map<String, Object?> json) =>
      H2hAbsenceViewDto(
        monthStart: (json['month_start'] as String?) ?? '',
        active: (json['active'] as bool?) ?? false,
        nextRound: json['next_round'] as int?,
        relegatesAt: json['relegates_at'] as String?,
        rounds: [
          for (final m in _maps(json['rounds'])) H2hAbsenceRoundDto.fromJson(m),
        ],
        watch: [
          for (final m in _maps(json['watch'])) H2hAbsenceWatchDto.fromJson(m),
        ],
        candidates: [
          for (final m in _maps(json['candidates']))
            H2hAbsenceCandidateDto.fromJson(m),
        ],
        moves: [
          for (final m in _maps(json['moves'])) H2hSeatMoveDto.fromJson(m),
        ],
      );

  /// The month's first day, `YYYY-MM-DD`.
  final String monthStart;

  /// Whether the rules run this month.
  final bool active;

  /// The next round not started, when there is one.
  final int? nextRound;

  /// When the system swaps before it (ISO-8601, UTC), or null.
  final String? relegatesAt;

  /// The month's rounds.
  final List<H2hAbsenceRoundDto> rounds;

  /// Elite players absent from the latest counted rounds.
  final List<H2hAbsenceWatchDto> watch;

  /// The next substitutes, best first.
  final List<H2hAbsenceCandidateDto> candidates;

  /// The month's swaps, oldest first.
  final List<H2hSeatMoveDto> moves;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'month_start': monthStart,
    'active': active,
    'next_round': nextRound,
    'relegates_at': relegatesAt,
    'rounds': [for (final r in rounds) r.toJson()],
    'watch': [for (final w in watch) w.toJson()],
    'candidates': [for (final c in candidates) c.toJson()],
    'moves': [for (final m in moves) m.toJson()],
  };
}

/// Request body of `POST /admin/h2h/relegations`.
final class H2hRelegationRequestDto {
  /// Creates a request.
  const H2hRelegationRequestDto({required this.userId, required this.reason});

  /// The elite player to relegate (UUID string).
  final String userId;

  /// Why (1..300 characters).
  final String reason;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'user_id': userId, 'reason': reason};
}

/// Request body of `POST /admin/h2h/excusals`.
final class H2hExcusalRequestDto {
  /// Creates a request.
  const H2hExcusalRequestDto({required this.roundId, required this.reason});

  /// The round to take out of the count (UUID string).
  final String roundId;

  /// Why (1..300 characters).
  final String reason;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'round_id': roundId, 'reason': reason};
}
