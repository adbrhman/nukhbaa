import 'dart:io';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/fixtures/[id]/details/index.dart' as route;
import 'competition_route_harness.dart';

final class _Store implements MatchDetailsStore {
  final Map<String, MatchDetails> rows = <String, MatchDetails>{};

  @override
  Future<Result<List<PendingMatchDetails>>> pending({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  }) async => const Result.ok(<PendingMatchDetails>[]);

  @override
  Future<Result<void>> save(MatchDetails details) async {
    rows[details.fixtureId] = details;
    return const Result.ok(null);
  }

  @override
  Future<Result<MatchDetails?>> find(String fixtureId) async =>
      Result.ok(rows[fixtureId]);
}

/// `GET /fixtures/{id}/details` through the real use-case: a player reads
/// the story of Paris FC 4-3 Rennes FC as stored, nothing while it is not
/// read, nothing for a match the provider did not have.
void main() {
  late _Store store;
  late CompositionRoot root;

  setUp(() {
    store = _Store();
    root = CompositionRoot.forTesting(
      getMatchDetails: GetMatchDetails(store: store),
    );
  });

  Future<Response> get({HttpMethod method = HttpMethod.get}) => route.onRequest(
    wireContext(root: root, principal: userPrincipal(), method: method),
    kFixtureId,
  );

  test('a player reads the events, the half time and the ground', () async {
    await store.save(
      MatchDetails(
        fixtureId: kFixtureId,
        found: true,
        source: 'highlightly',
        externalMatchId: '1321424223',
        fetchedAt: DateTime.utc(2026, 10, 18, 19),
        halfTimeHome: 2,
        halfTimeAway: 1,
        venue: 'Stade Jean Bouin',
        round: 'Regular Season - 8',
        events: const <MatchEvent>[
          MatchEvent(
            minute: '14',
            kind: MatchEventKind.goal,
            home: true,
            player: 'Maxime López',
            assist: 'Lassine Sinayoko',
          ),
          MatchEvent(
            minute: '51',
            kind: MatchEventKind.varGoalCancelled,
            home: false,
            player: 'Sebastian Szymański',
          ),
        ],
      ),
    );

    final response = await get();

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['available'], isTrue);
    expect(body['half_time_home'], 2);
    expect(body['half_time_away'], 1);
    expect(body['venue'], 'Stade Jean Bouin');
    expect(body['events'], <Object?>[
      <String, Object?>{
        'minute': '14',
        'kind': 'goal',
        'home': true,
        'player': 'Maxime López',
        'assist': 'Lassine Sinayoko',
      },
      <String, Object?>{
        'minute': '51',
        'kind': 'var_goal_cancelled',
        'home': false,
        'player': 'Sebastian Szymański',
        'assist': null,
      },
    ]);
  });

  test('nothing to show while the details are not read', () async {
    final body = await decodeBody(await get());

    expect(body['available'], isFalse);
    expect(body['events'], isEmpty);
  });

  test('nothing to show for a match the provider did not have', () async {
    await store.save(
      MatchDetails.notFound(
        fixtureId: kFixtureId,
        source: 'highlightly',
        fetchedAt: DateTime.utc(2026, 10, 18, 19),
      ),
    );

    final body = await decodeBody(await get());

    expect(body['available'], isFalse);
  });

  test('any other method is 405', () async {
    final response = await get(method: HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
