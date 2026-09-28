import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/champions/[id]/index.dart' as crown_route;
// ignore: always_use_package_imports
import '../../routes/admin/champions/[id]/photos/[userId]/index.dart'
    as set_photo_route;
// ignore: always_use_package_imports
import '../../routes/champions/[id]/photos/[userId]/index.dart' as photo_route;
// ignore: always_use_package_imports
import '../../routes/champions/index.dart' as list_route;
import 'competition_route_harness.dart';

const _season = 'c7700000-0000-4000-8000-000000000009';
const _u1 = '00000000-0000-4000-8077-000000000001';
const _u2 = '00000000-0000-4000-8077-000000000002';
const _p1 = '00000000-0000-4000-8177-000000000001';
const _p2 = '00000000-0000-4000-8177-000000000002';

final DateTime _monthEnd = DateTime.utc(2026, 9, 30, 21);
final DateTime _now = DateTime.utc(2026, 10, 1, 12);

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime nowUtc() => _now;
}

final class _Champions implements MonthChampionRepository {
  int unscored = 0;
  final List<MonthChampion> rows = [];
  final Map<String, (List<int>, String)> photos = {};

  @override
  Future<Result<ChampionMonth?>> month(SeasonId season) async {
    if (season.value != _season) {
      return const Result.ok(null);
    }
    return Result.ok(
      ChampionMonth(
        seasonId: season,
        label: '09/2026',
        startAt: DateTime.utc(2026, 9),
        endAt: _monthEnd,
        fixtures: const [FixtureRef('c7700000-0000-4000-8000-0000000000f1')],
        unscoredFixtures: unscored,
        crowned: [for (final row in rows) row.userId],
      ),
    );
  }

  @override
  Future<Result<void>> crown({
    required SeasonId season,
    required List<ChampionToCrown> champions,
    required UserId crownedBy,
    required DateTime crownedAt,
  }) async {
    for (final champion in champions) {
      rows.add(
        MonthChampion(
          seasonId: season,
          seasonLabel: '09/2026',
          userId: champion.userId,
          displayName: 'Ahmad',
          points: champion.points,
          exactCount: champion.exactCount,
          decidedCount: champion.decidedCount,
          referralPoints: champion.referralPoints,
          crownedAt: crownedAt,
          avatarUpdatedAt: DateTime.utc(2026, 9, 5),
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<List<MonthChampion>>> list({required int limit}) async =>
      Result.ok(List<MonthChampion>.of(rows));

  @override
  Future<Result<bool>> setPhoto({
    required SeasonId season,
    required UserId user,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  }) async {
    final int at = rows.indexWhere((row) => row.userId == user);
    if (at < 0) {
      return const Result.ok(false);
    }
    final old = rows[at];
    rows[at] = MonthChampion(
      seasonId: old.seasonId,
      seasonLabel: old.seasonLabel,
      userId: old.userId,
      displayName: old.displayName,
      points: old.points,
      exactCount: old.exactCount,
      decidedCount: old.decidedCount,
      referralPoints: old.referralPoints,
      crownedAt: old.crownedAt,
      photoUpdatedAt: now,
      avatarUpdatedAt: old.avatarUpdatedAt,
    );
    photos[user.value] = (bytes, mime);
    return const Result.ok(true);
  }

  @override
  Future<Result<StoredAvatar?>> photo({
    required SeasonId season,
    required UserId user,
  }) async {
    final stored = photos[user.value];
    return Result.ok(
      stored == null
          ? null
          : StoredAvatar(bytes: stored.$1, mime: stored.$2, updatedAt: _now),
    );
  }
}

final class _Totals implements FixtureTotalsReader {
  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async => Result.ok([
    (ParticipantFixtureTotals.of(
              participantId: const ParticipantId(_p1),
              totalPoints: 42,
              fixturesScored: 30,
              exactCount: 6,
              decidedCount: 30,
            )
            as Ok<ParticipantFixtureTotals>)
        .value,
    (ParticipantFixtureTotals.of(
              participantId: const ParticipantId(_p2),
              totalPoints: 39,
              fixturesScored: 30,
              exactCount: 7,
              decidedCount: 30,
            )
            as Ok<ParticipantFixtureTotals>)
        .value,
  ]);
}

InMemoryParticipantReader _participants() => InMemoryParticipantReader()
  ..add(
    Participant.fromStored(
      id: const ParticipantId(_p1),
      seasonId: const SeasonId(_season),
      userId: const UserId(_u1),
      status: ParticipantStatus.active,
      joinedAt: DateTime.utc(2026, 9, 2),
    ),
  )
  ..add(
    Participant.fromStored(
      id: const ParticipantId(_p2),
      seasonId: const SeasonId(_season),
      userId: const UserId(_u2),
      status: ParticipantStatus.active,
      joinedAt: DateTime.utc(2026, 9, 2),
    ),
  );

CompositionRoot _root(_Champions champions) {
  final board = MonthFinalBoard(
    fixtureTotalsReader: _Totals(),
    participantReader: _participants(),
  );
  return CompositionRoot.forTesting(
    adminGetChampionCandidates: AdminGetChampionCandidates(
      champions: champions,
      board: board,
      clock: const _Clock(),
    ),
    adminCrownMonthChampions: AdminCrownMonthChampions(
      champions: champions,
      board: board,
      clock: const _Clock(),
    ),
    adminSetChampionPhoto: AdminSetChampionPhoto(
      champions: champions,
      clock: const _Clock(),
    ),
    listMonthChampions: ListMonthChampions(champions: champions),
    readChampionPhoto: ReadChampionPhoto(champions: champions),
  );
}

Future<List<int>> _bytesOf(Response response) => response
    .bytes()
    .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));

void main() {
  group('GET /admin/champions/{seasonId}', () {
    test('an admin previews the month and its leader', () async {
      final champions = _Champions()..unscored = 1;
      final response = await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _season,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['season_label'], '09/2026');
      expect(body['ended'], isTrue);
      expect(body['unscored_fixtures'], 1);
      expect(body['crowned'], isEmpty);
      final candidates = (body['candidates']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(candidates.first['user_id'], _u1);
      expect(candidates.first['rank'], 1);
      expect(candidates.first['points'], 42);
      expect(candidates[1]['rank'], 2);
    });

    test('a player is refused', () async {
      final response = await crown_route.onRequest(
        wireContext(
          root: _root(_Champions()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _season,
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('POST /admin/champions/{seasonId}', () {
    test('crowns the leader and answers the month\'s champions', () async {
      final champions = _Champions();
      final response = await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          body: const {
            'user_ids': [_u1],
          },
        ),
        _season,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final list = (body['champions']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(list.single['user_id'], _u1);
      expect(list.single['points'], 42);
      expect(list.single['crowned_at'], '2026-10-01T12:00:00.000Z');
      expect(list.single['celebrate_until'], '2026-10-03T12:00:00.000Z');
      expect(champions.rows, hasLength(1));
    });

    test('the second on the board is refused with 409', () async {
      final champions = _Champions();
      final response = await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          body: const {
            'user_ids': [_u2],
          },
        ),
        _season,
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'champion.not_first');
      expect(champions.rows, isEmpty);
    });

    test('unscored fixtures need the admin\'s confirmation', () async {
      final champions = _Champions()..unscored = 2;
      final refused = await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          body: const {
            'user_ids': [_u1],
          },
        ),
        _season,
      );
      expect(refused.statusCode, HttpStatus.conflict);
      expect((await decodeBody(refused))['code'], 'champion.fixtures_unscored');

      final forced = await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          body: const {
            'user_ids': [_u1],
            'force': true,
          },
        ),
        _season,
      );
      expect(forced.statusCode, HttpStatus.ok);
    });

    test('a body without user_ids is 400', () async {
      final response = await crown_route.onRequest(
        wireContext(
          root: _root(_Champions()),
          principal: adminPrincipal(),
          body: const {'user_ids': 'nope'},
        ),
        _season,
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('any other method is 405', () async {
      final response = await crown_route.onRequest(
        wireContext(
          root: _root(_Champions()),
          principal: adminPrincipal(),
          method: HttpMethod.delete,
        ),
        _season,
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('the champion\'s picture', () {
    Future<Response> upload(
      _Champions champions,
      String userId, {
      required List<int> bytes,
      String? contentType = 'image/png',
    }) {
      final context = wireContext(
        root: _root(champions),
        principal: adminPrincipal(),
      );
      // Take the request mock out first: stubbing through context.request
      // would re-stub context.request itself.
      final Request request = context.request;
      when(() => request.headers).thenReturn(<String, String>{
        if (contentType != null) HttpHeaders.contentTypeHeader: contentType,
      });
      when(request.bytes).thenAnswer((_) => Stream.value(bytes));
      return set_photo_route.onRequest(context, _season, userId);
    }

    test('an admin sets it and every player reads it', () async {
      final champions = _Champions();
      await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          body: const {
            'user_ids': [_u1],
          },
        ),
        _season,
      );

      final set = await upload(champions, _u1, bytes: const [137, 80, 78, 71]);
      expect(set.statusCode, HttpStatus.ok);
      final listed = (await decodeBody(set))['champions']! as List<Object?>;
      final photoUrl =
          (listed.single! as Map<String, Object?>)['photo_url']! as String;
      expect(
        photoUrl,
        '/champions/$_season/photos/$_u1'
        '?v=${_now.millisecondsSinceEpoch}',
      );

      final read = await photo_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _season,
        _u1,
      );
      expect(read.statusCode, HttpStatus.ok);
      expect(read.headers[HttpHeaders.contentTypeHeader], 'image/png');
      expect(await _bytesOf(read), [137, 80, 78, 71]);
    });

    test('no picture is 404', () async {
      final response = await photo_route.onRequest(
        wireContext(
          root: _root(_Champions()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _season,
        _u1,
      );
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('a missing content type is 400, a stranger 409', () async {
      final champions = _Champions();
      final untyped = await upload(
        champions,
        _u1,
        bytes: const [1, 2, 3],
        contentType: null,
      );
      expect(untyped.statusCode, HttpStatus.badRequest);

      final stranger = await upload(champions, _u2, bytes: const [1, 2, 3]);
      expect(stranger.statusCode, HttpStatus.conflict);
      expect((await decodeBody(stranger))['code'], 'champion.not_found');
    });
  });

  group('GET /champions', () {
    test('every player reads the champions with their pictures', () async {
      final champions = _Champions();
      await crown_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: adminPrincipal(),
          body: const {
            'user_ids': [_u1],
          },
        ),
        _season,
      );

      final response = await list_route.onRequest(
        wireContext(
          root: _root(champions),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final row =
          (body['champions']! as List<Object?>).single! as Map<String, Object?>;
      expect(row['season_label'], '09/2026');
      expect(row['display_name'], 'Ahmad');
      expect(row['avatar_url'], startsWith('/users/$_u1/avatar?v='));
      expect(row.containsKey('photo_url'), isFalse);
    });

    test('any other method is 405', () async {
      final response = await list_route.onRequest(
        wireContext(root: _root(_Champions()), principal: userPrincipal()),
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
