#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# 1) packages/contracts — Open/Link request DTOs
cat > packages/contracts/lib/src/competition_dto.dart << 'NUKHBAA_EOF'
/// Versioned wire shapes for the Competition context (API ADR, Section 4: DTOs
/// are decoupled from the schema and carry a schema version so client and
/// archived payloads evolve safely).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR, Section 3). They are *read* projections
/// — a command handler returns them, a client renders them — and deliberately
/// carry only stable, safe identity/structure facts, never internal state.
library;

/// The wire shape of a competition (read projection).
final class CompetitionDto {
  /// Creates a competition DTO.
  const CompetitionDto({
    required this.id,
    required this.name,
    required this.format,
    required this.visibility,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory CompetitionDto.fromJson(Map<String, Object?> json) {
    return CompetitionDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      name: json['name']! as String,
      format: json['format']! as String,
      visibility: json['visibility']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The competition id (UUID string).
  final String id;

  /// The display name.
  final String name;

  /// The game-format token (e.g. `football_scoreline`).
  final String format;

  /// The visibility token (`public` / `private`).
  final String visibility;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'name': name,
    'format': format,
    'visibility': visibility,
  };

  @override
  bool operator ==(Object other) =>
      other is CompetitionDto &&
      other.id == id &&
      other.name == name &&
      other.format == format &&
      other.visibility == visibility &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(id, name, format, visibility, schemaVersion);
}

/// The wire shape of a competition season (read projection).
final class SeasonDto {
  /// Creates a season DTO.
  const SeasonDto({
    required this.id,
    required this.competitionId,
    required this.label,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory SeasonDto.fromJson(Map<String, Object?> json) {
    return SeasonDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      competitionId: json['competition_id']! as String,
      label: json['label']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season id (UUID string).
  final String id;

  /// The owning competition id (UUID string).
  final String competitionId;

  /// The display label (e.g. "2026/27").
  final String label;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'competition_id': competitionId,
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      other is SeasonDto &&
      other.id == id &&
      other.competitionId == competitionId &&
      other.label == label &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(id, competitionId, label, schemaVersion);
}

/// The wire shape of a round (read projection).
///
/// Intentionally excludes the frozen ruleset snapshot: the snapshot is an
/// internal, Scoring-owned structure (Application ADR, Section 2.10), not part
/// of the client-facing round read model. Only the ruleset *version* is exposed
/// so a client can display "rules v3" without receiving the opaque payload.
final class RoundDto {
  /// Creates a round DTO.
  const RoundDto({
    required this.id,
    required this.seasonId,
    required this.sequence,
    required this.predictionDeadline,
    required this.status,
    required this.rulesetVersion,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory RoundDto.fromJson(Map<String, Object?> json) {
    return RoundDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      seasonId: json['season_id']! as String,
      sequence: json['sequence']! as int,
      predictionDeadline: json['prediction_deadline']! as String,
      status: json['status']! as String,
      rulesetVersion: json['ruleset_version']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The round id (UUID string).
  final String id;

  /// The owning season id (UUID string).
  final String seasonId;

  /// The 1-based ordinal within the season.
  final int sequence;

  /// The prediction deadline as an ISO-8601 UTC string.
  final String predictionDeadline;

  /// The lifecycle status token (`open` / `locked` / `scored`).
  final String status;

  /// The version of the ruleset frozen for this round.
  final int rulesetVersion;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'season_id': seasonId,
    'sequence': sequence,
    'prediction_deadline': predictionDeadline,
    'status': status,
    'ruleset_version': rulesetVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundDto &&
      other.id == id &&
      other.seasonId == seasonId &&
      other.sequence == sequence &&
      other.predictionDeadline == predictionDeadline &&
      other.status == status &&
      other.rulesetVersion == rulesetVersion &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    seasonId,
    sequence,
    predictionDeadline,
    status,
    rulesetVersion,
    schemaVersion,
  );
}

/// The wire shape of a participant enrolment (read projection).
final class ParticipantDto {
  /// Creates a participant DTO.
  const ParticipantDto({
    required this.id,
    required this.seasonId,
    required this.userId,
    required this.status,
    required this.joinedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory ParticipantDto.fromJson(Map<String, Object?> json) {
    return ParticipantDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      seasonId: json['season_id']! as String,
      userId: json['user_id']! as String,
      status: json['status']! as String,
      joinedAt: json['joined_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The participant id (UUID string).
  final String id;

  /// The season id (UUID string).
  final String seasonId;

  /// The enrolled user id (UUID string).
  final String userId;

  /// The enrolment status token (`active` / `withdrawn`).
  final String status;

  /// The enrolment instant as an ISO-8601 UTC string.
  final String joinedAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'season_id': seasonId,
    'user_id': userId,
    'status': status,
    'joined_at': joinedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is ParticipantDto &&
      other.id == id &&
      other.seasonId == seasonId &&
      other.userId == userId &&
      other.status == status &&
      other.joinedAt == joinedAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(id, seasonId, userId, status, joinedAt, schemaVersion);
}

/// The wire shape of a round↔fixture link (read projection).
final class RoundFixtureDto {
  /// Creates a round-fixture link DTO.
  const RoundFixtureDto({
    required this.roundId,
    required this.fixtureId,
    required this.displayOrder,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory RoundFixtureDto.fromJson(Map<String, Object?> json) {
    return RoundFixtureDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      roundId: json['round_id']! as String,
      fixtureId: json['fixture_id']! as String,
      displayOrder: json['display_order']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning round id (UUID string).
  final String roundId;

  /// The referenced fixture id (UUID string).
  final String fixtureId;

  /// The 0-based presentation order within the round.
  final int displayOrder;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round_id': roundId,
    'fixture_id': fixtureId,
    'display_order': displayOrder,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundFixtureDto &&
      other.roundId == roundId &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(roundId, fixtureId, displayOrder, schemaVersion);
}

/// A round-fixture link enriched with its fixture-schedule identity (team
/// names + kickoff), for the client's prediction-form render (Session
/// decision 2026-08-07: `GET /rounds/{id}/fixtures` widened instead of a new
/// endpoint). [homeTeam]/[awayTeam]/[kickoffAt] are nullable — a linked
/// fixture with no registered schedule yet is legitimate (Axiom 3).
final class RoundFixtureCardDto {
  /// Creates a round-fixture card DTO.
  const RoundFixtureCardDto({
    required this.roundId,
    required this.fixtureId,
    required this.displayOrder,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory RoundFixtureCardDto.fromJson(Map<String, Object?> json) {
    return RoundFixtureCardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      roundId: json['round_id']! as String,
      fixtureId: json['fixture_id']! as String,
      displayOrder: json['display_order']! as int,
      homeTeam: json['home_team'] as String?,
      awayTeam: json['away_team'] as String?,
      kickoffAt: json['kickoff_at'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning round id (UUID string).
  final String roundId;

  /// The referenced fixture id (UUID string).
  final String fixtureId;

  /// The 0-based presentation order within the round.
  final int displayOrder;

  /// The home side's team name, or `null` if not yet scheduled.
  final String? homeTeam;

  /// The away side's team name, or `null` if not yet scheduled.
  final String? awayTeam;

  /// The kickoff time as an ISO 8601 UTC timestamp string, or `null` if not
  /// yet scheduled.
  final String? kickoffAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round_id': roundId,
    'fixture_id': fixtureId,
    'display_order': displayOrder,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundFixtureCardDto &&
      other.roundId == roundId &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    roundId,
    fixtureId,
    displayOrder,
    homeTeam,
    awayTeam,
    kickoffAt,
    schemaVersion,
  );
}

/// The request body of `POST /seasons/{id}/rounds` (command intent
/// `OpenRound`, admin-only). The season id travels in the path, never here.
final class OpenRoundRequestDto {
  /// Creates an open-round request body.
  const OpenRoundRequestDto({
    required this.sequence,
    required this.predictionDeadline,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map. A missing field surfaces as an explicit
  /// `null` so the use-case reports the validation failure rather than
  /// throwing at parse time.
  factory OpenRoundRequestDto.fromJson(Map<String, Object?> json) {
    return OpenRoundRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      sequence: json['sequence'] as int?,
      predictionDeadline: json['prediction_deadline'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The 1-based ordinal of the round within its season.
  final int? sequence;

  /// The prediction deadline as an ISO 8601 timestamp string.
  final String? predictionDeadline;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'sequence': sequence,
    'prediction_deadline': predictionDeadline,
  };

  @override
  bool operator ==(Object other) =>
      other is OpenRoundRequestDto &&
      other.sequence == sequence &&
      other.predictionDeadline == predictionDeadline &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(sequence, predictionDeadline, schemaVersion);
}

/// The request body of `POST /rounds/{id}/fixtures` (command intent
/// `LinkFixtureToRound`, admin-only). The round id travels in the path.
final class LinkFixtureToRoundRequestDto {
  /// Creates a link-fixture-to-round request body.
  const LinkFixtureToRoundRequestDto({
    required this.fixtureId,
    required this.displayOrder,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory LinkFixtureToRoundRequestDto.fromJson(Map<String, Object?> json) {
    return LinkFixtureToRoundRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id'] as String?,
      displayOrder: json['display_order'] as int?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture id to link (UUID string).
  final String? fixtureId;

  /// The 0-based presentation order within the round.
  final int? displayOrder;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'display_order': displayOrder,
  };

  @override
  bool operator ==(Object other) =>
      other is LinkFixtureToRoundRequestDto &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(fixtureId, displayOrder, schemaVersion);
}
NUKHBAA_EOF

# 2) packages/api_client — openRound / linkFixtureToRound
cat > packages/api_client/lib/src/competition_api.dart << 'NUKHBAA_EOF'
import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Competition browse surface of `apps/server`.
///
/// Wraps exactly the read routes that exist today, verbatim — no invented path.
/// The four hops of the browse navigation competition -> season -> round ->
/// fixtures are all reachable now that the FA-1 season/round scope closure
/// (2026-07-13) added the two middle-hop GET branches:
///   * `GET /competitions`               -> `List<CompetitionDto>`
///     (`routes/competitions/index.dart` GET branch, public catalogue)
///   * `GET /competitions/{id}`          -> [CompetitionDto]
///     (`routes/competitions/[id]/index.dart`; `404 competition.not_found`)
///   * `GET /competitions/{id}/seasons`  -> `List<SeasonDto>`
///     (`routes/competitions/[id]/seasons/index.dart` GET branch, label order;
///     an absent competition is a legitimate empty array — no existence oracle)
///   * `GET /seasons/{id}/rounds`        -> `List<RoundDto>`
///     (`routes/seasons/[id]/rounds/index.dart` GET branch, sequence order;
///     an absent season is a legitimate empty array — no existence oracle)
///   * `GET /rounds/{id}`                -> [RoundDto]
///     (`routes/rounds/[id]/index.dart`; `404 competition.round_not_found`)
///   * `GET /rounds/{id}/fixtures`       -> `List<RoundFixtureCardDto>`
///     (`routes/rounds/[id]/fixtures/index.dart` GET branch, display order,
///     each card enriched with its schedule identity — team names + kickoff,
///     all nullable since the round<->fixture link never verifies a schedule
///     exists, Axiom 3; query intent `BrowseRoundFixtures`, Session decision
///     2026-08-07 widened this read instead of a new endpoint; an absent round
///     is a legitimate empty array — no existence oracle)
///
/// All routes are behind `bearerAuth`. The browse reads above are pure (no
/// side effect); [openRound] and [linkFixtureToRound] below are admin-only
/// commands (authorization enforced server-side inside the use-case, never
/// by this client). Every method returns a typed [Result] and never throws.
final class CompetitionApi {
  /// Creates the Competition client over the shared [ApiTransport].
  const CompetitionApi(this._transport);

  final ApiTransport _transport;

  /// `GET /competitions` — the browsable public competition catalogue.
  ///
  /// An empty catalogue is a legitimate `Ok(<empty list>)`, never an error.
  Future<Result<List<CompetitionDto>>> listCompetitions() {
    return _transport.getList<CompetitionDto>(
      '/competitions',
      parseElement: CompetitionDto.fromJson,
    );
  }

  /// `GET /competitions/{id}` — a single competition.
  ///
  /// A missing competition is `Err(invariant, code: competition.not_found)`
  /// (the server returns a true `404` with that stable code); a malformed id is
  /// `Err(validation)`.
  Future<Result<CompetitionDto>> getCompetition(String competitionId) {
    return _transport.getObject<CompetitionDto>(
      '/competitions/$competitionId',
      parse: CompetitionDto.fromJson,
    );
  }

  /// `GET /competitions/{id}/seasons` — the competition's seasons, label order.
  ///
  /// The first middle hop of the browse navigation. A competition with no
  /// seasons — or one that does not exist — is a legitimate `Ok(<empty list>)`
  /// (the server reveals no existence oracle on this browse read).
  Future<Result<List<SeasonDto>>> listCompetitionSeasons(String competitionId) {
    return _transport.getList<SeasonDto>(
      '/competitions/$competitionId/seasons',
      parseElement: SeasonDto.fromJson,
    );
  }

  /// `GET /seasons/{id}/rounds` — the season's rounds, 1-based sequence order.
  ///
  /// The second middle hop of the browse navigation. A season with no rounds —
  /// or one that does not exist — is a legitimate `Ok(<empty list>)` (no
  /// existence oracle). Each [RoundDto] exposes only the ruleset *version*,
  /// never the opaque frozen snapshot.
  Future<Result<List<RoundDto>>> listSeasonRounds(String seasonId) {
    return _transport.getList<RoundDto>(
      '/seasons/$seasonId/rounds',
      parseElement: RoundDto.fromJson,
    );
  }

  /// `GET /rounds/{id}` — a single round (status + deadline + ruleset version).
  ///
  /// A missing round is `Err(invariant, code: competition.round_not_found)`
  /// (true `404`); a malformed id is `Err(validation)`. The opaque frozen
  /// ruleset snapshot is never exposed — only [RoundDto.rulesetVersion].
  Future<Result<RoundDto>> getRound(String roundId) {
    return _transport.getObject<RoundDto>(
      '/rounds/$roundId',
      parse: RoundDto.fromJson,
    );
  }

  /// `GET /rounds/{id}/fixtures` — the round's fixtures in display order,
  /// each enriched with its schedule identity (team names + kickoff) for the
  /// prediction-form render (query intent `BrowseRoundFixtures`; Session
  /// decision 2026-08-07 widened this read instead of a new per-fixture
  /// endpoint — batched, no N+1).
  ///
  /// A round with no linked fixtures — or one that does not exist — is a
  /// legitimate `Ok(<empty list>)` (the server reveals no existence oracle on
  /// this browse read). `homeTeam`/`awayTeam`/`kickoffAt` are `null` when the
  /// linked fixture has no schedule yet (the link never verifies one exists —
  /// Axiom 3).
  Future<Result<List<RoundFixtureCardDto>>> browseRoundFixtures(
    String roundId,
  ) {
    return _transport.getList<RoundFixtureCardDto>(
      '/rounds/$roundId/fixtures',
      parseElement: RoundFixtureCardDto.fromJson,
    );
  }

  /// `POST /seasons/{id}/rounds` — opens a new round in the season, freezing
  /// the ruleset (command intent `OpenRound`). Admin-only, enforced inside the
  /// server use-case. [predictionDeadline] must be an ISO 8601 timestamp
  /// string; the server normalizes it to UTC.
  Future<Result<RoundDto>> openRound({
    required String seasonId,
    required int sequence,
    required String predictionDeadline,
  }) {
    return _transport.postObject<RoundDto>(
      '/seasons/$seasonId/rounds',
      body: OpenRoundRequestDto(
        sequence: sequence,
        predictionDeadline: predictionDeadline,
      ).toJson(),
      parse: RoundDto.fromJson,
    );
  }

  /// `POST /rounds/{id}/fixtures` — links an already-registered fixture into
  /// the round at [displayOrder] (command intent `LinkFixtureToRound`; Axiom
  /// 3: the only place Competition names a fixture). Admin-only, enforced
  /// inside the server use-case.
  Future<Result<RoundFixtureDto>> linkFixtureToRound({
    required String roundId,
    required String fixtureId,
    required int displayOrder,
  }) {
    return _transport.postObject<RoundFixtureDto>(
      '/rounds/$roundId/fixtures',
      body: LinkFixtureToRoundRequestDto(
        fixtureId: fixtureId,
        displayOrder: displayOrder,
      ).toJson(),
      parse: RoundFixtureDto.fromJson,
    );
  }
}
NUKHBAA_EOF

# 3) apps/mobile core providers doc comment
cat > apps/mobile/lib/core/providers.dart << 'NUKHBAA_EOF'
/// Application-wide dependency providers (the composition seam for `apps/mobile`).
///
/// This file is the client's small equivalent of the server's `CompositionRoot`:
/// it constructs the ratified `api_client` transport + domain clients and the
/// platform `TokenStore`, and exposes them as Riverpod providers so feature
/// state (the session controller, and later Competition/Prediction/Leaderboard
/// controllers) can depend on them without knowing how they are built.
///
/// It performs NO HTTP and holds NO business logic — it only wires
/// already-built collaborators (Flutter App phase constraint / ADR-002 §2.8):
///   * [AppConfig] from compile-time environment (base API URL);
///   * the one `http.Client` (via `createHttpClient`, the sole `package:http`
///     touch-point in the app);
///   * [TokenStore] — `SecureTokenStore` in production; overridable with an
///     `InMemoryTokenStore` in tests via a ProviderScope override;
///   * an [ApiTransport] whose [TokenProvider] reads the current token from the
///     [TokenStore], so every `api_client` call is authenticated transparently;
///   * the typed domain clients ([AuthApi], [CompetitionApi], [PredictionApi],
///     [LeaderboardsApi]).
library;

import 'package:api_client/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'config/app_config.dart';
import 'auth/token_store.dart';
import 'network/http_client.dart';

part 'providers.g.dart';

/// The immutable runtime configuration, resolved once from the environment.
///
/// Overridden in tests (and in a custom bootstrap) by supplying a different
/// [AppConfig] through a `ProviderScope` override.
@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) => AppConfig.fromEnvironment();

/// The platform-secure token store — the single owner of *where* the access
/// token lives on the client. Production wiring uses `flutter_secure_storage`;
/// tests override this provider with an [InMemoryTokenStore].
@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) =>
    const SecureTokenStore(FlutterSecureStorage());

/// The one shared [ApiTransport]. It owns the app's single `http.Client`
/// (closed when this provider is disposed) and reads the bearer token from the
/// [TokenStore] on every request via its [TokenProvider] — the app never
/// attaches a token by hand.
@Riverpod(keepAlive: true)
ApiTransport apiTransport(Ref ref) {
  final config = ref.watch(appConfigProvider);
  final store = ref.watch(tokenStoreProvider);
  final client = createHttpClient();
  ref.onDispose(client.close);
  return ApiTransport(
    baseUri: config.apiBaseUrl,
    httpClient: client,
    tokenProvider: store.read,
    onUnauthorized: () async {
      await store.clear();
      ref.read(sessionExpiryProvider.notifier).signal();
    },
  );
}

@Riverpod(keepAlive: true)
class SessionExpiry extends _$SessionExpiry {
  @override
  int build() => 0;

  void signal() => state = state + 1;
}

/// The typed Auth (identity) client over the shared transport.
@Riverpod(keepAlive: true)
AuthApi authApi(Ref ref) => AuthApi(ref.watch(apiTransportProvider));

/// The typed Competition (browse + round administration) client over the
/// shared transport.
///
/// Consumed read-only by the Competition browse feature (competition -> season
/// -> round -> fixtures) and by the Admin round-administration controllers
/// (open a round, link a fixture into it — server-enforced admin-only). Like
/// [authApi], it holds no state and performs no HTTP of its own — it
/// delegates every call to the shared [ApiTransport].
@Riverpod(keepAlive: true)
CompetitionApi competitionApi(Ref ref) =>
    CompetitionApi(ref.watch(apiTransportProvider));

/// The typed Prediction (submit) client over the shared transport.
///
/// Consumed by the Prediction feature (read the caller's own prediction for a
/// round, and submit/amend it). Like [authApi]/[competitionApi] it holds no
/// state and performs no HTTP of its own — it delegates every call to the
/// shared [ApiTransport], which attaches the bearer token. This is the ONLY
/// prediction write path the client has; there is no direct Supabase write
/// (ADR-002 §2.2/§2.8) — every submission goes through the server use-case API.
@Riverpod(keepAlive: true)
PredictionApi predictionApi(Ref ref) =>
    PredictionApi(ref.watch(apiTransportProvider));

/// The typed Leaderboards (view) client over the shared transport.
///
/// Consumed read-only by the Leaderboards feature (a season's ranked
/// standings). Like [authApi]/[competitionApi]/[predictionApi] it holds no
/// state and performs no HTTP of its own — it delegates the one leaderboard
/// read (`GET /seasons/{id}/leaderboard`) to the shared [ApiTransport], which
/// attaches the bearer token. A leaderboard is a read-only projection over the
/// append-only ledger (Axiom 5): the server computes every rank and total; the
/// client never submits or computes a point value, so this client is
/// query-only.
@Riverpod(keepAlive: true)
LeaderboardsApi leaderboardsApi(Ref ref) =>
    LeaderboardsApi(ref.watch(apiTransportProvider));

/// The typed Ledger (personal balance + points history) client over the
/// shared transport.
///
/// Consumed by the Ledger feature (a participant's own balance and entry
/// stream). Like the other domain clients it holds no state and performs no
/// HTTP of its own — it delegates every read to the shared [ApiTransport].
/// The ledger is a read-only projection over the append-only points stream
/// (Axiom 5); there is no write method here.
@Riverpod(keepAlive: true)
LedgerApi ledgerApi(Ref ref) => LedgerApi(ref.watch(apiTransportProvider));

/// The typed Notifications (own inbox) client over the shared transport.
///
/// Consumed by the Notifications feature (list, unread count, mark-read).
/// Recipient-only (Notifications decision #4): every gate lives server-side,
/// bound to the verified token, never a value this client supplies.
@Riverpod(keepAlive: true)
NotificationsApi notificationsApi(Ref ref) =>
    NotificationsApi(ref.watch(apiTransportProvider));

/// The typed Groups client over the shared transport.
///
/// Consumed by the Groups feature (create/join/read/members/leaderboard/feed).
/// Member-only visibility for every read; the create/join commands bind the
/// caller from the verified token server-side.
@Riverpod(keepAlive: true)
GroupsApi groupsApi(Ref ref) => GroupsApi(ref.watch(apiTransportProvider));

/// The typed Admin Panel client over the shared transport.
///
/// Consumed by the Admin feature (audit log, user sanctions, support-read of a
/// participant's ledger). Admin-only, enforced entirely server-side; this
/// client never decides who may call it.
@Riverpod(keepAlive: true)
AdminApi adminApi(Ref ref) => AdminApi(ref.watch(apiTransportProvider));

/// The typed Fixture Schedule (identity) client over the shared transport.
///
/// Consumed by the Admin feature to register/correct a fixture's identity —
/// home team, away team, kickoff time (the fixture-IDENTITY seam, Axiom 3;
/// Next-Task decision 2026-07-11, option (a)). Admin-only, enforced entirely
/// server-side inside `RegisterFixtureSchedule`/`CorrectFixtureSchedule`; this
/// client never decides who may call it.
@Riverpod(keepAlive: true)
FixtureScheduleApi fixtureScheduleApi(Ref ref) =>
    FixtureScheduleApi(ref.watch(apiTransportProvider));
NUKHBAA_EOF

# 4) l10n source (ar/en)
cat > apps/mobile/lib/l10n/app_ar.arb << 'NUKHBAA_EOF'
{
  "@@locale": "ar",
  "appTitle": "نُخبة",
  "signIn": "تسجيل الدخول",
  "signOut": "تسجيل الخروج",
  "loading": "جارٍ التحميل…",
  "error": "حدث خطأ ما",
  "retry": "إعادة المحاولة",
  "showPassword": "إظهار كلمة المرور",
  "hidePassword": "إخفاء كلمة المرور",
  "markNotificationRead": "تعليم كمقروءة",
  "createAccount": "إنشاء حساب",
  "signInSubtitle": "سجّل الدخول بالبريد الإلكتروني وكلمة المرور للمتابعة.",
  "signUpSubtitle": "أنشئ حساباً لتبدأ اللعب في نُخبة.",
  "email": "البريد الإلكتروني",
  "emailHint": "you@example.com",
  "emailRequired": "الرجاء إدخال بريدك الإلكتروني.",
  "password": "كلمة المرور",
  "passwordRequired": "الرجاء إدخال كلمة المرور.",
  "toggleToSignIn": "لديك حساب بالفعل؟ سجّل الدخول",
  "toggleToRegister": "جديد هنا؟ أنشئ حساباً",
  "tagline": "منصة توقعات كرة القدم",
  "authTabSignIn": "دخول",
  "authTabRegister": "تسجيل",
  "confirmPassword": "تأكيد كلمة المرور",
  "confirmPasswordRequired": "الرجاء تأكيد كلمة المرور.",
  "passwordMismatch": "كلمتا المرور غير متطابقتين.",
  "rulesTitle": "كيف تلعب؟",
  "rulesTagline": "توقع، نافس، تصدّر، كن من النخبة",
  "rulesPredictMajorLeagues": "توقع مباريات الدوريات الكبرى",
  "rulesCorrectPrediction": "التوقع الصحيح: 3 نقاط",
  "rulesWrongPrediction": "التوقع الخاطئ: 0 نقطة",
  "rulesDoubleMatch": "المباراة المختارة كدبل: 6 نقاط",
  "notifications": "الإشعارات",
  "signedIn": "تم تسجيل الدخول",
  "userId": "معرّف المستخدم",
  "role": "الدور",
  "status": "الحالة",
  "browseCompetitions": "تصفح البطولات",
  "hallOfFame": "قاعة المشاهير",
  "myPredictions": "توقعاتي",
  "createGroup": "إنشاء مجموعة",
  "joinGroup": "الانضمام إلى مجموعة",
  "adminDashboard": "لوحة تحكم المشرف",
  "hallOfFameEmpty": "لم يحصل أحد على أي نقاط بعد.",
  "hallOfFameSeasonsPlayed": "{count, plural, zero{لم يشارك في أي موسم} one{شارك في موسم واحد} two{شارك في موسمين} few{شارك في {count} مواسم} many{شارك في {count} موسمًا} other{شارك في {count} موسم}}",
  "competitionSeasonsEmpty": "لا توجد مواسم لهذه البطولة بعد.",
  "leaderboardTitle": "{label} — لوحة الصدارة",
  "seasonLeaderboardEmpty": "لم ينضم أحد لهذا الموسم بعد.",
  "leaderboardEntriesCounted": "{count, plural, zero{لا توجد مشاركات محتسبة} one{مشاركة واحدة محتسبة} two{مشاركتان محتسبتان} few{{count} مشاركات محتسبة} many{{count} مشاركة محتسبة} other{{count} مشاركة محتسبة}}",
  "pointsAbbreviated": "{count, plural, zero{0 نقطة} one{نقطة واحدة} two{نقطتان} few{{count} نقاط} many{{count} نقطة} other{{count} نقطة}}",
  "groupLeaderboardEmpty": "لم ينضم أي عضو من هذه المجموعة للموسم بعد.",
  "competitions": "المسابقات",
  "competitionsEmpty": "لا توجد مسابقات للتصفح حتى الآن.",
  "visibilityPublic": "عام",
  "visibilityPrivate": "خاص",
  "predictionHistoryEmpty": "لم تقدّم أي توقعات بعد.",
  "predictionHistoryScoreLine": "{fixtureId}: {homeGoals} - {awayGoals}",
  "groupFeedTitle": "نشاط {groupName}",
  "groupFeedEmpty": "لا يوجد نشاط بعد.",
  "activityRoundScored": "تم احتساب نتيجة الجولة",
  "activityMemberJoined": "انضم عضو جديد",
  "activityRankShift": "انتقل من المركز #{oldRank} إلى #{newRank}",
  "activityRankShiftUnknown": "تغيّر الترتيب",
  "seasonRoundsTitle": "{seasonLabel} — الجولات",
  "viewLeaderboardTooltip": "عرض لوحة الصدارة",
  "seasonRoundsEmpty": "لا توجد جولات لهذا الموسم بعد.",
  "roundItemTitle": "الجولة {sequence}",
  "roundDeadlineLine": "{statusLabel} · الموعد النهائي {deadline}",
  "roundStatusOpen": "مفتوحة للتوقعات",
  "roundStatusLocked": "مغلقة",
  "roundStatusScored": "محتسبة",
  "roundFixturesTitle": "الجولة",
  "roundRulesLine": "{statusLabel} · القواعد إصدار {rulesetVersion}",
  "predictRoundButton": "توقع نتائج هذه الجولة",
  "roundFixturesEmpty": "لا توجد مباريات لهذه الجولة بعد.",
  "fixtureItemTitle": "المباراة {fixtureId}",
  "fixtureVsTitle": "{home} ضد {away}",
  "predictionTitle": "التوقّع",
  "predictionClosedMessage": "هذه الجولة {status}. التوقعات مغلقة.",
  "genericErrorMessage": "حدث خطأ ما. يُرجى المحاولة مرة أخرى.",
  "tryAgainButton": "حاول مرة أخرى",
  "predictionAlreadySubmitted": "لقد أرسلت توقعاً لهذه الجولة مسبقاً. التعديل والإرسال مرة أخرى سيحدّثه.",
  "predictionSaved": "تم حفظ توقعك.",
  "submitPredictionButton": "إرسال التوقع",
  "predictionDoubleLabel": "الدبل",
  "predictionFixtureLockedLabel": "بدأت المباراة",
  "predictionDoubleHint": "اختر مباراة واحدة كدبل قبل الإرسال.",
  "predictionIncompleteHint": "أدخل نتيجة كل مباراة مفتوحة قبل الإرسال.",
  "predictionNoOpenFixturesMessage": "كل مباريات هذه الجولة بدأت بالفعل. لا يوجد ما يمكن توقّعه الآن.",
  "adminAuditLogTab": "سجل التدقيق",
  "adminUsersTab": "المستخدمون",
  "adminLedgerLookupTab": "البحث في السجل المالي",
  "adminAuditLogEmpty": "لا توجد إدخالات تدقيق بعد.",
  "adminReasonMandatoryLabel": "السبب (إلزامي)",
  "adminSuspendButton": "تعليق",
  "adminReinstateButton": "إعادة تفعيل",
  "adminParticipantIdLabel": "معرّف المشارك",
  "adminLookUpButton": "بحث",
  "adminFixturesTab": "هوية المباراة",
  "adminFixtureIdOptionalLabel": "معرّف المباراة (للتصحيح فقط، اتركه فارغاً للتسجيل)",
  "adminHomeTeamLabel": "الفريق المضيف",
  "adminAwayTeamLabel": "الفريق الضيف",
  "adminPickKickoffButton": "اختر موعد المباراة",
  "adminRegisterFixtureButton": "تسجيل مباراة جديدة",
  "adminCorrectFixtureButton": "تصحيح المباراة",
  "adminRoundsTab": "الجولات",
  "adminOpenRoundSectionTitle": "فتح جولة جديدة",
  "adminSeasonIdLabel": "معرّف الموسم",
  "adminSequenceLabel": "رقم الجولة",
  "adminPickDeadlineButton": "اختر موعد إغلاق التوقعات",
  "adminOpenRoundButton": "فتح الجولة",
  "adminLinkFixtureSectionTitle": "ربط مباراة بجولة",
  "adminRoundIdLabel": "معرّف الجولة",
  "adminFixtureIdLabel": "معرّف المباراة",
  "adminDisplayOrderLabel": "ترتيب العرض",
  "adminLinkFixtureButton": "ربط المباراة بالجولة",
  "createGroupTitle": "إنشاء مجموعة",
  "groupNameLabel": "اسم المجموعة",
  "createGroupButton": "إنشاء",
  "joinGroupTitle": "الانضمام إلى مجموعة",
  "inviteCodeLabel": "رمز الدعوة",
  "joinGroupButton": "انضمام",
  "ledgerTitle": "نقاطي",
  "ledgerEmpty": "لا توجد حركات نقاط بعد.",
  "ledgerEntryCount": "{count} حركة مسجّلة",
  "@ledgerEntryCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "notificationsTitle": "الإشعارات",
  "notificationsEmpty": "ليس لديك أي إشعارات بعد.",
  "notificationRoundScored": "تم تسجيل نتيجة جولة توقعتها",
  "notificationGroupMemberJoined": "انضم شخص إلى مجموعتك",
  "notificationReactionReceived": "تلقيت تفاعلاً",
  "notificationsMarkAsRead": "تمييز كمقروء"
}
NUKHBAA_EOF

cat > apps/mobile/lib/l10n/app_en.arb << 'NUKHBAA_EOF'
{
  "@@locale": "en",
  "appTitle": "Nukhba",
  "@appTitle": {
    "description": "Application title"
  },
  "signIn": "Sign in",
  "signOut": "Sign out",
  "loading": "Loading…",
  "error": "Something went wrong",
  "retry": "Retry",
  "showPassword": "Show password",
  "hidePassword": "Hide password",
  "markNotificationRead": "Mark as read",
  "createAccount": "Create account",
  "signInSubtitle": "Sign in with your email and password to continue.",
  "signUpSubtitle": "Create an account to start playing Nukhba.",
  "email": "Email",
  "emailHint": "you@example.com",
  "emailRequired": "Please enter your email.",
  "password": "Password",
  "passwordRequired": "Please enter your password.",
  "toggleToSignIn": "Already have an account? Sign in",
  "toggleToRegister": "New here? Create an account",
  "tagline": "Football prediction platform",
  "authTabSignIn": "Sign in",
  "authTabRegister": "Register",
  "confirmPassword": "Confirm password",
  "confirmPasswordRequired": "Please confirm your password.",
  "passwordMismatch": "Passwords do not match.",
  "rulesTitle": "How to play?",
  "rulesTagline": "Predict, compete, top the table, be Nukhba.",
  "rulesPredictMajorLeagues": "Predict matches from the major leagues",
  "rulesCorrectPrediction": "Correct prediction: 3 points",
  "rulesWrongPrediction": "Wrong prediction: 0 points",
  "rulesDoubleMatch": "Match picked as double: 6 points",
  "notifications": "Notifications",
  "signedIn": "Signed in",
  "userId": "User ID",
  "role": "Role",
  "status": "Status",
  "browseCompetitions": "Browse competitions",
  "hallOfFame": "Hall of Fame",
  "myPredictions": "My Predictions",
  "createGroup": "Create a group",
  "joinGroup": "Join a group",
  "adminDashboard": "Admin dashboard",
  "hallOfFameEmpty": "Nobody has earned any points yet.",
  "hallOfFameSeasonsPlayed": "{count, plural, =0{No seasons played} =1{1 season played} other{{count} seasons played}}",
  "@hallOfFameSeasonsPlayed": {
    "description": "Number of seasons a user has played, shown on the Hall of Fame leaderboard row.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "competitionSeasonsEmpty": "This competition has no seasons yet.",
  "leaderboardTitle": "{label} — Leaderboard",
  "@leaderboardTitle": {
    "description": "Title of the season leaderboard screen.",
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "seasonLeaderboardEmpty": "No one has joined this season yet.",
  "leaderboardEntriesCounted": "{count, plural, =0{No entries counted} =1{1 entry counted} other{{count} entries counted}}",
  "@leaderboardEntriesCounted": {
    "description": "Number of prediction entries counted toward a participant's leaderboard score.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "pointsAbbreviated": "{count, plural, =0{0 pts} =1{1 pt} other{{count} pts}}",
  "@pointsAbbreviated": {
    "description": "Abbreviated points total, shown on leaderboard rows (e.g. Hall of Fame, season leaderboard).",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "groupLeaderboardEmpty": "No members of this group have joined the season yet.",
  "competitions": "Competitions",
  "competitionsEmpty": "There are no competitions to browse yet.",
  "visibilityPublic": "Public",
  "visibilityPrivate": "Private",
  "predictionHistoryEmpty": "You have not submitted any predictions yet.",
  "predictionHistoryScoreLine": "{fixtureId}: {homeGoals} - {awayGoals}",
  "@predictionHistoryScoreLine": {
    "description": "One fixture's predicted scoreline within a submitted prediction history row.",
    "placeholders": {
      "fixtureId": {
        "type": "String"
      },
      "homeGoals": {
        "type": "int"
      },
      "awayGoals": {
        "type": "int"
      }
    }
  },
  "groupFeedTitle": "{groupName} Feed",
  "@groupFeedTitle": {
    "description": "App bar title for a group's activity feed screen.",
    "placeholders": {
      "groupName": {
        "type": "String"
      }
    }
  },
  "groupFeedEmpty": "No activity yet.",
  "activityRoundScored": "Round scored",
  "activityMemberJoined": "New member joined",
  "activityRankShift": "Moved from #{oldRank} to #{newRank}",
  "@activityRankShift": {
    "description": "Describes a member's rank change in the group activity feed.",
    "placeholders": {
      "oldRank": {
        "type": "int"
      },
      "newRank": {
        "type": "int"
      }
    }
  },
  "activityRankShiftUnknown": "Rank changed",
  "seasonRoundsTitle": "{seasonLabel} — Rounds",
  "@seasonRoundsTitle": {
    "description": "App bar title for the season rounds browse screen.",
    "placeholders": {
      "seasonLabel": {
        "type": "String"
      }
    }
  },
  "viewLeaderboardTooltip": "View leaderboard",
  "@viewLeaderboardTooltip": {
    "description": "Tooltip for the app bar action that navigates to the season leaderboard."
  },
  "seasonRoundsEmpty": "This season has no rounds yet.",
  "@seasonRoundsEmpty": {
    "description": "Empty state message when a season has no rounds."
  },
  "roundItemTitle": "Round {sequence}",
  "@roundItemTitle": {
    "description": "Title of a round list item, showing its 1-based sequence number.",
    "placeholders": {
      "sequence": {
        "type": "int"
      }
    }
  },
  "roundDeadlineLine": "{statusLabel} · Deadline {deadline}",
  "@roundDeadlineLine": {
    "description": "Subtitle of a round list item combining its humanised status and formatted prediction deadline.",
    "placeholders": {
      "statusLabel": {
        "type": "String"
      },
      "deadline": {
        "type": "String"
      }
    }
  },
  "roundStatusOpen": "Open for predictions",
  "@roundStatusOpen": {
    "description": "Humanised label for a round in the open lifecycle status."
  },
  "roundStatusLocked": "Locked",
  "@roundStatusLocked": {
    "description": "Humanised label for a round in the locked lifecycle status."
  },
  "roundStatusScored": "Scored",
  "@roundStatusScored": {
    "description": "Humanised label for a round in the scored lifecycle status."
  },
  "roundFixturesTitle": "Round",
  "roundRulesLine": "{statusLabel} · Rules v{rulesetVersion}",
  "@roundRulesLine": {
    "description": "Round header status line combining the humanised status and the ruleset version applied to this round.",
    "placeholders": {
      "statusLabel": {
        "type": "String"
      },
      "rulesetVersion": {
        "type": "int"
      }
    }
  },
  "predictRoundButton": "Predict this round",
  "roundFixturesEmpty": "This round has no fixtures yet.",
  "fixtureItemTitle": "Fixture {fixtureId}",
  "@fixtureItemTitle": {
    "description": "Title of a fixture list item, showing its stable fixture id.",
    "placeholders": {
      "fixtureId": {
        "type": "String"
      }
    }
  },
  "fixtureVsTitle": "{home} vs {away}",
  "@fixtureVsTitle": {
    "description": "Title of a fixture list item when its schedule identity is known.",
    "placeholders": {
      "home": {
        "type": "String"
      },
      "away": {
        "type": "String"
      }
    }
  },
  "predictionTitle": "Predict",
  "@predictionTitle": {
    "description": "App bar title on the prediction submit/amend screen."
  },
  "predictionClosedMessage": "This round is {status}. Predictions are closed.",
  "@predictionClosedMessage": {
    "description": "Shown when a round is not open for predictions; status is the lowercase lifecycle label.",
    "placeholders": {
      "status": {
        "type": "String"
      }
    }
  },
  "genericErrorMessage": "Something went wrong. Please try again.",
  "@genericErrorMessage": {
    "description": "Fallback error message for an untyped/unexpected client error."
  },
  "tryAgainButton": "Try again",
  "@tryAgainButton": {
    "description": "Retry button label on a form error state."
  },
  "predictionAlreadySubmitted": "You have already submitted a prediction for this round. Editing and submitting again will update it.",
  "@predictionAlreadySubmitted": {
    "description": "Banner shown when the caller already has a stored prediction for this round."
  },
  "predictionSaved": "Your prediction was saved.",
  "@predictionSaved": {
    "description": "Success banner after a prediction submit/amend succeeds."
  },
  "submitPredictionButton": "Submit prediction",
  "@submitPredictionButton": {
    "description": "Label on the prediction submit button."
  },
  "predictionDoubleLabel": "Double",
  "@predictionDoubleLabel": {
    "description": "Tooltip/semantic label on the per-fixture double-selection star."
  },
  "predictionFixtureLockedLabel": "Started",
  "@predictionFixtureLockedLabel": {
    "description": "Small label under a fixture that has already kicked off and can no longer be edited."
  },
  "predictionDoubleHint": "Select exactly one open fixture as your double before submitting.",
  "@predictionDoubleHint": {
    "description": "Shown when every open fixture has a score but no double is selected yet."
  },
  "predictionIncompleteHint": "Enter a score for every open fixture before submitting.",
  "@predictionIncompleteHint": {
    "description": "Shown while at least one open fixture is missing a valid score."
  },
  "predictionNoOpenFixturesMessage": "Every fixture in this round has already kicked off. There is nothing left to predict.",
  "@predictionNoOpenFixturesMessage": {
    "description": "Shown instead of the form when every fixture in the round has already locked."
  },
  "adminAuditLogTab": "Audit Log",
  "adminUsersTab": "Users",
  "adminLedgerLookupTab": "Ledger Lookup",
  "adminAuditLogEmpty": "No audit entries yet.",
  "adminReasonMandatoryLabel": "Reason (mandatory)",
  "adminSuspendButton": "Suspend",
  "adminReinstateButton": "Reinstate",
  "adminParticipantIdLabel": "Participant ID",
  "adminLookUpButton": "Look up",
  "adminFixturesTab": "Fixture Identity",
  "adminFixtureIdOptionalLabel": "Fixture ID (correction only — leave empty to register)",
  "adminHomeTeamLabel": "Home team",
  "adminAwayTeamLabel": "Away team",
  "adminPickKickoffButton": "Pick kickoff time",
  "adminRegisterFixtureButton": "Register fixture",
  "adminCorrectFixtureButton": "Correct fixture",
  "adminRoundsTab": "Rounds",
  "adminOpenRoundSectionTitle": "Open a new round",
  "adminSeasonIdLabel": "Season ID",
  "adminSequenceLabel": "Round sequence",
  "adminPickDeadlineButton": "Pick prediction deadline",
  "adminOpenRoundButton": "Open round",
  "adminLinkFixtureSectionTitle": "Link a fixture to a round",
  "adminRoundIdLabel": "Round ID",
  "adminFixtureIdLabel": "Fixture ID",
  "adminDisplayOrderLabel": "Display order",
  "adminLinkFixtureButton": "Link fixture to round",
  "createGroupTitle": "Create Group",
  "groupNameLabel": "Group name",
  "createGroupButton": "Create",
  "joinGroupTitle": "Join Group",
  "inviteCodeLabel": "Invite code",
  "joinGroupButton": "Join",
  "ledgerTitle": "My Points",
  "ledgerEmpty": "No points movements yet.",
  "ledgerEntryCount": "{count} movements counted",
  "@ledgerEntryCount": {
    "description": "Count of point movements shown below the balance on the ledger screen.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "notificationsTitle": "Notifications",
  "notificationsEmpty": "You have no notifications yet.",
  "notificationRoundScored": "A round you predicted was scored",
  "notificationGroupMemberJoined": "Someone joined your group",
  "notificationReactionReceived": "You received a reaction",
  "notificationsMarkAsRead": "Mark as read"
}
NUKHBAA_EOF

echo "Part 1 (contracts + api_client + l10n source) written."
