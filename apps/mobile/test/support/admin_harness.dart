/// Test harness for the Admin Panel slice.
///
/// Mirrors `prediction_harness.dart`: it builds a `ProviderScope` whose
/// networking is served entirely by a `package:http/testing.dart` [MockClient]
/// (no live socket), wiring the shared `apiTransportProvider` over that client
/// so the real `adminApiProvider`, `fixtureScheduleApiProvider`, and
/// `competitionApiProvider` (the screen's five controllers/reads) exercise the
/// genuine `api_client` end-to-end — only the socket is faked. The token store
/// is a seedable in-memory fake so the transport still attaches a bearer token
/// exactly as production does.
///
/// A test supplies a [handler] that returns a canned response per request (or
/// throws to simulate a transport failure). Because the Admin dashboard issues
/// several distinct reads/writes (`GET /admin/audit`,
/// `POST /admin/users/{id}/suspend`, `POST /admin/users/{id}/reinstate`,
/// `GET /admin/participants/{id}/ledger`, `POST /fixtures`,
/// `PUT /fixtures/{id}`, `POST /seasons/{id}/rounds`,
/// `POST /rounds/{id}/fixtures`), the handler is expected to branch on
/// `request.method` + `request.url.path`. Response builders
/// ([okJsonObject]/[errorEnvelope]) and DTO fixtures are provided.
library;

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/token_store.dart';
import 'package:mobile/core/providers.dart';

/// One captured outbound request (for asserting method + path + body).
final class CapturedRequest {
  /// Wraps a captured [http.Request].
  CapturedRequest(this.request);

  /// The raw captured request.
  final http.Request request;
}

/// The pieces a test needs to drive and inspect the Admin slice.
final class AdminHarness {
  /// Creates a harness over its [container] and [captured] list.
  AdminHarness({required this.container, required this.captured});

  /// The Riverpod container backing the overridden providers.
  final ProviderContainer container;

  /// Every request the [MockClient] saw, in order.
  final List<CapturedRequest> captured;

  /// `ProviderScope` overrides for widget tests.
  List<Override> get overrides => _overrides;

  late final List<Override> _overrides;

  /// Disposes the container (call in `addTearDown`).
  void dispose() => container.dispose();
}

/// Builds an [AdminHarness]. The [handler] decides each canned response (or
/// throws to simulate a transport failure).
AdminHarness buildAdminHarness(
  Future<http.Response> Function(http.Request request) handler,
) {
  final captured = <CapturedRequest>[];
  final client = MockClient((request) async {
    captured.add(CapturedRequest(request));
    return handler(request);
  });

  final overrides = <Override>[
    // A fixed token store so the transport attaches a bearer token like prod.
    tokenStoreProvider.overrideWithValue(InMemoryTokenStore('admin-jwt')),
    apiTransportProvider.overrideWith(
      (ref) => ApiTransport(
        baseUri: Uri.parse('https://api.test.example/'),
        httpClient: client,
        tokenProvider: ref.watch(tokenStoreProvider).read,
        // No real HTTP ever happens here (MockClient) — disable the timeout
        // so a test that intentionally never resolves its handler (to assert
        // a loading state) doesn't leave a real Timer pending at teardown.
        requestTimeout: null,
      ),
    ),
    // The real Admin + FixtureSchedule clients over the faked transport (the
    // providers/controllers/screen under test are NOT overridden).
    adminApiProvider.overrideWith(
      (ref) => AdminApi(ref.watch(apiTransportProvider)),
    ),
    fixtureScheduleApiProvider.overrideWith(
      (ref) => FixtureScheduleApi(ref.watch(apiTransportProvider)),
    ),
    competitionApiProvider.overrideWith(
      (ref) => CompetitionApi(ref.watch(apiTransportProvider)),
    ),
  ];

  final container = ProviderContainer(
    overrides: overrides,
    retry: (retryCount, error) => null,
  );
  final harness = AdminHarness(container: container, captured: captured);
  harness._overrides = overrides;
  return harness;
}

/// A `200 OK` JSON-object response (a single-item read or a command result).
http.Response okJsonObject(Map<String, Object?> object) => http.Response(
  jsonEncode(object),
  200,
  headers: const {'content-type': 'application/json'},
);

/// A non-2xx response carrying the server's versioned error envelope.
http.Response errorEnvelope(int status, String code, String message) =>
    http.Response(
      jsonEncode({'schema_version': 1, 'code': code, 'message': message}),
      status,
      headers: const {'content-type': 'application/json'},
    );

// ---------------------------------------------------------------------------
// DTO fixtures (the exact wire shapes the admin routes return).
// ---------------------------------------------------------------------------

/// An empty audit trail (legitimate empty — `GET /admin/audit`).
const AuditLogDto emptyAuditLog = AuditLogDto(entries: <AuditEntryDto>[]);

/// Two audit entries, newest-first.
const AuditLogDto twoAuditEntries = AuditLogDto(
  entries: <AuditEntryDto>[
    AuditEntryDto(
      id: 'audit-2',
      actorId: 'admin-1',
      action: 'user_suspended',
      targetRef: 'user-9',
      reason: 'ابتزاز داخل الدردشة',
      occurredAt: '2026-08-07T12:00:00.000Z',
    ),
    AuditEntryDto(
      id: 'audit-1',
      actorId: 'admin-1',
      action: 'fixture_registered',
      targetRef: 'fixture-1',
      occurredAt: '2026-08-06T09:00:00.000Z',
    ),
  ],
);

/// The result of suspending `user-9`.
const UserSanctionResultDto suspendedResult = UserSanctionResultDto(
  userId: 'user-9',
  status: 'suspended',
);

/// The result of reinstating `user-9`.
const UserSanctionResultDto reinstatedResult = UserSanctionResultDto(
  userId: 'user-9',
  status: 'active',
);

/// A single participant's ledger with one entry.
const ParticipantEntriesDto oneLedgerEntry = ParticipantEntriesDto(
  participantId: 'part-1',
  entries: <PointEntryDto>[
    PointEntryDto(
      id: 'entry-1',
      participantId: 'part-1',
      roundId: 'r-1',
      kind: 'round_score',
      amount: 9,
      sourceRef: 'round-r-1',
      occurredAt: '2026-08-01T10:00:00.000Z',
    ),
  ],
);

/// A freshly registered fixture (`POST /fixtures` response).
const FixtureScheduleDto registeredFixture = FixtureScheduleDto(
  fixtureId: 'f-new',
  homeTeam: 'Al Hilal',
  awayTeam: 'Al Nassr',
  kickoffAt: '2026-08-20T18:00:00.000Z',
);

/// A freshly opened round (`POST /seasons/{id}/rounds` response).
const RoundDto openedRound = RoundDto(
  id: 'round-new',
  seasonId: 'season-1',
  sequence: 3,
  predictionDeadline: '2026-08-25T18:00:00.000Z',
  status: 'open',
  rulesetVersion: 1,
);

/// A freshly linked round-fixture (`POST /rounds/{id}/fixtures` response).
const RoundFixtureDto linkedRoundFixture = RoundFixtureDto(
  roundId: 'round-new',
  fixtureId: 'f-new',
  displayOrder: 0,
);

/// A freshly recorded fixture result (`PUT /fixtures/{id}/result` response).
const FixtureResultDto recordedFixtureResult = FixtureResultDto(
  fixtureId: 'f-new',
  homeGoals: 2,
  awayGoals: 1,
);

/// A scored round with one participant (`POST /rounds/{id}/score` and
/// `GET /rounds/{id}/scores` share this exact shape).
const RoundScoresDto oneRoundScore = RoundScoresDto(
  roundId: 'round-new',
  scores: <RoundScoreDto>[
    RoundScoreDto(
      roundId: 'round-new',
      participantId: 'part-1',
      rulesetVersion: 1,
      totalPoints: 9,
      fixtureResults: <FixtureScoreResultDto>[
        FixtureScoreResultDto(
          fixtureId: 'f-new',
          grade: 'exact_scoreline',
          points: 9,
        ),
      ],
    ),
  ],
);
