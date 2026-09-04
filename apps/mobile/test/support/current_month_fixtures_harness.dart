/// Test harness for [CurrentMonthFixturesScreen] (and, since it shares the
/// same private card widgets by convention, useful for exercising the
/// identical `FixturePredictionScreen` behavior too).
///
/// Mirrors `prediction_harness.dart`: builds a `ProviderScope` whose
/// networking is served entirely by a `package:http/testing.dart`
/// [MockClient] (no live socket), wiring the shared `apiTransportProvider`
/// over that client so the real `competitionApiProvider` (current-month
/// feed + fixture scores), `predictionApiProvider` (my-predictions read +
/// submit), and `teamsApiProvider` (team catalog) all exercise the genuine
/// `api_client` end-to-end — only the socket is faked.
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

/// A point far enough in the future that a fixture stays "not yet started"
/// (unlocked) for the lifetime of any single test run.
String futureIso() =>
    DateTime.now().toUtc().add(const Duration(days: 365)).toIso8601String();

/// One captured outbound request (for asserting method + path + body).
final class CapturedRequest {
  /// Wraps a captured [http.Request].
  CapturedRequest(this.request);

  /// The raw captured request.
  final http.Request request;
}

/// The pieces a test needs to drive and inspect the current-month-fixtures
/// slice.
final class CurrentMonthFixturesHarness {
  /// Creates a harness over its [container] and [captured] list.
  CurrentMonthFixturesHarness({
    required this.container,
    required this.captured,
  });

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

/// Builds a [CurrentMonthFixturesHarness]. The [handler] decides each canned
/// response (or throws to simulate a transport failure) — branch on
/// `request.method` + `request.url.path`.
CurrentMonthFixturesHarness buildCurrentMonthFixturesHarness(
  Future<http.Response> Function(http.Request request) handler,
) {
  final captured = <CapturedRequest>[];
  final client = MockClient((request) async {
    captured.add(CapturedRequest(request));
    return handler(request);
  });

  final overrides = <Override>[
    tokenStoreProvider.overrideWithValue(InMemoryTokenStore('feed-jwt')),
    apiTransportProvider.overrideWith(
      (ref) => ApiTransport(
        baseUri: Uri.parse('https://api.test.example/'),
        httpClient: client,
        tokenProvider: ref.watch(tokenStoreProvider).read,
        requestTimeout: null,
      ),
    ),
    competitionApiProvider.overrideWith(
      (ref) => CompetitionApi(ref.watch(apiTransportProvider)),
    ),
    predictionApiProvider.overrideWith(
      (ref) => PredictionApi(ref.watch(apiTransportProvider)),
    ),
    teamsApiProvider.overrideWith(
      (ref) => TeamsApi(ref.watch(apiTransportProvider)),
    ),
  ];

  final container = ProviderContainer(
    overrides: overrides,
    retry: (retryCount, error) => null,
  );
  final harness = CurrentMonthFixturesHarness(
    container: container,
    captured: captured,
  );
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

// ---------------------------------------------------------------------------
// DTO fixtures.
// ---------------------------------------------------------------------------

/// One unlocked, unpredicted fixture in the current-month feed.
final CurrentMonthFixtureItemDto sampleFeedItem = CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'الدوري السعودي',
  seasonLabel: '2026/27',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Al Hilal',
    awayTeam: 'Al Nassr',
    kickoffAt: futureIso(),
  ),
);
