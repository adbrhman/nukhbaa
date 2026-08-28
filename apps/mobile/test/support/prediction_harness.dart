/// Test harness for the Prediction (submit) slice.
///
/// Mirrors `competition_harness.dart`: it builds a `ProviderScope` whose
/// networking is served entirely by a `package:http/testing.dart` [MockClient]
/// (no live socket), wiring the shared `apiTransportProvider` over that client so
/// the real `predictionApiProvider` (the submit controller + `myPredictionProvider`)
/// AND the real `competitionApiProvider` (the reused `roundDetailProvider` /
/// `roundFixturesProvider` the screen composes) exercise the genuine `api_client`
/// end-to-end — only the socket is faked. The token store is a seedable in-memory
/// fake so the transport still attaches a bearer token exactly as production does.
///
/// A test supplies a [handler] that returns a canned response per request (or
/// throws to simulate a transport failure). Because the Prediction screen issues
/// several distinct reads/writes (`GET /rounds/{id}`, `GET /rounds/{id}/fixtures`,
/// `GET /rounds/{id}/predictions`, `POST /rounds/{id}/predictions`), the handler
/// is expected to branch on `request.method` + `request.url.path`. Response
/// builders ([okJsonList]/[okJsonObject]/[errorEnvelope]) and DTO fixtures are
/// provided.
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

/// A point far enough in the future that it stays "not yet started"
/// for the lifetime of any single test run — computed at runtime instead
/// of hardcoded, so it never silently becomes "in the past" as real
/// calendar time passes.
String _futureIso() =>
    DateTime.now().toUtc().add(const Duration(days: 365)).toIso8601String();

/// One captured outbound request (for asserting method + path + body).
final class CapturedRequest {
  /// Wraps a captured [http.Request].
  CapturedRequest(this.request);

  /// The raw captured request.
  final http.Request request;
}

/// The pieces a test needs to drive and inspect the Prediction slice.
final class PredictionHarness {
  /// Creates a harness over its [container] and [captured] list.
  PredictionHarness({required this.container, required this.captured});

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

/// Builds a [PredictionHarness]. The [handler] decides each canned response (or
/// throws to simulate a transport failure).
PredictionHarness buildPredictionHarness(
  Future<http.Response> Function(http.Request request) handler,
) {
  final captured = <CapturedRequest>[];
  final client = MockClient((request) async {
    captured.add(CapturedRequest(request));
    return handler(request);
  });

  final overrides = <Override>[
    // A fixed token store so the transport attaches a bearer token like prod.
    tokenStoreProvider.overrideWithValue(InMemoryTokenStore('predict-jwt')),
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
    // The real Prediction + Competition clients over the faked transport (the
    // providers/controller/screen under test are NOT overridden).
    predictionApiProvider.overrideWith(
      (ref) => PredictionApi(ref.watch(apiTransportProvider)),
    ),
    competitionApiProvider.overrideWith(
      (ref) => CompetitionApi(ref.watch(apiTransportProvider)),
    ),
  ];

  final container = ProviderContainer(
    overrides: overrides,
    retry: (retryCount, error) => null,
  );
  final harness = PredictionHarness(container: container, captured: captured);
  harness._overrides = overrides;
  return harness;
}

/// A `200 OK` JSON-array response (a list read).
http.Response okJsonList(List<Object?> elements) => http.Response(
  jsonEncode(elements),
  200,
  headers: const {'content-type': 'application/json'},
);

/// A `200 OK` JSON-object response (a single-item read or a submit result).
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
// DTO fixtures (the exact wire shapes the prediction/round routes return).
// ---------------------------------------------------------------------------

/// An OPEN round (predictions allowed) — no earlier round in the season is
/// blocking it, so the sequential-round gate reports it predictable.
final RoundDto openRound = RoundDto(
  id: 'r-1',
  seasonId: 's-1',
  sequence: 1,
  predictionDeadline: _futureIso(),
  status: 'open',
  rulesetVersion: 3,
  isPredictable: true,
);

/// A LOCKED round (predictions closed).
final RoundDto lockedRound = RoundDto(
  id: 'r-1',
  seasonId: 's-1',
  sequence: 1,
  predictionDeadline: _futureIso(),
  status: 'locked',
  rulesetVersion: 3,
);

/// An OPEN round that the sequential-round gate is still blocking — an
/// earlier round in the same season hasn't been locked yet.
final RoundDto openButNotYetPredictableRound = RoundDto(
  id: 'r-1',
  seasonId: 's-1',
  sequence: 2,
  predictionDeadline: _futureIso(),
  status: 'open',
  rulesetVersion: 3,
);

/// Two fixtures of [openRound], in display order.
final RoundFixtureCardDto fixtureA = RoundFixtureCardDto(
  roundId: 'r-1',
  fixtureId: 'f-a',
  displayOrder: 0,
  homeTeam: 'Al Hilal',
  awayTeam: 'Al Nassr',
  kickoffAt: _futureIso(),
);

/// The second fixture of [openRound].
const RoundFixtureCardDto fixtureB = RoundFixtureCardDto(
  roundId: 'r-1',
  fixtureId: 'f-b',
  displayOrder: 1,
  homeTeam: null,
  awayTeam: null,
  kickoffAt: null,
);

/// A third fixture of [openRound] that has already kicked off (a fixed date
/// safely in the past): exercises the per-fixture lock — disabled score
/// inputs, no tappable double star.
const RoundFixtureCardDto fixtureLocked = RoundFixtureCardDto(
  roundId: 'r-1',
  fixtureId: 'f-locked',
  displayOrder: 2,
  homeTeam: 'Al Ahly',
  awayTeam: 'Zamalek',
  kickoffAt: '2020-01-01T00:00:00.000Z',
);

/// A stored prediction for [openRound] covering both fixtures.
const PredictionDto storedPrediction = PredictionDto(
  id: 'p-1',
  participantId: 'part-1',
  roundId: 'r-1',
  submittedAt: '2026-08-01T10:00:00.000Z',
  fixtureScores: <FixtureScoreDto>[
    FixtureScoreDto(fixtureId: 'f-a', homeGoals: 2, awayGoals: 1),
    FixtureScoreDto(fixtureId: 'f-b', homeGoals: 0, awayGoals: 0),
  ],
);

/// A stored per-fixture prediction (Axiom 4 Amendment; the per-fixture
/// sibling of [storedPrediction]) — submitted more recently, so it sorts
/// first in the merged history.
const FixturePredictionDto storedFixturePrediction = FixturePredictionDto(
  id: 'fp-1',
  participantId: 'part-1',
  fixtureId: 'f-c',
  submittedAt: '2026-08-02T10:00:00.000Z',
  homeGoals: 3,
  awayGoals: 3,
);
