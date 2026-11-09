import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/cup-champions/[month]/[place]/photo/index.dart'
    as admin_photo_route;
// ignore: always_use_package_imports
import '../../routes/cup-champions/[month]/[place]/photo/index.dart'
    as photo_route;
// ignore: always_use_package_imports
import '../../routes/cup-champions/index.dart' as list_route;
import 'competition_route_harness.dart';

const _month = '2026-11-01';
const _u1 = '00000000-0000-4000-8204-000000000001';
const _u2 = '00000000-0000-4000-8204-000000000002';

final DateTime _now = DateTime.utc(2026, 12, 1, 12);

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime nowUtc() => _now;
}

/// Paths 1 and 2 of November 2026 have a champion; path 3 is vacant.
final class _Cups implements CupChampionRepository {
  final Map<int, (List<int>, String, DateTime)> photos = {};

  bool _has(String month, int place) =>
      month == _month && (place == 1 || place == 2);

  @override
  Future<Result<List<CupChampion>>> list({required int limit}) async {
    return Result.ok([
      for (final place in const [1, 2])
        CupChampion(
          monthStart: _month,
          place: place,
          how: 'final',
          userId: UserId(place == 1 ? _u1 : _u2),
          displayName: 'P$place',
          photoUpdatedAt: photos[place]?.$3,
          avatarUpdatedAt: place == 2 ? DateTime.utc(2026, 11, 5) : null,
        ),
    ]);
  }

  @override
  Future<Result<bool>> setPhoto({
    required String monthStart,
    required int place,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  }) async {
    if (!_has(monthStart, place)) {
      return const Result.ok(false);
    }
    photos[place] = (bytes, mime, now);
    return const Result.ok(true);
  }

  @override
  Future<Result<bool>> removePhoto({
    required String monthStart,
    required int place,
  }) async => Result.ok(photos.remove(place) != null);

  @override
  Future<Result<StoredAvatar?>> photo({
    required String monthStart,
    required int place,
  }) async {
    final stored = photos[place];
    if (stored == null) {
      return const Result.ok(null);
    }
    return Result.ok(
      StoredAvatar(bytes: stored.$1, mime: stored.$2, updatedAt: stored.$3),
    );
  }
}

CompositionRoot _root(_Cups cups) => CompositionRoot.forTesting(
  cupChampions: CupChampions(champions: cups, clock: const _Clock()),
);

Future<List<int>> _bytesOf(Response response) => response
    .bytes()
    .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));

void main() {
  group('GET /cup-champions', () {
    test('a player reads the champions, with the picture URLs', () async {
      final cups = _Cups()..photos[1] = ([1], 'image/png', _now);
      final response = await list_route.onRequest(
        wireContext(
          root: _root(cups),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final listed =
          (await decodeBody(response))['champions']! as List<Object?>;
      expect(listed, hasLength(2));
      final first = listed.first! as Map<String, Object?>;
      expect(first['month_start'], _month);
      expect(first['user_id'], _u1);
      expect(
        first['photo_url'],
        '/cup-champions/$_month/1/photo?v=${_now.millisecondsSinceEpoch}',
      );
      expect(first.containsKey('avatar_url'), isFalse);
      final second = listed.last! as Map<String, Object?>;
      expect(second.containsKey('photo_url'), isFalse);
      expect(
        second['avatar_url'],
        '/users/$_u2/avatar?v=${DateTime.utc(2026, 11, 5).millisecondsSinceEpoch}',
      );
    });

    test('another method is 405; no service is a 503-class error', () async {
      final post = await list_route.onRequest(
        wireContext(root: _root(_Cups()), principal: userPrincipal()),
      );
      expect(post.statusCode, HttpStatus.methodNotAllowed);

      final absent = await list_route.onRequest(
        wireContext(
          root: CompositionRoot.forTesting(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(absent.statusCode, HttpStatus.serviceUnavailable);
      expect((await decodeBody(absent))['code'], 'cup.unavailable');
    });
  });

  group('the picture of a champion of the cup', () {
    Future<Response> upload(
      _Cups cups,
      String place, {
      required List<int> bytes,
      String? contentType = 'image/png',
      AuthenticatedUser? principal,
    }) {
      final context = wireContext(
        root: _root(cups),
        principal: principal ?? adminPrincipal(),
      );
      final Request request = context.request;
      when(() => request.headers).thenReturn(<String, String>{
        HttpHeaders.contentTypeHeader: ?contentType,
      });
      when(request.bytes).thenAnswer((_) => Stream.value(bytes));
      return admin_photo_route.onRequest(context, _month, place);
    }

    test('an admin sets it and every player reads it', () async {
      final cups = _Cups();
      final set = await upload(cups, '1', bytes: const [137, 80, 78, 71]);
      expect(set.statusCode, HttpStatus.ok);
      final listed = (await decodeBody(set))['champions']! as List<Object?>;
      expect(
        (listed.first! as Map<String, Object?>)['photo_url'],
        '/cup-champions/$_month/1/photo?v=${_now.millisecondsSinceEpoch}',
      );

      final read = await photo_route.onRequest(
        wireContext(
          root: _root(cups),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _month,
        '1',
      );
      expect(read.statusCode, HttpStatus.ok);
      expect(read.headers[HttpHeaders.contentTypeHeader], 'image/png');
      expect(await _bytesOf(read), [137, 80, 78, 71]);
    });

    test('no picture is 404', () async {
      final response = await photo_route.onRequest(
        wireContext(
          root: _root(_Cups()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _month,
        '2',
      );
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('a missing type is 400, a vacant path 409, a player 401', () async {
      final cups = _Cups();
      final untyped = await upload(
        cups,
        '1',
        bytes: const [1, 2, 3],
        contentType: null,
      );
      expect(untyped.statusCode, HttpStatus.badRequest);

      final vacant = await upload(cups, '3', bytes: const [1, 2, 3]);
      expect(vacant.statusCode, HttpStatus.conflict);
      expect((await decodeBody(vacant))['code'], 'cup.champion_not_found');

      final bad = await upload(cups, '4', bytes: const [1, 2, 3]);
      expect(bad.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(bad))['code'], 'cup.target_invalid');

      final player = await upload(
        cups,
        '1',
        bytes: const [1, 2, 3],
        principal: userPrincipal(),
      );
      expect(player.statusCode, HttpStatus.unauthorized);
      expect(cups.photos, isEmpty);
    });

    test('an admin removes it; a player cannot; PUT is 405', () async {
      final cups = _Cups()..photos[2] = ([1], 'image/png', _now);

      final byPlayer = await admin_photo_route.onRequest(
        wireContext(
          root: _root(cups),
          principal: userPrincipal(),
          method: HttpMethod.delete,
        ),
        _month,
        '2',
      );
      expect(byPlayer.statusCode, HttpStatus.unauthorized);
      expect(cups.photos, isNotEmpty);

      final removed = await admin_photo_route.onRequest(
        wireContext(
          root: _root(cups),
          principal: adminPrincipal(),
          method: HttpMethod.delete,
        ),
        _month,
        '2',
      );
      expect(removed.statusCode, HttpStatus.ok);
      final listed = (await decodeBody(removed))['champions']! as List<Object?>;
      expect(
        (listed.last! as Map<String, Object?>).containsKey('photo_url'),
        isFalse,
      );
      expect(cups.photos, isEmpty);

      final put = await admin_photo_route.onRequest(
        wireContext(
          root: _root(cups),
          principal: adminPrincipal(),
          method: HttpMethod.put,
        ),
        _month,
        '2',
      );
      expect(put.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
