// NK313_03
/// `GET /owner/h2h-cup/picks` from the real entry point: the owner gate the
/// `/owner` subtree installs, then the route handler, the real use-case and
/// the real mapper over a scripted cup store and an unmasked pick reader.
/// The owner reads every pick before kickoff; an admin without a seat, a
/// player, and a request with no valid token get the `404` of a path with no
/// route, and nothing is read for them. Nothing writes here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/owner_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/owner/h2h-cup/picks/index.dart' as picks_route;
import 'competition_route_harness.dart';

const _owner = '11111111-2222-4333-8444-555555555555';
const _admin = '66666666-7777-4888-8999-000000000000';
const _a = '00000000-0000-4000-9000-000000000001';
const _b = '00000000-0000-4000-9000-000000000002';
const _c = '00000000-0000-4000-9000-000000000003';
const _d = '00000000-0000-4000-9000-000000000004';
const _notStarted = '00000000-0000-4000-9000-0000000000a1';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC.
final _now = DateTime.utc(2026, 11, 22, 12);

AuthenticatedUser _asAdmin(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.admin);

final class _Verifier implements TokenVerifier {
  _Verifier(this.answer);

  Result<AuthenticatedUser> answer;

  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async => answer;
}

final class _Seats implements OwnerNotices {
  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async =>
      Result.ok(user == const UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Audit implements OwnerAuditLog {
  @override
  Future<Result<void>> record({
    required UserId actor,
    required String method,
    required String path,
    required int status,
  }) async => const Result.ok(null);
}

final class _Cups implements H2hCupStore {
  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async {
    if (monthStart != _november) {
      return const Result.ok(H2hCupState.empty);
    }
    const ids = [_a, _b, _c, _d];
    return Result.ok(
      H2hCupState(
        entries: [
          for (var i = 0; i < ids.length; i++)
            H2hCupEntry(
              userId: UserId(ids[i]),
              place: 1,
              groupNumber: i + 1,
              leaguePoints: 40,
              pointsFor: 100,
              exactCount: 10,
            ),
        ],
        stages: [
          H2hCupStage(
            id: const H2hCupStageId('55555555-5555-4555-8555-555555555555'),
            monthStart: _november,
            step: const H2hCupStep(1, H2hCupRound.semi),
            attempt: 1,
            day: DateTime.utc(2026, 11, 22),
            fixtureCount: 1,
            lockedAt: null,
            pairs: const [
              H2hCupPair(slot: 1, home: UserId(_a), away: UserId(_c)),
              H2hCupPair(slot: 2, home: UserId(_b), away: UserId(_d)),
            ],
            results: const <H2hCupResult>[],
          ),
        ],
        titles: const <H2hCupTitle>[],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

/// Every pick of a fixture that has not kicked off, but `_d`'s: he did not
/// predict. Counts its readings.
final class _OwnerPicks implements H2hCupOwnerPickReader {
  int reads = 0;

  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>>
  fixturesOfUnmasked({required List<H2hCupStage> stages}) async {
    reads++;
    H2hFixturePick pick(int home, int away) => H2hFixturePick(
      homeGoals: home,
      awayGoals: away,
      isDouble: false,
      points: null,
      exact: false,
    );
    return Result.ok({
      for (final stage in stages)
        stage.id: [
          H2hCupStageFixture(
            fixtureId: _notStarted,
            homeTeam: 'Alpha',
            awayTeam: 'Beta',
            homeTeamId: null,
            awayTeamId: null,
            kickoffAt: DateTime.utc(2026, 11, 22, 18),
            counted: true,
            homeGoals: null,
            awayGoals: null,
            picks: {
              const UserId(_a): pick(1, 0),
              const UserId(_c): pick(7, 5),
              const UserId(_b): pick(2, 2),
            },
          ),
        ],
    });
  }
}

final class _Profiles implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final id in userIds)
      id: WeeklyLeagueMemberProfile(displayName: 'name-${id.value}'),
  });
}

class _MockGateContext extends Mock implements RequestContext {}

class _MockGateRequest extends Mock implements Request {}

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

void main() {
  setUpAll(() {
    registerFallbackValue(_asAdmin(_owner));
  });

  late _Verifier verifier;
  late _OwnerPicks picks;
  late int handled;

  setUp(() {
    verifier = _Verifier(Result.ok(_asAdmin(_owner)));
    picks = _OwnerPicks();
    handled = 0;
  });

  CompositionRoot root() => CompositionRoot.forTesting(
    authenticateRequest: AuthenticateRequest(verifier),
    ownerNotices: _Seats(),
    ownerAuditLog: _Audit(),
    getOwnerH2hCupPicks: GetOwnerH2hCupPicks(
      cups: _Cups(),
      picks: picks,
      profiles: _Profiles(),
      clock: FixedClock(_now),
    ),
  );

  /// The request as the server runs it: through the owner gate, then the
  /// route.
  Future<Response> call({
    HttpMethod method = HttpMethod.get,
    Map<String, String> query = const {},
  }) async {
    final rootFuture = Future<CompositionRoot>.value(root());
    final request = _MockGateRequest();
    when(() => request.method).thenReturn(method);
    when(() => request.uri).thenReturn(
      Uri(
        path: '/owner/h2h-cup/picks',
        queryParameters: query.isEmpty ? null : query,
      ),
    );
    when(
      () => request.headers,
    ).thenReturn({HttpHeaders.authorizationHeader: 'Bearer token'});

    final outer = _MockGateContext();
    when(() => outer.request).thenReturn(request);
    when(
      () => outer.read<Future<CompositionRoot>>(),
    ).thenAnswer((_) => rootFuture);
    late AuthenticatedUser provided;
    final inner = _MockGateContext();
    when(() => inner.request).thenReturn(request);
    when(
      () => inner.read<Future<CompositionRoot>>(),
    ).thenAnswer((_) => rootFuture);
    when(() => inner.read<AuthenticatedUser>()).thenAnswer((_) => provided);
    when(() => outer.provide<AuthenticatedUser>(any())).thenAnswer((inv) {
      provided =
          (inv.positionalArguments.first as AuthenticatedUser Function())();
      return inner;
    });

    final Handler handler = ownerGate()((context) {
      handled++;
      return picks_route.onRequest(context);
    });
    return handler(outer);
  }

  Future<void> expectNoRoute(Response response) async {
    expect(response.statusCode, HttpStatus.notFound);
    expect(await response.body(), routeNotFoundBody);
    expect(handled, 0);
    expect(picks.reads, 0);
  }

  group('GET /owner/h2h-cup/picks', () {
    test(
      'the owner reads every pick of a fixture that has not started',
      () async {
        final response = await call();

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        expect(body['month_start'], '2026-11-01');
        final stage = _list(_list(body['paths']).single['stages']).first;
        final pairs = _list(stage['pairs']);

        final first = _list(
          pairs.singleWhere((p) => p['slot'] == 1)['fixtures'],
        ).single;
        expect(first['state'], 'not_started');
        final home = first['home_side']! as Map;
        final away = first['away_side']! as Map;
        expect(home['revealed'], true);
        expect((home['pick']! as Map)['home_goals'], 1);
        expect(away['revealed'], true);
        expect((away['pick']! as Map)['home_goals'], 7);
        expect((away['pick']! as Map)['away_goals'], 5);

        // The player who did not predict: shown, with no pick.
        final second = _list(
          pairs.singleWhere((p) => p['slot'] == 2)['fixtures'],
        ).single;
        expect((second['home_side']! as Map)['pick'], isNotNull);
        expect(second['away_side'], {'revealed': true});
        expect(picks.reads, 1);
      },
    );

    test('a month that is not a date is 400', () async {
      final response = await call(query: {'month': 'soon'});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(jsonEncode(await decodeBody(response)), contains('h2h_month'));
    });

    test('a month with no cup reads an empty board', () async {
      final response = await call(query: {'month': '2026-05-01'});

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(_list(body['paths']), isEmpty);
      expect(picks.reads, 0);
    });

    for (final method in [
      HttpMethod.post,
      HttpMethod.put,
      HttpMethod.patch,
      HttpMethod.delete,
    ]) {
      test('an owner writing with ${method.name} is 405', () async {
        final response = await call(method: method);

        expect(response.statusCode, HttpStatus.methodNotAllowed);
        expect(picks.reads, 0);
      });
    }

    test('an admin who holds no seat gets a path with no route', () async {
      verifier.answer = Result.ok(_asAdmin(_admin));

      await expectNoRoute(await call());
    });

    test('a player gets a path with no route', () async {
      verifier.answer = const Result.ok(
        AuthenticatedUser(userId: UserId(_admin), role: PlatformRole.user),
      );

      await expectNoRoute(await call());
    });

    test('no token, or a bad one, is not told 401', () async {
      verifier.answer = const Result.err(
        AppError.authorization('auth.invalid_token', 'bad token'),
      );

      await expectNoRoute(await call());
    });

    test('a write by someone who is not an owner is the same 404', () async {
      verifier.answer = Result.ok(_asAdmin(_admin));

      await expectNoRoute(await call(method: HttpMethod.post));
    });
  });
}
