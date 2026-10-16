/// Versioned wire shapes for the fixture-IDENTITY seam (API ADR §4: DTOs are
/// decoupled from the schema and carry a schema version so client and
/// archived payloads evolve safely).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR §3).
///
/// Integrity boundary (Axiom 3; Next-Task decision 2026-07-11, option (a),
/// applied to schedule rather than outcome): a fixture's identity — which two
/// sides play and when — is admin-fed, never client-computed. It carries **no**
/// competition/round reference (the same fixture may be linked into many
/// rounds). [FixtureScheduleRequestDto] is the ONE client-supplied body shape,
/// reused unchanged for both registration (`POST /fixtures`, where the fixture
/// id is server-generated) and correction (`PUT /fixtures/{id}`, where the id
/// travels in the path) — mirroring the suspend/reinstate precedent in the
/// Admin Panel contracts (`SuspendUserRequestDto`): same body, the id/action
/// distinction lives in the route, never duplicated across two DTOs.
library;

/// The wire shape echoed back for a fixture's registered identity (the
/// response of both `POST /fixtures` and `PUT /fixtures/{id}`, and the read
/// projection of the domain `FixtureSchedule`).
///
/// Carries no competition/round reference (Axiom 3). [kickoffAt] is an ISO
/// 8601 UTC timestamp string — every DTO on the wire is String/int only, so a
/// `DateTime` field is never passed as a native type across the boundary.
final class FixtureScheduleDto {
  /// Creates a fixture-schedule DTO.
  const FixtureScheduleDto({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.homeTeamId,
    this.awayTeamId,
    this.leagueId,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureScheduleDto.fromJson(Map<String, Object?> json) {
    return FixtureScheduleDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      homeTeam: json['home_team']! as String,
      awayTeam: json['away_team']! as String,
      kickoffAt: json['kickoff_at']! as String,
      homeTeamId: json['home_team_id'] as String?,
      awayTeamId: json['away_team_id'] as String?,
      leagueId: json['league_id'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture id (UUID string).
  final String fixtureId;

  /// The home side's team name (server-trimmed, 1-120 characters).
  final String homeTeam;

  /// The away side's team name (server-trimmed, 1-120 characters, distinct
  /// from [homeTeam]).
  final String awayTeam;

  /// The kickoff time as an ISO 8601 UTC timestamp string.
  final String kickoffAt;

  /// The home side's resolved Football Data team id, or `null` when the
  /// admin picked a team not yet in the catalog (or this fixture predates
  /// the enrichment).
  final String? homeTeamId;

  /// The away side's resolved Football Data team id, same nullability as
  /// [homeTeamId].
  final String? awayTeamId;

  /// The league this fixture belongs to, or `null` when none is on file.
  final String? leagueId;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
    'home_team_id': homeTeamId,
    'away_team_id': awayTeamId,
    'league_id': leagueId,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureScheduleDto &&
      other.fixtureId == fixtureId &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId &&
      other.leagueId == leagueId &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
    leagueId,
    schemaVersion,
  );
}

/// The request body of a fixture-identity registration/correction command
/// (`POST /fixtures` | `PUT /fixtures/{id}`, admin-only). The fixture id is
/// EITHER server-generated (register) OR taken from the path (correct) —
/// never from this body — so the same shape serves both routes (see the
/// library-level doc comment).
final class FixtureScheduleRequestDto {
  /// Creates a fixture-schedule request body.
  const FixtureScheduleRequestDto({
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.homeTeamId,
    this.awayTeamId,
    this.leagueId,
    this.isTest = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field. A missing field surfaces as an explicit
  /// `null` so the use-case reports the validation failure (never a silent
  /// empty team name or fabricated kickoff time).
  factory FixtureScheduleRequestDto.fromJson(Map<String, Object?> json) {
    return FixtureScheduleRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      homeTeam: json['home_team'] as String?,
      awayTeam: json['away_team'] as String?,
      kickoffAt: json['kickoff_at'] as String?,
      homeTeamId: json['home_team_id'] as String?,
      awayTeamId: json['away_team_id'] as String?,
      leagueId: json['league_id'] as String?,
      isTest: json['is_test'] == true,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The home side's team name. Nullable on the wire only so a malformed body
  /// (missing field) can be reported as a validation failure by the use-case
  /// rather than throwing at parse time.
  final String? homeTeam;

  /// The away side's team name.
  final String? awayTeam;

  /// The kickoff time as an ISO 8601 timestamp string.
  final String? kickoffAt;

  /// The home side's Football Data team id, when the admin picked one from
  /// the team catalog (optional — a legacy free-text-only entry is still
  /// accepted, Axiom 3).
  final String? homeTeamId;

  /// The away side's Football Data team id, same optionality as
  /// [homeTeamId].
  final String? awayTeamId;

  /// The league the admin filed this fixture under. Optional on the wire
  /// so an older client keeps working; when absent, the stored league is
  /// left as it is rather than cleared.
  final String? leagueId;

  /// Whether to register it as a test fixture (migration 0098): admins
  /// only, never scored. Fixed once registered.
  final bool isTest;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
    'home_team_id': homeTeamId,
    'away_team_id': awayTeamId,
    'league_id': leagueId,
    if (isTest) 'is_test': true,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureScheduleRequestDto &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId &&
      other.leagueId == leagueId &&
      other.isTest == isTest &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
    leagueId,
    isTest,
    schemaVersion,
  );
}

/// The body of `POST /admin/fixture-visibility` (migration 0098): hide the
/// named fixtures from the players, or show them again.
final class FixtureVisibilityRequestDto {
  /// Creates the body.
  const FixtureVisibilityRequestDto({
    required this.fixtureIds,
    required this.hidden,
    this.schemaVersion = currentSchemaVersion,
  });

  /// The `hidden` field of an untrusted body, or `null` when it is missing
  /// or not a boolean, so the use-case refuses it rather than guessing.
  static bool? hiddenOf(Map<String, Object?> json) {
    final Object? raw = json['hidden'];
    return raw is bool ? raw : null;
  }

  /// The `fixture_ids` field of an untrusted body, or `null` when it is not
  /// a list of strings.
  static List<String>? fixtureIdsOf(Map<String, Object?> json) {
    final Object? raw = json['fixture_ids'];
    if (raw is! List<Object?>) return null;
    final ids = <String>[];
    for (final Object? id in raw) {
      if (id is! String) return null;
      ids.add(id);
    }
    return ids;
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixtures to change (UUID strings).
  final List<String> fixtureIds;

  /// `true` hides them, `false` shows them.
  final bool hidden;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_ids': fixtureIds,
    'hidden': hidden,
  };
}

/// The answer of `POST /admin/fixture-visibility`: the fixtures whose state
/// changed (one already hidden, or already shown, is not listed).
final class FixtureVisibilityResultDto {
  /// Creates the answer.
  const FixtureVisibilityResultDto({
    required this.changed,
    required this.hidden,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FixtureVisibilityResultDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['changed'];
    return FixtureVisibilityResultDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      changed: <String>[
        if (raw is List<Object?>)
          for (final Object? id in raw)
            if (id is String) id,
      ],
      hidden: json['hidden'] == true,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixtures that changed (UUID strings).
  final List<String> changed;

  /// The state they are now in.
  final bool hidden;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'changed': changed,
    'hidden': hidden,
  };
}

/// One row of `GET /admin/fixtures/{id}/copies` (migration 0176, script
/// 95): the fixture asked about ([isSelf]) or another copy of its match.
final class FixtureCopyDto {
  /// Creates one row.
  const FixtureCopyDto({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.hidden,
    required this.predictions,
    required this.doubles,
    required this.hasResult,
    required this.linked,
    required this.isSelf,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FixtureCopyDto.fromJson(Map<String, Object?> json) => FixtureCopyDto(
    fixtureId: json['fixture_id'] as String? ?? '',
    homeTeam: json['home_team'] as String? ?? '',
    awayTeam: json['away_team'] as String? ?? '',
    kickoffAt: json['kickoff_at'] as String? ?? '',
    hidden: json['hidden'] == true,
    predictions: (json['predictions'] as num?)?.toInt() ?? 0,
    doubles: (json['doubles'] as num?)?.toInt() ?? 0,
    hasResult: json['has_result'] == true,
    linked: json['linked'] == true,
    isSelf: json['is_self'] == true,
  );

  /// The fixture id (UUID string).
  final String fixtureId;

  /// The home side as stored.
  final String homeTeam;

  /// The away side as stored.
  final String awayTeam;

  /// The kickoff, ISO 8601 UTC.
  final String kickoffAt;

  /// Whether it is hidden from the players.
  final bool hidden;

  /// How many predictions it holds.
  final int predictions;

  /// How many of them are doubled.
  final int doubles;

  /// Whether its result is recorded.
  final bool hasResult;

  /// Whether a provider match is linked to it.
  final bool linked;

  /// Whether this row is the fixture asked about.
  final bool isSelf;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
    'hidden': hidden,
    'predictions': predictions,
    'doubles': doubles,
    'has_result': hasResult,
    'linked': linked,
    'is_self': isSelf,
  };
}

/// The answer of `GET /admin/fixtures/{id}/copies`: the fixture first,
/// then the other copies of its match not merged yet.
final class FixtureCopiesDto {
  /// Creates the answer.
  const FixtureCopiesDto({
    required this.copies,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FixtureCopiesDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['copies'];
    return FixtureCopiesDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      copies: <FixtureCopyDto>[
        if (raw is List<Object?>)
          for (final Object? row in raw)
            if (row is Map<String, Object?>) FixtureCopyDto.fromJson(row),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The rows.
  final List<FixtureCopyDto> copies;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'copies': [for (final c in copies) c.toJson()],
  };
}

/// The body of `POST /admin/fixtures/{id}/merge` (migration 0176): merge
/// fixture `{id}` into [into], or only preview it ([apply] false).
final class FixtureMergeRequestDto {
  /// Creates the body.
  const FixtureMergeRequestDto({
    required this.into,
    required this.apply,
    this.schemaVersion = currentSchemaVersion,
  });

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The copy that stays (UUID string).
  final String into;

  /// `true` merges, `false` answers what a merge would do.
  final bool apply;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'into': into,
    'apply': apply,
  };
}

/// The answer of `POST /admin/fixtures/{id}/merge`: what the merge did, or
/// would do.
final class FixtureMergeReportDto {
  /// Creates the answer.
  const FixtureMergeReportDto({
    required this.moved,
    required this.doublesMoved,
    required this.doublesDropped,
    required this.bothPredicted,
    required this.late,
    required this.notParticipant,
    required this.linkMoved,
    required this.keptHasResult,
    required this.applied,
    required this.rescored,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FixtureMergeReportDto.fromJson(Map<String, Object?> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return FixtureMergeReportDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      moved: n('moved'),
      doublesMoved: n('doubles_moved'),
      doublesDropped: n('doubles_dropped'),
      bothPredicted: n('both_predicted'),
      late: n('late'),
      notParticipant: n('not_participant'),
      linkMoved: json['link_moved'] == true,
      keptHasResult: json['kept_has_result'] == true,
      applied: json['applied'] == true,
      rescored: json['rescored'] == true,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Predictions moved to the kept copy.
  final int moved;

  /// Of [moved], those that kept their double.
  final int doublesMoved;

  /// Of [moved], those that lost their double (the day's one double was
  /// already on another match).
  final int doublesDropped;

  /// Players who predicted both copies.
  final int bothPredicted;

  /// Predictions sent after the kept copy's kickoff, left where they were.
  final int late;

  /// Players not in a season of the kept copy, left where they were.
  final int notParticipant;

  /// Whether the provider link went to the kept copy.
  final bool linkMoved;

  /// Whether the kept copy has its result.
  final bool keptHasResult;

  /// Whether the merge was done (`false`: a preview).
  final bool applied;

  /// Whether the kept copy was scored again after the merge.
  final bool rescored;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'moved': moved,
    'doubles_moved': doublesMoved,
    'doubles_dropped': doublesDropped,
    'both_predicted': bothPredicted,
    'late': late,
    'not_participant': notParticipant,
    'link_moved': linkMoved,
    'kept_has_result': keptHasResult,
    'applied': applied,
    'rescored': rescored,
  };
}
