import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _season = 'c2040000-0000-4000-8000-000000000011';
const _owner = '00000000-0000-4000-8204-0000000000aa';
const _player = '00000000-0000-4000-8204-0000000000bb';
const _u1 = '00000000-0000-4000-8204-000000000001';
const _u2 = '00000000-0000-4000-8204-000000000002';
const _u3 = '00000000-0000-4000-8204-000000000003';
const _u4 = '00000000-0000-4000-8204-000000000004';
const _p1 = '00000000-0000-4000-8304-000000000001';
const _p2 = '00000000-0000-4000-8304-000000000002';
const _p3 = '00000000-0000-4000-8304-000000000003';
const _p4 = '00000000-0000-4000-8304-000000000004';
const _f1 = 'c2040000-0000-4000-8000-0000000000f1';
const _f2 = 'c2040000-0000-4000-8000-0000000000f2';

const _ownerPrincipal = AuthenticatedUser(
  userId: UserId(_owner),
  role: PlatformRole.admin,
);
const _playerPrincipal = AuthenticatedUser(
  userId: UserId(_player),
  role: PlatformRole.user,
);

/// November 2026 ends at 00:00 Riyadh on 1 December.
final DateTime _monthEnd = DateTime.utc(2026, 11, 30, 21);

/// One hour after the month's end: its last match is over.
final DateTime _later = _monthEnd.add(const Duration(hours: 1));

final class _Clock implements Clock {
  _Clock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// In-memory [MonthChampionRepository]: one month and its crowned rows.
final class _Champions implements MonthChampionRepository {
  final List<MonthChampion> rows = [];

  @override
  Future<Result<ChampionMonth?>> month(SeasonId season) async {
    if (season.value != _season) {
      return const Result.ok(null);
    }
    return Result.ok(
      ChampionMonth(
        seasonId: season,
        label: '11/2026',
        startAt: DateTime.utc(2026, 10, 31, 21),
        endAt: _monthEnd,
        fixtures: const [FixtureRef(_f1), FixtureRef(_f2)],
        // f2 was postponed: it has no result.
        unscoredFixtures: 1,
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
          seasonLabel: '11/2026',
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
    crownedBys.add(crownedBy);
    return const Result.ok(null);
  }

  final List<UserId> crownedBys = [];

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
  }) async => const Result.ok(false);

  @override
  Future<Result<StoredAvatar?>> photo({
    required SeasonId season,
    required UserId user,
  }) async => const Result.ok(null);
}

/// In-memory podium (0191).
final class _Podium implements MonthPodiumRepository {
  final List<MonthPodiumPlace> rows = [];

  @override
  Future<Result<List<MonthPodiumPlace>>> list({required int limit}) async =>
      Result.ok(List<MonthPodiumPlace>.of(rows));

  @override
  Future<Result<List<MonthPodiumPlace>>> of(SeasonId season) async =>
      Result.ok([
        for (final row in rows)
          if (row.seasonId == season) row,
      ]);

  @override
  Future<Result<void>> set({
    required SeasonId season,
    required List<PodiumPlaceToSet> places,
    required UserId setBy,
    required DateTime setAt,
  }) async {
    for (final place in places) {
      rows.add(
        MonthPodiumPlace(
          seasonId: season,
          place: place.place,
          userId: place.userId,
          displayName: 'P${place.userId.value.substring(35)}',
          points: place.points,
          exactCount: place.exactCount,
          decidedCount: place.decidedCount,
        ),
      );
    }
    return const Result.ok(null);
  }
}

/// The month's stored totals, per participant, counting the reads.
final class _Totals implements FixtureTotalsReader {
  final Map<String, ParticipantFixtureTotals> lines = {};
  int reads = 0;

  void put(
    String participantId, {
    required int points,
    required int exact,
    required int outcome,
    required DateTime joinedAt,
  }) {
    final result = ParticipantFixtureTotals.of(
      participantId: ParticipantId(participantId),
      totalPoints: points,
      fixturesScored: 40,
      exactCount: exact,
      decidedCount: 40,
      outcomeCount: outcome,
      joinedAt: joinedAt,
    );
    lines[participantId] = (result as Ok<ParticipantFixtureTotals>).value;
  }

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async {
    reads++;
    return Result.ok(List<ParticipantFixtureTotals>.of(lines.values));
  }
}

final class _Participants implements ParticipantReader {
  final Map<String, Participant> byId = {
    for (final (p, u) in const [(_p1, _u1), (_p2, _u2), (_p3, _u3), (_p4, _u4)])
      p: Participant.fromStored(
        id: ParticipantId(p),
        seasonId: const SeasonId(_season),
        userId: UserId(u),
        status: ParticipantStatus.active,
        joinedAt: DateTime.utc(2026, 11, 1),
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

/// In-memory [MonthCrownStore]: the month is due while within the window,
/// with its crowning time read from the champions.
final class _Store implements MonthCrownStore {
  _Store(this._champions);

  final _Champions _champions;
  MonthCrownState state = const MonthCrownState(
    waiting: 0,
    skipped: 1,
    skippedNames: 'A2 × B2',
    rescore: 0,
  );
  List<FixtureRef> rescoreIds = const [];
  String? prize;
  final Set<String> notes = {};
  DateTime? writtenAfter;
  final List<String> prizesSet = [];

  @override
  Future<Result<List<CrownDueMonth>>> dueMonths({
    required DateTime now,
    required Duration window,
  }) async {
    if (now.isBefore(_monthEnd) || !now.isBefore(_monthEnd.add(window))) {
      return const Result.ok([]);
    }
    return Result.ok([
      CrownDueMonth(
        seasonId: const SeasonId(_season),
        label: '11/2026',
        endAt: _monthEnd,
        crownedAt: _champions.rows.isEmpty
            ? null
            : _champions.rows.first.crownedAt,
      ),
    ]);
  }

  @override
  Future<Result<MonthCrownState>> stateOf({
    required SeasonId season,
    required DateTime now,
    required Duration postponedAfter,
  }) async => Result.ok(state);

  @override
  Future<Result<List<FixtureRef>>> toRescore(SeasonId season) async =>
      Result.ok(rescoreIds);

  @override
  Future<Result<String?>> prizeFor(SeasonId season) async => Result.ok(prize);

  @override
  Future<Result<void>> setPrize({
    required SeasonId season,
    required String prize,
    required UserId setBy,
    required DateTime setAt,
  }) async {
    prizesSet.add(prize);
    this.prize = prize;
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> noteOnce({
    required SeasonId season,
    required String kind,
    required String signature,
  }) async => Result.ok(notes.add('$kind|$signature'));

  @override
  Future<Result<DateTime?>> resultsWrittenAfter({
    required SeasonId season,
    required DateTime since,
  }) async {
    final written = writtenAfter;
    return Result.ok(
      written != null && written.isAfter(since) ? written : null,
    );
  }
}

final class _Owner implements OwnerNotices {
  UserId? id = const UserId(_owner);
  final List<(String, String)> told = [];

  @override
  Future<Result<UserId?>> ownerId() async => Result.ok(id);

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async {
    told.add((title, body));
    return const Result.ok(null);
  }
}

final class _World {
  _World() : clock = _Clock(_later) {
    store = _Store(champions);
    // P1 leads; P2, P3 and P4 follow.
    totals
      ..put(_p1, points: 30, exact: 10, outcome: 5, joinedAt: _join(1))
      ..put(_p2, points: 24, exact: 8, outcome: 6, joinedAt: _join(2))
      ..put(_p3, points: 21, exact: 7, outcome: 9, joinedAt: _join(3))
      ..put(_p4, points: 18, exact: 6, outcome: 4, joinedAt: _join(4));
  }

  final _Champions champions = _Champions();
  final _Podium podium = _Podium();
  final _Totals totals = _Totals();
  final _Participants participants = _Participants();
  final _Owner owner = _Owner();
  final _Clock clock;
  late final _Store store;
  final List<String> rescored = [];

  static DateTime _join(int hour) => DateTime.utc(2026, 10, 31, 21 + hour);

  MonthFinalBoard get board => MonthFinalBoard(
    fixtureTotalsReader: totals,
    participantReader: participants,
  );

  AdminCrownMonthChampions get crown => AdminCrownMonthChampions(
    champions: champions,
    board: board,
    clock: clock,
  );

  late final AutoCrownMonths auto = AutoCrownMonths(
    store: store,
    champions: champions,
    board: board,
    crown: crown,
    setPodium: AdminSetMonthPodium(
      champions: champions,
      podium: podium,
      board: board,
      clock: clock,
    ),
    rescore: ({required String fixtureId}) async {
      rescored.add(fixtureId);
      return const Result.ok(null);
    },
    owner: owner,
  );

  Future<List<AutoCrownStep>> run([DateTime? at]) async {
    final DateTime now = at ?? clock.now;
    clock.now = now;
    final result = await auto(now: now);
    return [
      for (final outcome in (result as Ok<List<AutoCrownOutcome>>).value)
        outcome.step,
    ];
  }
}

String? _codeOf<T>(Result<T> result) => switch (result) {
  Ok<T>() => null,
  Err<T>(:final error) => error.code,
};

void main() {
  group('AutoCrownMonths', () {
    test(
      'nothing is looked at before the month ends or after its window',
      () async {
        final world = _World();
        expect(
          await world.run(_monthEnd.subtract(const Duration(minutes: 1))),
          isEmpty,
        );
        expect(await world.run(_monthEnd.add(AutoCrownMonths.window)), isEmpty);
        expect(world.champions.rows, isEmpty);
      },
    );

    test('waits while a match of the month may still be played', () async {
      final world = _World();
      world.store.state = const MonthCrownState(
        waiting: 1,
        waitingNames: 'A9 × B9',
        skipped: 0,
        rescore: 0,
      );
      expect(await world.run(), [AutoCrownStep.waiting]);
      expect(world.champions.rows, isEmpty);
      expect(world.owner.told, isEmpty);
    });

    test('waits five minutes after the last result was written', () async {
      final world = _World();
      world.store.state = MonthCrownState(
        waiting: 0,
        skipped: 0,
        rescore: 0,
        lastResultAt: _later.subtract(const Duration(minutes: 4)),
      );
      expect(await world.run(), [AutoCrownStep.waiting]);
      expect(world.champions.rows, isEmpty);

      world.store.state = MonthCrownState(
        waiting: 0,
        skipped: 0,
        rescore: 0,
        lastResultAt: _later.subtract(const Duration(minutes: 5)),
      );
      expect(await world.run(), [AutoCrownStep.crowned]);
    });

    test(
      'scores again what is not all in, and crowns on a later run',
      () async {
        final world = _World();
        world.store
          ..state = const MonthCrownState(waiting: 0, skipped: 0, rescore: 1)
          ..rescoreIds = const [FixtureRef(_f1)];
        expect(await world.run(), [AutoCrownStep.rescored]);
        expect(world.rescored, [_f1]);
        expect(world.champions.rows, isEmpty);

        world.store.state = const MonthCrownState(
          waiting: 0,
          skipped: 0,
          rescore: 0,
        );
        expect(await world.run(), [AutoCrownStep.crowned]);
      },
    );

    test('a fixture that never comes out right is reported, not retried '
        'for ever', () async {
      final world = _World();
      world.store
        ..state = const MonthCrownState(waiting: 0, skipped: 0, rescore: 1)
        ..rescoreIds = const [FixtureRef(_f1)];
      for (var i = 0; i < AutoCrownMonths.maxRescores; i++) {
        expect(await world.run(), [AutoCrownStep.rescored]);
      }
      final result = await world.auto(now: _later);
      expect(_codeOf(result), 'champion.rescore_stuck');
      expect(world.rescored, hasLength(AutoCrownMonths.maxRescores));
      expect(world.champions.rows, isEmpty);
    });

    test('crowns the first with the prize, as the owner, a postponed match '
        'left out, sets the podium and tells the owner once', () async {
      final world = _World();
      world.store.prize = '200 ريال سعودي';

      expect(await world.run(), [AutoCrownStep.crowned]);

      final champion = world.champions.rows.single;
      expect(champion.userId, const UserId(_u1));
      expect(champion.points, 30);
      expect(champion.exactCount, 10);
      expect(champion.prize, '200 ريال سعودي');
      expect(world.champions.crownedBys, [const UserId(_owner)]);
      expect(
        [for (final place in world.podium.rows) (place.place, place.userId)],
        [(2, const UserId(_u2)), (3, const UserId(_u3))],
      );

      final (title, body) = world.owner.told.single;
      expect(title, contains('11/2026'));
      expect(body, contains('البطل: P1'));
      expect(body, contains('200 ريال سعودي'));
      expect(body, contains('الثاني: P2'));
      expect(body, contains('الثالث: P3'));
      expect(body, contains('A2 × B2'));

      // The next runs find it crowned and say nothing more.
      expect(await world.run(), [AutoCrownStep.settled]);
      expect(world.owner.told, hasLength(1));
      expect(world.champions.rows, hasLength(1));
      expect(world.podium.rows, hasLength(2));
    });

    test('a month without a prize set is crowned without one', () async {
      final world = _World();
      expect(await world.run(), [AutoCrownStep.crowned]);
      expect(world.champions.rows.single.prize, isNull);
      expect(world.owner.told.single.$2, contains('بلا نص جائزة'));
    });

    test(
      'a tie for first on points, exact scorelines and right outcomes '
      'waits for the owner, whatever the join times, and is told once',
      () async {
        final world = _World();
        // P2 levels with P1 but joined an hour later.
        world.totals.put(
          _p2,
          points: 30,
          exact: 10,
          outcome: 5,
          joinedAt: _World._join(2),
        );

        expect(await world.run(), [AutoCrownStep.tie]);
        expect(world.champions.rows, isEmpty);
        final (title, body) = world.owner.told.single;
        expect(title, contains('ينتظر قرارك'));
        expect(body, contains('P1'));
        expect(body, contains('P2'));

        expect(await world.run(), [AutoCrownStep.tie]);
        expect(world.owner.told, hasLength(1));

        // The owner crowns the later-joined one by hand; the next run sets
        // the podium and tells him the crowning.
        final crowned = await world.crown(
          principal: _ownerPrincipal,
          seasonId: _season,
          userIds: const [_u2],
          force: true,
        );
        expect(_codeOf(crowned), isNull);
        expect(await world.run(), [AutoCrownStep.settled]);
        expect(
          [for (final place in world.podium.rows) place.userId],
          [const UserId(_u1), const UserId(_u3)],
        );
        expect(world.owner.told, hasLength(2));
        expect(world.owner.told.last.$1, contains('تُوِّج'));
      },
    );

    test('a result written after the crowning that changes the first three is '
        'told once; an unchanged one is not read again', () async {
      final world = _World();
      expect(await world.run(), [AutoCrownStep.crowned]);
      final crownedAt = world.champions.rows.single.crownedAt;

      // A result corrected later that changes nothing.
      world.store.writtenAfter = crownedAt.add(const Duration(minutes: 30));
      expect(await world.run(), [AutoCrownStep.settled]);
      final reads = world.totals.reads;
      expect(await world.run(), [AutoCrownStep.settled]);
      expect(world.totals.reads, reads, reason: 'the same write, not read');

      // Another one moves P4 above P3.
      world.totals.put(
        _p4,
        points: 22,
        exact: 7,
        outcome: 4,
        joinedAt: _World._join(4),
      );
      world.store.writtenAfter = crownedAt.add(const Duration(minutes: 40));
      expect(await world.run(), [AutoCrownStep.changed]);
      final (title, body) = world.owner.told.last;
      expect(title, contains('تغيّر ترتيب'));
      expect(body, contains('3. P4'));
      expect(world.podium.rows.last.userId, const UserId(_u3));

      world.store.writtenAfter = crownedAt.add(const Duration(minutes: 50));
      expect(await world.run(), [AutoCrownStep.changed]);
      expect(world.owner.told, hasLength(2), reason: 'told once');
    });

    test('nobody on the board: told once, nothing crowned', () async {
      final world = _World();
      world.totals.lines.clear();
      expect(await world.run(), [AutoCrownStep.empty]);
      expect(await world.run(), [AutoCrownStep.empty]);
      expect(world.owner.told, hasLength(1));
      expect(world.champions.rows, isEmpty);
    });

    test('without the owner account nothing is crowned', () async {
      final world = _World();
      world.owner.id = null;
      final result = await world.auto(now: _later);
      expect(_codeOf(result), 'champion.owner_missing');
      expect(world.champions.rows, isEmpty);
    });
  });

  group('the crown follows points, exact scorelines and right outcomes', () {
    test('a player level with the first may be crowned whatever his join '
        'time, and the preview shows him first', () async {
      final world = _World();
      world.totals.put(
        _p2,
        points: 30,
        exact: 10,
        outcome: 5,
        joinedAt: _World._join(2),
      );
      final preview = await AdminGetChampionCandidates(
        champions: world.champions,
        board: world.board,
        clock: world.clock,
        crownStore: world.store..prize = '150',
      )(principal: _ownerPrincipal, seasonId: _season);
      final value = (preview as Ok<ChampionCandidates>).value;
      expect(
        [for (final line in value.candidates) line.entry.rank],
        [1, 1, 3, 4],
      );
      expect(value.plannedPrize, '150');

      final crowned = await world.crown(
        principal: _ownerPrincipal,
        seasonId: _season,
        userIds: const [_u1, _u2],
        force: true,
      );
      expect(_codeOf(crowned), isNull);
      expect(world.champions.rows, hasLength(2));
    });

    test('one exact scoreline fewer is not level', () async {
      final world = _World();
      world.totals.put(
        _p2,
        points: 30,
        exact: 9,
        outcome: 6,
        joinedAt: _World._join(2),
      );
      final crowned = await world.crown(
        principal: _ownerPrincipal,
        seasonId: _season,
        userIds: const [_u2],
        force: true,
      );
      expect(_codeOf(crowned), 'champion.not_first');
    });
  });

  group('AdminSetMonthPrize', () {
    AdminSetMonthPrize prizeOf(_World world) => AdminSetMonthPrize(
      champions: world.champions,
      store: world.store,
      clock: world.clock,
    );

    test('an admin sets the prize ahead, trimmed, and changes it', () async {
      final world = _World();
      final set = prizeOf(world);
      final first = await set(
        principal: _ownerPrincipal,
        seasonId: _season,
        prize: '  150 ريال سعودي ',
      );
      expect((first as Ok<String>).value, '150 ريال سعودي');
      await set(principal: _ownerPrincipal, seasonId: _season, prize: '200');
      expect(world.store.prizesSet, ['150 ريال سعودي', '200']);
    });

    test('a blank or long prize, an unknown or crowned month, a player: '
        'refused', () async {
      final world = _World();
      final set = prizeOf(world);
      expect(
        _codeOf(
          await set(principal: _ownerPrincipal, seasonId: _season, prize: ' '),
        ),
        'champion.prize_blank',
      );
      expect(
        _codeOf(
          await set(
            principal: _ownerPrincipal,
            seasonId: _season,
            prize: 'x' * 81,
          ),
        ),
        'champion.prize_too_long',
      );
      expect(
        _codeOf(
          await set(
            principal: _ownerPrincipal,
            seasonId: 'c2040000-0000-4000-8000-000000000099',
            prize: '150',
          ),
        ),
        'champion.month_not_found',
      );
      expect(
        _codeOf(
          await set(principal: _playerPrincipal, seasonId: _season, prize: '1'),
        ),
        'auth.insufficient_role',
      );
      await world.run();
      expect(
        _codeOf(
          await set(principal: _ownerPrincipal, seasonId: _season, prize: '9'),
        ),
        'champion.already_crowned',
      );
      expect(world.store.prizesSet, isEmpty);
    });
  });
}
