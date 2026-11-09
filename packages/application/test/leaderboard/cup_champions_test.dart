import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _admin = '00000000-0000-4000-8204-0000000000aa';
const _player = '00000000-0000-4000-8204-0000000000bb';
const _u4 = '00000000-0000-4000-8204-000000000004';
const _u5 = '00000000-0000-4000-8204-000000000005';

const _adminPrincipal = AuthenticatedUser(
  userId: UserId(_admin),
  role: PlatformRole.admin,
);
const _playerPrincipal = AuthenticatedUser(
  userId: UserId(_player),
  role: PlatformRole.user,
);

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2099, 12);
}

/// In-memory [CupChampionRepository]: path 1 and 2 of November have a
/// champion, path 3 is vacant (so it is not listed and has no picture).
final class _Cups implements CupChampionRepository {
  final Map<String, List<int>> photos = {};
  final Map<String, DateTime> stamps = {};

  static String _key(String month, int place) => '$month/$place';

  bool _has(String month, int place) =>
      month == '2099-11-01' && (place == 1 || place == 2);

  @override
  Future<Result<List<CupChampion>>> list({required int limit}) async {
    return Result.ok([
      for (final place in const [1, 2])
        CupChampion(
          monthStart: '2099-11-01',
          place: place,
          how: place == 1 ? 'final' : 'walkover',
          userId: UserId(place == 1 ? _u4 : _u5),
          displayName: 'P${place + 3}',
          photoUpdatedAt: stamps[_key('2099-11-01', place)],
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
    photos[_key(monthStart, place)] = bytes;
    stamps[_key(monthStart, place)] = now;
    return const Result.ok(true);
  }

  @override
  Future<Result<bool>> removePhoto({
    required String monthStart,
    required int place,
  }) async {
    stamps.remove(_key(monthStart, place));
    return Result.ok(photos.remove(_key(monthStart, place)) != null);
  }

  @override
  Future<Result<StoredAvatar?>> photo({
    required String monthStart,
    required int place,
  }) async {
    final bytes = photos[_key(monthStart, place)];
    if (bytes == null) {
      return const Result.ok(null);
    }
    return Result.ok(
      StoredAvatar(
        bytes: bytes,
        mime: 'image/png',
        updatedAt: stamps[_key(monthStart, place)]!,
      ),
    );
  }
}

String? _codeOf<T>(Result<T> result) => switch (result) {
  Ok<T>() => null,
  Err<T>(:final error) => error.code,
};

void main() {
  CupChampions build(_Cups cups) =>
      CupChampions(champions: cups, clock: _Clock());

  test('every player reads the champions of the cup', () async {
    final result = await build(_Cups()).list(principal: _playerPrincipal);

    final champions = (result as Ok<List<CupChampion>>).value;
    expect(champions.map((c) => c.place), [1, 2]);
    expect(champions.first.userId.value, _u4);
  });

  test('an admin sets a picture, and any player reads it back', () async {
    final cups = _Cups();
    final cup = build(cups);

    final set = await cup.setPhoto(
      principal: _adminPrincipal,
      monthStart: '2099-11-01',
      place: '1',
      bytes: const [137, 80, 78, 71],
      mime: 'image/png',
    );
    expect(
      (set as Ok<List<CupChampion>>).value.first.photoUpdatedAt,
      DateTime.utc(2099, 12),
    );

    final read = await cup.photo(
      principal: _playerPrincipal,
      monthStart: '2099-11-01',
      place: '1',
    );
    expect((read as Ok<StoredAvatar?>).value?.bytes, [137, 80, 78, 71]);

    final none = await cup.photo(
      principal: _playerPrincipal,
      monthStart: '2099-11-01',
      place: '2',
    );
    expect((none as Ok<StoredAvatar?>).value, isNull);
  });

  test(
    'the picture follows the avatar rules and fits a champion only',
    () async {
      final cup = build(_Cups());

      final gif = await cup.setPhoto(
        principal: _adminPrincipal,
        monthStart: '2099-11-01',
        place: '1',
        bytes: const [1, 2, 3],
        mime: 'image/gif',
      );
      expect(_codeOf(gif), 'identity.avatar_mime_unsupported');

      final vacant = await cup.setPhoto(
        principal: _adminPrincipal,
        monthStart: '2099-11-01',
        place: '3',
        bytes: const [1, 2, 3],
        mime: 'image/png',
      );
      expect(_codeOf(vacant), 'cup.champion_not_found');

      final byPlayer = await cup.setPhoto(
        principal: _playerPrincipal,
        monthStart: '2099-11-01',
        place: '1',
        bytes: const [1, 2, 3],
        mime: 'image/png',
      );
      expect(_codeOf(byPlayer), 'auth.insufficient_role');
    },
  );

  test('a month or a path that is not one is refused', () async {
    final cup = build(_Cups());
    for (final target in const [
      ['2099-11-15', '1'],
      ['2099-13-01', '1'],
      ['november', '1'],
      ['2099-11-01', '0'],
      ['2099-11-01', '4'],
      ['2099-11-01', 'x'],
    ]) {
      final result = await cup.photo(
        principal: _playerPrincipal,
        monthStart: target[0],
        place: target[1],
      );
      expect(_codeOf(result), 'cup.target_invalid', reason: '$target');
    }
  });

  test('an admin removes a picture, a player cannot', () async {
    final cups = _Cups();
    final cup = build(cups);
    await cup.setPhoto(
      principal: _adminPrincipal,
      monthStart: '2099-11-01',
      place: '2',
      bytes: const [1],
      mime: 'image/png',
    );

    final byPlayer = await cup.removePhoto(
      principal: _playerPrincipal,
      monthStart: '2099-11-01',
      place: '2',
    );
    expect(_codeOf(byPlayer), 'auth.insufficient_role');
    expect(cups.photos, isNotEmpty);

    final removed = await cup.removePhoto(
      principal: _adminPrincipal,
      monthStart: '2099-11-01',
      place: '2',
    );
    expect(
      (removed as Ok<List<CupChampion>>).value.last.photoUpdatedAt,
      isNull,
    );
    expect(cups.photos, isEmpty);
  });
}
