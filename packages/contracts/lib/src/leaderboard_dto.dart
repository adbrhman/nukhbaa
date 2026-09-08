/// Versioned wire shapes for the Leaderboards context (API ADR §4: DTOs are
/// decoupled from the schema and carry a schema version so client and archived
/// payloads evolve safely).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR §3).
///
/// Integrity boundary (Axioms 2/5): a leaderboard is a **read-only** surface on
/// the wire — a server-produced projection over the append-only ledger. Totals
/// and ranks here are computed by the server; the client never submits or
/// computes a point total, and there is deliberately **no** command DTO in this
/// file (a leaderboard is only ever read). The entry shapes name a participant
/// by id only (Axiom 4: one score, ranked everywhere — no group reference on the
/// entry itself; a group/global board is a later phase over the same shape).
library;

/// The wire shape of one participant's line on a season leaderboard (read
/// projection of the domain `LeaderboardEntry`).
///
/// Names the participant by id only; carries the standard-competition
/// [rank] ("1224": tied totals share a rank, the next distinct total skips), the
/// signed [totalPoints] (equals that participant's ledger balance — a
/// `correction` is already netted in, so it may be negative — Axiom 5), and the
/// [entryCount] of immutable ledger movements the total sums (audit). Every
/// field is server-produced; none is client-writable (Axioms 2/5). Versioned.
final class LeaderboardEntryDto {
  /// Creates a leaderboard-entry DTO.
  const LeaderboardEntryDto({
    required this.rank,
    required this.participantId,
    required this.displayName,
    required this.totalPoints,
    required this.entryCount,
    this.previousRank,
    this.exactCount = 0,
    this.settledCount = 0,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field. [displayName] falls back to
  /// [participantId] for a legacy payload that predates the field, so an
  /// older cached response still renders something rather than a null crash.
  factory LeaderboardEntryDto.fromJson(Map<String, Object?> json) {
    final participantId = json['participant_id']! as String;
    return LeaderboardEntryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      rank: json['rank']! as int,
      participantId: participantId,
      displayName: (json['display_name'] as String?) ?? participantId,
      totalPoints: json['total_points']! as int,
      entryCount: json['entry_count']! as int,
      previousRank: json['previous_rank'] as int?,
      exactCount: (json['exact_count'] as int?) ?? 0,
      settledCount: (json['settled_count'] as int?) ?? 0,
    );
  }

  /// The current schema version for this DTO. Bumped to 2 by the addition of
  /// the nullable [previousRank]; a v1 payload simply lacks the key and
  /// deserializes with a null [previousRank], so an older cached response
  /// still renders — without arrows.
  /// Version 3 adds [exactCount]/[settledCount]; an older payload lacks the
  /// keys and deserializes to 0, so a cached response still renders --
  /// without accuracy.
  static const int currentSchemaVersion = 3;

  /// The participant's standard-competition rank (1-based; tied totals share a
  /// rank, the next distinct total skips by the number tied).
  final int rank;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The platform-owned display name of the user behind this participant.
  final String displayName;

  /// The signed point total — the server projection over the participant's
  /// append-only ledger stream (equals their balance; may be negative if a
  /// correction nets below zero — Axiom 5).
  final int totalPoints;

  /// How many immutable ledger movements contributed to [totalPoints] (audit).
  final int entryCount;

  /// The rank this participant held at the most recent daily snapshot, or null
  /// when there is nothing to compare against. The client derives the arrow as
  /// `previousRank - rank`; the delta is never sent pre-computed, so the two
  /// numbers on screen always come from the same pair.
  final int? previousRank;

  /// Settled fixtures the participant called exactly right, and settled
  /// fixtures in total. The percentage is derived from the pair by the
  /// reader, never sent pre-divided, so the ratio and its inputs cannot
  /// drift; `settledCount == 0` means there is no accuracy yet at all.
  final int exactCount;

  /// The denominator behind [exactCount] -- see that field.
  final int settledCount;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'rank': rank,
    'participant_id': participantId,
    'display_name': displayName,
    'total_points': totalPoints,
    'entry_count': entryCount,
    'previous_rank': previousRank,
    'exact_count': exactCount,
    'settled_count': settledCount,
  };

  @override
  bool operator ==(Object other) =>
      other is LeaderboardEntryDto &&
      other.rank == rank &&
      other.participantId == participantId &&
      other.displayName == displayName &&
      other.totalPoints == totalPoints &&
      other.entryCount == entryCount &&
      other.previousRank == previousRank &&
      other.exactCount == exactCount &&
      other.settledCount == settledCount &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    rank,
    participantId,
    displayName,
    totalPoints,
    entryCount,
    previousRank,
    exactCount,
    settledCount,
    schemaVersion,
  );
}

/// The wire shape of a season's ranked standings (read projection of the domain
/// `SeasonLeaderboard`) — the response of `GET /seasons/{id}/leaderboard`.
///
/// Names the season by id and carries the [entries] in the server-defined
/// display order (points descending, then joinedAt ascending, then participant
/// id ascending — a total, reproducible order). An **empty** [entries] list is a
/// legitimate result: a season with no participants. Visibility gating
/// (season-membership) lives in the use-case, not this shape. Versioned.
final class SeasonLeaderboardDto {
  /// Creates a season-leaderboard DTO.
  const SeasonLeaderboardDto({
    required this.seasonId,
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory SeasonLeaderboardDto.fromJson(Map<String, Object?> json) {
    final raw = json['entries']! as List<Object?>;
    return SeasonLeaderboardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      seasonId: json['season_id']! as String,
      entries: raw
          .map(
            (e) => LeaderboardEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season these standings are for (UUID string).
  final String seasonId;

  /// The ranked entries, in the server-defined display order.
  final List<LeaderboardEntryDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'season_id': seasonId,
    'entries': [for (final e in entries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is SeasonLeaderboardDto &&
      other.seasonId == seasonId &&
      _listEquals(other.entries, entries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(seasonId, Object.hashAll(entries), schemaVersion);

  static bool _listEquals(
    List<LeaderboardEntryDto> a,
    List<LeaderboardEntryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The wire shape of one participant's line on a round leaderboard (read
/// projection of the domain `RoundLeaderboardEntry`) — the ranked counterpart
/// of `RoundScoreDto` for the same round.
///
/// Names the participant by id only and carries the standard-competition
/// [rank] ("1224") and the [totalPoints] Scoring already computed for that
/// round (Axiom 5: the SAME points as `RoundScoreDto.totalPoints`, never
/// recomputed here). Every field is server-produced; none is client-writable.
/// Versioned.
final class RoundLeaderboardEntryDto {
  /// Creates a round-leaderboard-entry DTO.
  const RoundLeaderboardEntryDto({
    required this.rank,
    required this.participantId,
    required this.totalPoints,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory RoundLeaderboardEntryDto.fromJson(Map<String, Object?> json) {
    return RoundLeaderboardEntryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      rank: json['rank']! as int,
      participantId: json['participant_id']! as String,
      totalPoints: json['total_points']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The participant's standard-competition rank (1-based; tied totals share a
  /// rank, the next distinct total skips by the number tied).
  final int rank;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The round's already-computed total for this participant (echoed from
  /// `RoundScoreDto.totalPoints`).
  final int totalPoints;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'rank': rank,
    'participant_id': participantId,
    'total_points': totalPoints,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundLeaderboardEntryDto &&
      other.rank == rank &&
      other.participantId == participantId &&
      other.totalPoints == totalPoints &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(rank, participantId, totalPoints, schemaVersion);
}

/// The wire shape of a round's ranked standings (read projection of the domain
/// `RoundLeaderboard`) — the response of `GET /rounds/{id}/leaderboard`.
///
/// Names the round by id and carries the [entries] in the server-defined
/// display order (points descending, then participant id ascending). An
/// **empty** [entries] list is a legitimate result: a scored round nobody
/// predicted. Visibility gating (round scored + season membership) lives in
/// the use-case, not this shape. Versioned.
final class RoundLeaderboardDto {
  /// Creates a round-leaderboard DTO.
  const RoundLeaderboardDto({
    required this.roundId,
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory RoundLeaderboardDto.fromJson(Map<String, Object?> json) {
    final raw = json['entries']! as List<Object?>;
    return RoundLeaderboardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      roundId: json['round_id']! as String,
      entries: raw
          .map(
            (e) => RoundLeaderboardEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The round these standings are for (UUID string).
  final String roundId;

  /// The ranked entries, in the server-defined display order.
  final List<RoundLeaderboardEntryDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round_id': roundId,
    'entries': [for (final e in entries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RoundLeaderboardDto &&
      other.roundId == roundId &&
      _listEquals(other.entries, entries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(roundId, Object.hashAll(entries), schemaVersion);

  static bool _listEquals(
    List<RoundLeaderboardEntryDto> a,
    List<RoundLeaderboardEntryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The wire shape of one line on the platform-wide, all-time Hall of Fame
/// (read projection of the domain `HallOfFameEntry`).
///
/// Names the [userId] (constant across every season, unlike a season entry's
/// per-season `participant_id`) and carries the standard-competition [rank],
/// the signed [totalPoints] (the SUM of that user's ledger amounts across
/// every season they have played — Axiom 5), and [seasonsPlayed] (how many
/// distinct seasons contributed to that total). Every field is
/// server-produced; none is client-writable. Versioned.
final class HallOfFameEntryDto {
  /// Creates a Hall of Fame entry DTO.
  const HallOfFameEntryDto({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.totalPoints,
    required this.seasonsPlayed,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field. [displayName] falls back to [userId]
  /// for a legacy payload that predates the field, so older cached responses
  /// still render something rather than a null crash.
  factory HallOfFameEntryDto.fromJson(Map<String, Object?> json) {
    final userId = json['user_id']! as String;
    return HallOfFameEntryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      rank: json['rank']! as int,
      userId: userId,
      displayName: (json['display_name'] as String?) ?? userId,
      totalPoints: json['total_points']! as int,
      seasonsPlayed: json['seasons_played']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The user's standard-competition ("1224") rank on the all-time board.
  final int rank;

  /// The owning user id (UUID string) — constant across seasons.
  final String userId;

  /// The user's platform-owned display name, shown on the board instead of
  /// the raw [userId].
  final String displayName;

  /// The signed all-time point total.
  final int totalPoints;

  /// How many distinct seasons contributed to [totalPoints].
  final int seasonsPlayed;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'rank': rank,
    'user_id': userId,
    'display_name': displayName,
    'total_points': totalPoints,
    'seasons_played': seasonsPlayed,
  };

  @override
  bool operator ==(Object other) =>
      other is HallOfFameEntryDto &&
      other.rank == rank &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.totalPoints == totalPoints &&
      other.seasonsPlayed == seasonsPlayed &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    rank,
    userId,
    displayName,
    totalPoints,
    seasonsPlayed,
    schemaVersion,
  );
}

/// The wire shape of the platform-wide Hall of Fame (read projection of the
/// domain `HallOfFame`) — the response of `GET /leaderboard/hall-of-fame`.
///
/// Carries the [entries] in the server-defined display order (points
/// descending, then user id ascending). An **empty** [entries] list is a
/// legitimate result (nobody has ever been credited yet). Unlike
/// [SeasonLeaderboardDto], visibility is intentionally public to any
/// authenticated user — there is no membership gate to encode here. Versioned.
final class HallOfFameDto {
  /// Creates a Hall of Fame DTO.
  const HallOfFameDto({
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory HallOfFameDto.fromJson(Map<String, Object?> json) {
    final raw = json['entries']! as List<Object?>;
    return HallOfFameDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      entries: raw
          .map(
            (e) => HallOfFameEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The ranked entries, in the server-defined display order.
  final List<HallOfFameEntryDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'entries': [for (final e in entries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is HallOfFameDto &&
      _listEquals(other.entries, entries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(Object.hashAll(entries), schemaVersion);

  static bool _listEquals(
    List<HallOfFameEntryDto> a,
    List<HallOfFameEntryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The wire shape of one participant's line on a season's live "monthly"
/// fixture leaderboard (read projection of the domain
/// `FixtureLeaderboardEntry`) — the Axiom 4 Amendment sibling of
/// [RoundLeaderboardEntryDto], aggregated over every fixture scored so far
/// instead of a single round.
///
/// Names the participant by id only and carries the standard-competition
/// [rank] ("1224"), the running [totalPoints] summed from every
/// already-computed fixture score so far (Axiom 5: never recomputed here),
/// and [fixturesScored] — how many of the season's fixtures contributed to
/// that total (a transparency count for a board that is live/partial by
/// construction, never gated on "the season being finished"). Every field is
/// server-produced; none is client-writable. Versioned.
final class FixtureLeaderboardEntryDto {
  /// Creates a fixture-leaderboard-entry DTO.
  const FixtureLeaderboardEntryDto({
    required this.rank,
    required this.participantId,
    required this.displayName,
    required this.totalPoints,
    required this.fixturesScored,
    this.exactCount = 0,
    this.decidedCount = 0,
    this.previousRank,
    this.avatarUrl,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field. [displayName] falls back to
  /// [participantId] for a legacy payload that predates the field, so an
  /// older cached response still renders something rather than a null crash.
  factory FixtureLeaderboardEntryDto.fromJson(Map<String, Object?> json) {
    final participantId = json['participant_id']! as String;
    return FixtureLeaderboardEntryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      rank: json['rank']! as int,
      participantId: participantId,
      displayName: (json['display_name'] as String?) ?? participantId,
      totalPoints: json['total_points']! as int,
      fixturesScored: json['fixtures_scored']! as int,
      exactCount: (json['exact_count'] as int?) ?? 0,
      decidedCount: (json['decided_count'] as int?) ?? 0,
      previousRank: json['previous_rank'] as int?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  /// The current schema version for this DTO. Version 2 added
  /// [exactCount]/[decidedCount]; version 3 added [previousRank]; version 4
  /// adds [avatarUrl]. An older payload lacks the keys and deserializes to
  /// 0/null, so a cached response still renders -- without accuracy, without
  /// arrows, without pictures.
  static const int currentSchemaVersion = 4;

  /// The participant's standard-competition rank (1-based; tied totals share
  /// a rank, the next distinct total skips by the number tied).
  final int rank;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The platform-owned display name of the user behind this participant.
  final String displayName;

  /// The running point total summed from every fixture score so far.
  final int totalPoints;

  /// How many of the season's fixtures have been scored for this participant
  /// so far.
  final int fixturesScored;

  /// Decided fixtures the participant called exactly right, and decided
  /// fixtures in total. The percentage is derived from the pair by the
  /// reader, never sent pre-divided, so the ratio and its inputs cannot
  /// drift; `decidedCount == 0` means there is no accuracy yet at all.
  ///
  /// [decidedCount] is narrower than [fixturesScored]: it excludes fixtures
  /// that were missed (never predicted) and still pending.
  final int exactCount;

  /// The denominator behind [exactCount] -- see that field.
  final int decidedCount;

  /// The rank this participant held at the season's most recent daily
  /// snapshot, or null when there is nothing to compare against. The client
  /// derives the arrow as `previousRank - rank`; the delta is never sent
  /// pre-computed, so the two numbers on screen always come from the same
  /// pair.
  final int? previousRank;

  /// The participant's profile picture, as a **server-relative** URL, or null
  /// when they have none. Relative because the server sits behind a proxy and
  /// does not know its own public origin; the client resolves it against the
  /// same API base it used for this very request. The `v` query parameter is
  /// the picture's version, so a replaced picture is a different URL and no
  /// device keeps serving the old bytes.
  final String? avatarUrl;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'rank': rank,
    'participant_id': participantId,
    'display_name': displayName,
    'total_points': totalPoints,
    'fixtures_scored': fixturesScored,
    'exact_count': exactCount,
    'decided_count': decidedCount,
    'previous_rank': previousRank,
    'avatar_url': avatarUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureLeaderboardEntryDto &&
      other.rank == rank &&
      other.participantId == participantId &&
      other.displayName == displayName &&
      other.totalPoints == totalPoints &&
      other.fixturesScored == fixturesScored &&
      other.exactCount == exactCount &&
      other.decidedCount == decidedCount &&
      other.previousRank == previousRank &&
      other.avatarUrl == avatarUrl &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    rank,
    participantId,
    displayName,
    totalPoints,
    fixturesScored,
    exactCount,
    decidedCount,
    previousRank,
    avatarUrl,
    schemaVersion,
  );
}

/// The wire shape of a season's live "monthly" fixture-leaderboard standings
/// (read projection of the domain `FixtureLeaderboard`) — the response of
/// `GET /seasons/{id}/fixture-leaderboard` (Axiom 4 Amendment sibling of
/// [RoundLeaderboardDto]).
///
/// Names the season by id and carries the [entries] in the server-defined
/// display order (points descending, then participant id ascending). An
/// **empty** [entries] list is a legitimate result: no fixture has been
/// scored yet — this board is live/partial by construction, never gated on
/// "the season being finished". Visibility gating (season-membership) lives
/// in the use-case, not this shape. Versioned.
final class FixtureLeaderboardDto {
  /// Creates a fixture-leaderboard DTO.
  const FixtureLeaderboardDto({
    required this.seasonId,
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureLeaderboardDto.fromJson(Map<String, Object?> json) {
    final raw = json['entries']! as List<Object?>;
    return FixtureLeaderboardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      seasonId: json['season_id']! as String,
      entries: raw
          .map(
            (e) => FixtureLeaderboardEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season these standings are for (UUID string).
  final String seasonId;

  /// The ranked entries, in the server-defined display order.
  final List<FixtureLeaderboardEntryDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'season_id': seasonId,
    'entries': [for (final e in entries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureLeaderboardDto &&
      other.seasonId == seasonId &&
      _listEquals(other.entries, entries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(seasonId, Object.hashAll(entries), schemaVersion);

  static bool _listEquals(
    List<FixtureLeaderboardEntryDto> a,
    List<FixtureLeaderboardEntryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
