import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _season = 'c7700000-0000-4000-8000-000000000009';
const _admin = '00000000-0000-4000-8077-0000000000aa';
const _player = '00000000-0000-4000-8077-0000000000bb';
const _u1 = '00000000-0000-4000-8077-000000000001';
const _u2 = '00000000-0000-4000-8077-000000000002';
const _u3 = '00000000-0000-4000-8077-000000000003';
const _p1 = '00000000-0000-4000-8177-000000000001';
const _p2 = '00000000-0000-4000-8177-000000000002';
const _p3 = '00000000-0000-4000-8177-000000000003';
const _f1 = 'c7700000-0000-4000-8000-0000000000f1';

const _adminPrincipal = AuthenticatedUser(
  userId: UserId(_admin),
  role: PlatformRole.admin,
);
const _playerPrincipal = AuthenticatedUser(
  userId: UserId(_player),
  role: PlatformRole.user,
);

final DateTime _monthEnd = DateTime.utc(2026, 9, 30, 21);

final class _Clock implements Clock {
  _Clock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// In-memory [MonthChampionRepository]: one month, its crowned rows and
/// their pictures.
final class _Champions implements MonthChampionRepository {
  _Champions({this.unscored = 0});

  int unscored;
  final List<MonthChampion> rows = [];
  final Map<String, List<int>> photos = {};
  UserId? crownedBy;

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
        fixtures: const [FixtureRef(_f1)],
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
    this.crownedBy = crownedBy;
    for (final champion in champions) {
      rows.add(
        MonthChampion(
          seasonId: season,
          seasonLabel: '09/2026',
          userId: champion.userId,
          displayName: 'P${champion.userId.value.substring(35)}',
          points: champion.points,
          exactCount: champion.exactCount,
          decidedCount: champion.decidedCount,
          referralPoints: champion.referralPoints,
          crownedAt: crownedAt,
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<List<MonthChampion>>> list({required int limit}) async =>
      Result.ok(rows.take(limit).toList(growable: false));

  @override
  Future<Result<bool>> setPhoto({
    required SeasonId season,
    required UserId user,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  }) async {
    final known = rows.any(
      (row) => row.seasonId == season && row.userId == user,
    );
    if (known) {
      photos[user.value] = bytes;
    }
    return Result.ok(known);
  }

  @override
  Future<Result<StoredAvatar?>> photo({
    required SeasonId season,
    required UserId user,
  }) async {
    final bytes = photos[user.value];
    return Result.ok(
      bytes == null
          ? null
          : StoredAvatar(
              bytes: bytes,
              mime: 'image/png',
              updatedAt: DateTime.utc(2026, 10),
            ),
    );
  }
}

/// The totals the live board would sum, seeded per participant.
final class _Totals implements FixtureTotalsReader {
  final List<ParticipantFixtureTotals> lines = [];

  void add(
    String participantId, {
    required int points,
    required int exact,
    required int decided,
    int referral = 0,
  }) {
    final result = ParticipantFixtureTotals.of(
      participantId: ParticipantId(participantId),
      totalPoints: points,
      fixturesScored: decided,
      exactCount: exact,
      decidedCount: decided,
      referralPoints: referral,
    );
    lines.add((result as Ok<ParticipantFixtureTotals>).value);
  }

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async => Result.ok(List<ParticipantFixtureTotals>.of(lines));
}

final class _Participants implements ParticipantReader {
  final Map<String, Participant> byId = {
    for (final (p, u) in const [(_p1, _u1), (_p2, _u2), (_p3, _u3)])
      p: Participant.fromStored(
        id: ParticipantId(p),
        seasonId: const SeasonId(_season),
        userId: UserId(u),
        status: ParticipantStatus.active,
        joinedAt: DateTime.utc(2026, 9, 2),
      ),
  };

  @override
  Future<Result<Participant?>> findParticipantById(ParticipantId id) async =>
      Result.ok(byId[id.value]);

  @override
  Future<Result<Map<String, String>>> findDisplayNames(
    List<ParticipantId> ids,
  ) async =>
      Result.ok({for (final id in ids) id.value: 'P${id.value.substring(35)}'});

  @override
  Future<Result<Map<String, ParticipantAvatarRef>>> findAvatarRefs(
    List<ParticipantId> ids,
  ) async => const Result.ok({});
}

final class _World {
  _World({int unscored = 0})
    : champions = _Champions(unscored: unscored),
      clock = _Clock(_monthEnd.add(const Duration(hours: 15)));

  final _Champions champions;
  final _Totals totals = _Totals();
  final _Participants participants = _Participants();
  final _Clock clock;

  MonthFinalBoard get board => MonthFinalBoard(
    fixtureTotalsReader: totals,
    participantReader: participants,
  );

  AdminCrownMonthChampions get crown => AdminCrownMonthChampions(
    champions: champions,
    board: board,
    clock: clock,
  );

  AdminGetChampionCandidates get candidates => AdminGetChampionCandidates(
    champions: champions,
    board: board,
    clock: clock,
  );
}

String? _codeOf<T>(Result<T> result) => switch (result) {
  Ok<T>() => null,
  Err<T>(:final error) => error.code,
};

void main() {
  group('AdminCrownMonthChampions', () {
    test('crowns the leader with the final figures frozen', () async {
      final world = _World();
      world.totals
        ..add(_p1, points: 42, exact: 6, decided: 30, referral: 2)
        ..add(_p2, points: 39, exact: 7, decided: 31);

      final result = await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u1],
        force: false,
      );

      final crowned = (result as Ok<List<MonthChampion>>).value;
      expect(crowned.single.userId, const UserId(_u1));
      expect(crowned.single.points, 42);
      expect(crowned.single.exactCount, 6);
      expect(crowned.single.decidedCount, 30);
      expect(crowned.single.referralPoints, 2);
      expect(crowned.single.crownedAt, world.clock.now);
      expect(world.champions.crownedBy, const UserId(_admin));
    });

    test(
      'two players level on every tie-break: the admin may crown both',
      () async {
        final world = _World();
        world.totals
          ..add(_p1, points: 42, exact: 6, decided: 30, referral: 2)
          ..add(_p2, points: 42, exact: 6, decided: 28, referral: 2)
          ..add(_p3, points: 20, exact: 2, decided: 25);

        final result = await world.crown(
          principal: _adminPrincipal,
          seasonId: _season,
          userIds: const [_u1, _u2],
          force: false,
        );

        expect(
          (result as Ok<List<MonthChampion>>).value.map((c) => c.userId.value),
          unorderedEquals(<String>[_u1, _u2]),
        );
      },
    );

    test('...or just one of them', () async {
      final world = _World();
      world.totals
        ..add(_p1, points: 42, exact: 6, decided: 30)
        ..add(_p2, points: 42, exact: 6, decided: 28);

      final result = await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u2],
        force: false,
      );

      expect(
        (result as Ok<List<MonthChampion>>).value.single.userId.value,
        _u2,
      );
    });

    test('a player who is not first is never crowned', () async {
      final world = _World();
      world.totals
        ..add(_p1, points: 42, exact: 6, decided: 30)
        ..add(_p2, points: 42, exact: 5, decided: 30);

      final result = await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u2],
        force: false,
      );

      expect(_codeOf(result), 'champion.not_first');
      expect(world.champions.rows, isEmpty);
    });

    test('not before the month is over', () async {
      final world = _World();
      world.totals.add(_p1, points: 42, exact: 6, decided: 30);
      world.clock.now = _monthEnd.subtract(const Duration(minutes: 1));

      final result = await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u1],
        force: false,
      );

      expect(_codeOf(result), 'champion.month_not_over');
    });

    test('a crowned month is not crowned again', () async {
      final world = _World();
      world.totals.add(_p1, points: 42, exact: 6, decided: 30);
      await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u1],
        force: false,
      );

      final again = await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u1],
        force: false,
      );

      expect(_codeOf(again), 'champion.already_crowned');
      expect(world.champions.rows, hasLength(1));
    });

    test(
      'fixtures without a result stop it unless the admin confirms',
      () async {
        final world = _World(unscored: 1);
        world.totals.add(_p1, points: 42, exact: 6, decided: 30);

        final refused = await world.crown(
          principal: _adminPrincipal,
          seasonId: _season,
          userIds: const [_u1],
          force: false,
        );
        expect(_codeOf(refused), 'champion.fixtures_unscored');

        final forced = await world.crown(
          principal: _adminPrincipal,
          seasonId: _season,
          userIds: const [_u1],
          force: true,
        );
        expect(forced, isA<Ok<List<MonthChampion>>>());
      },
    );

    test('one or two distinct players, nothing else', () async {
      final world = _World();
      world.totals.add(_p1, points: 42, exact: 6, decided: 30);

      for (final List<String>? ids in <List<String>?>[
        null,
        const <String>[],
        const [_u1, _u2, _u3],
        const [_u1, _u1],
      ]) {
        final result = await world.crown(
          principal: _adminPrincipal,
          seasonId: _season,
          userIds: ids,
          force: false,
        );
        expect(_codeOf(result), 'champion.choose_one_or_two', reason: '$ids');
      }
    });

    test('a player cannot crown anyone', () async {
      final world = _World();
      world.totals.add(_p1, points: 42, exact: 6, decided: 30);

      final result = await world.crown(
        principal: _playerPrincipal,
        seasonId: _season,
        userIds: const [_u1],
        force: false,
      );

      expect(_codeOf(result), 'auth.insufficient_role');
    });
  });

  group('AdminGetChampionCandidates', () {
    test('the preview shows the month, its state and everyone first', () async {
      final world = _World(unscored: 2);
      world.totals
        ..add(_p1, points: 42, exact: 6, decided: 30)
        ..add(_p2, points: 42, exact: 6, decided: 28)
        ..add(_p3, points: 20, exact: 2, decided: 25);

      final result = await world.candidates(
        principal: _adminPrincipal,
        seasonId: _season,
      );

      final preview = (result as Ok<ChampionCandidates>).value;
      expect(preview.ended, isTrue);
      expect(preview.month.unscoredFixtures, 2);
      expect(preview.month.label, '09/2026');
      expect(preview.candidates.map((c) => c.entry.rank), [1, 1, 3]);
      expect(preview.candidates.first.userId.value, anyOf(_u1, _u2));
    });

    test('an unknown month is refused', () async {
      final world = _World();

      final result = await world.candidates(
        principal: _adminPrincipal,
        seasonId: 'c7700000-0000-4000-8000-0000000000ff',
      );

      expect(_codeOf(result), 'champion.month_not_found');
    });
  });

  group('the picture', () {
    test('is set for a champion and read back by any player', () async {
      final world = _World();
      world.totals.add(_p1, points: 42, exact: 6, decided: 30);
      await world.crown(
        principal: _adminPrincipal,
        seasonId: _season,
        userIds: const [_u1],
        force: false,
      );

      final set =
          await AdminSetChampionPhoto(
            champions: world.champions,
            clock: world.clock,
          )(
            principal: _adminPrincipal,
            seasonId: _season,
            userId: _u1,
            bytes: const [137, 80, 78, 71],
            mime: 'image/png',
          );
      expect(set, isA<Ok<List<MonthChampion>>>());

      final read = await ReadChampionPhoto(champions: world.champions)(
        principal: _playerPrincipal,
        seasonId: _season,
        userId: _u1,
      );
      expect((read as Ok<StoredAvatar?>).value?.bytes, [137, 80, 78, 71]);
    });

    test('follows the avatar rules and only fits a champion', () async {
      final world = _World();
      final setPhoto = AdminSetChampionPhoto(
        champions: world.champions,
        clock: world.clock,
      );

      final gif = await setPhoto(
        principal: _adminPrincipal,
        seasonId: _season,
        userId: _u1,
        bytes: const [1, 2, 3],
        mime: 'image/gif',
      );
      expect(_codeOf(gif), 'identity.avatar_mime_unsupported');

      final stranger = await setPhoto(
        principal: _adminPrincipal,
        seasonId: _season,
        userId: _u3,
        bytes: const [1, 2, 3],
        mime: 'image/png',
      );
      expect(_codeOf(stranger), 'champion.not_found');

      final byPlayer = await setPhoto(
        principal: _playerPrincipal,
        seasonId: _season,
        userId: _u1,
        bytes: const [1, 2, 3],
        mime: 'image/png',
      );
      expect(_codeOf(byPlayer), 'auth.insufficient_role');
    });
  });

  test('every player reads the champions', () async {
    final world = _World();
    world.totals.add(_p1, points: 42, exact: 6, decided: 30);
    await world.crown(
      principal: _adminPrincipal,
      seasonId: _season,
      userIds: const [_u1],
      force: false,
    );

    final result = await ListMonthChampions(champions: world.champions)(
      principal: _playerPrincipal,
    );

    expect((result as Ok<List<MonthChampion>>).value.single.userId.value, _u1);
    expect(ListMonthChampions.celebrationWindow, const Duration(hours: 48));
  });
}
