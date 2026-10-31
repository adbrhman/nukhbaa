/// The podium of a crowned month (migration 0191): the second and third
/// places are the first two players of the final board after the
/// champion(s), set by the admin once the month is crowned, frozen after.
library;

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
const _u4 = '00000000-0000-4000-8077-000000000004';
const _p1 = '00000000-0000-4000-8177-000000000001';
const _p2 = '00000000-0000-4000-8177-000000000002';
const _p3 = '00000000-0000-4000-8177-000000000003';
const _p4 = '00000000-0000-4000-8177-000000000004';
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
          crownedAt: crownedAt,
          monthEndAt: _monthEnd,
          prize: champion.prize,
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
  }) {
    final result = ParticipantFixtureTotals.of(
      participantId: ParticipantId(participantId),
      totalPoints: points,
      fixturesScored: decided,
      exactCount: exact,
      decidedCount: decided,
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
    for (final (p, u) in const [(_p1, _u1), (_p2, _u2), (_p3, _u3), (_p4, _u4)])
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

/// In-memory [MonthPodiumRepository].
final class _Podium implements MonthPodiumRepository {
  final List<MonthPodiumPlace> rows = [];
  int sets = 0;

  @override
  Future<Result<List<MonthPodiumPlace>>> list({required int limit}) async =>
      Result.ok(rows.take(limit).toList(growable: false));

  @override
  Future<Result<List<MonthPodiumPlace>>> of(SeasonId season) async =>
      Result.ok([
        for (final r in rows)
          if (r.seasonId == season) r,
      ]);

  @override
  Future<Result<void>> set({
    required SeasonId season,
    required List<PodiumPlaceToSet> places,
    required UserId setBy,
    required DateTime setAt,
  }) async {
    sets++;
    for (final p in places) {
      rows.add(
        MonthPodiumPlace(
          seasonId: season,
          place: p.place,
          userId: p.userId,
          displayName: 'P${p.userId.value.substring(35)}',
          points: p.points,
          exactCount: p.exactCount,
          decidedCount: p.decidedCount,
        ),
      );
    }
    return const Result.ok(null);
  }
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

  final _Podium podium = _Podium();

  AdminSetMonthPodium get setPodium => AdminSetMonthPodium(
    champions: champions,
    podium: podium,
    board: board,
    clock: clock,
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

Future<void> _crown(_World world, List<String> users) async {
  final crowned = await world.crown(
    principal: _adminPrincipal,
    seasonId: _season,
    userIds: users,
    force: false,
  );
  expect(crowned, isA<Ok<List<MonthChampion>>>());
}

void main() {
  test('second and third are the next two on the final board', () async {
    final world = _World();
    world.totals
      ..add(_p1, points: 50, exact: 6, decided: 30)
      ..add(_p3, points: 44, exact: 5, decided: 30)
      ..add(_p2, points: 44, exact: 7, decided: 30)
      ..add(_p4, points: 40, exact: 9, decided: 30);
    await _crown(world, const [_u1]);

    final result = await world.setPodium(
      principal: _adminPrincipal,
      seasonId: _season,
    );

    final podium = (result as Ok<List<MonthPodiumPlace>>).value;
    // Level on points, the board breaks the tie on exact scorelines.
    expect(
      [for (final p in podium) (p.place, p.userId.value)],
      [(2, _u2), (3, _u3)],
    );
    expect(podium.first.points, 44);
    expect(podium.first.exactCount, 7);
  });

  test('with two champions the podium starts after both', () async {
    final world = _World();
    world.totals
      ..add(_p1, points: 50, exact: 6, decided: 30)
      ..add(_p2, points: 50, exact: 6, decided: 30)
      ..add(_p3, points: 40, exact: 5, decided: 30)
      ..add(_p4, points: 30, exact: 5, decided: 30);
    await _crown(world, const [_u1, _u2]);

    final result = await world.setPodium(
      principal: _adminPrincipal,
      seasonId: _season,
    );

    expect(
      [
        for (final p in (result as Ok<List<MonthPodiumPlace>>).value)
          p.userId.value,
      ],
      [_u3, _u4],
    );
  });

  test('set once: asked again it answers the podium already set', () async {
    final world = _World();
    world.totals
      ..add(_p1, points: 50, exact: 6, decided: 30)
      ..add(_p2, points: 44, exact: 5, decided: 30)
      ..add(_p3, points: 40, exact: 5, decided: 30);
    await _crown(world, const [_u1]);
    await world.setPodium(principal: _adminPrincipal, seasonId: _season);
    world.totals.add(_p4, points: 49, exact: 1, decided: 30);

    final again = await world.setPodium(
      principal: _adminPrincipal,
      seasonId: _season,
    );

    expect(world.podium.sets, 1);
    expect(
      (again as Ok<List<MonthPodiumPlace>>).value.first.userId,
      const UserId(_u2),
    );
  });

  test('a month with one player after the champion gets one place', () async {
    final world = _World();
    world.totals
      ..add(_p1, points: 50, exact: 6, decided: 30)
      ..add(_p2, points: 44, exact: 5, decided: 30);
    await _crown(world, const [_u1]);

    final result = await world.setPodium(
      principal: _adminPrincipal,
      seasonId: _season,
    );

    expect((result as Ok<List<MonthPodiumPlace>>).value.single.place, 2);
  });

  test('refused before the crowning, for a player, and for no month', () async {
    final world = _World();
    world.totals.add(_p1, points: 50, exact: 6, decided: 30);

    expect(
      _codeOf(
        await world.setPodium(principal: _adminPrincipal, seasonId: _season),
      ),
      'champion.not_crowned',
    );
    expect(
      _codeOf(
        await world.setPodium(principal: _playerPrincipal, seasonId: _season),
      ),
      isNotNull,
    );
    expect(
      _codeOf(
        await world.setPodium(
          principal: _adminPrincipal,
          seasonId: 'c7700000-0000-4000-8000-0000000000ff',
        ),
      ),
      'champion.month_not_found',
    );
    expect(world.podium.sets, 0);
  });

  test('every player reads the podium list', () async {
    final world = _World();
    world.podium.rows.add(
      const MonthPodiumPlace(
        seasonId: SeasonId(_season),
        place: 2,
        userId: UserId(_u2),
        displayName: 'P2',
        points: 44,
        exactCount: 5,
        decidedCount: 30,
      ),
    );

    final result = await ListMonthPodium(podium: world.podium)(
      principal: _playerPrincipal,
    );

    expect((result as Ok<List<MonthPodiumPlace>>).value, hasLength(1));
  });
}
