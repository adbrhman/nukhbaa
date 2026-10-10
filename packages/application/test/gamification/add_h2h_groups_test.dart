/// An admin adds groups to the month open now (2026-10-11): the players
/// waiting for a seat, most days of predictions first, twenty to a group,
/// into the next divisions of the ladder; each refusal keeps its code.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

const _admin = AuthenticatedUser(
  userId: UserId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  role: PlatformRole.admin,
);
const _player = AuthenticatedUser(
  userId: UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  role: PlatformRole.user,
);

final _october = DateTime.utc(2026, 10);

/// 02:00 Riyadh on October 11.
final _now = DateTime.utc(2026, 10, 10, 23);

List<UserId> _players(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    UserId('00000000-0000-4000-9000-${i.toString().padLeft(12, '0')}'),
];

/// The players waiting, as the database would order them; keeps what was
/// written.
final class _Extension implements H2hGroupExtension {
  _Extension(this.waiting);

  final List<UserId> waiting;
  final List<H2hDrawnGroup> written = <H2hDrawnGroup>[];
  int? askedMinDays;
  AppError? writeError;

  @override
  Future<Result<List<UserId>>> waitingByParticipation({
    required DateTime monthStart,
    required int minActiveDays,
  }) async {
    askedMinDays = minActiveDays;
    return Result.ok(waiting);
  }

  @override
  Future<Result<int>> addGroups({
    required DateTime monthStart,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) async {
    final failure = writeError;
    if (failure != null) {
      return Result.err(failure);
    }
    written.addAll(groups);
    var seats = 0;
    for (final g in groups) {
      seats += g.group.seats.length;
    }
    return Result.ok(seats);
  }
}

/// Settings and the admin log; nothing else is reached.
final class _Controls implements H2hControlStore {
  H2hSettings knobs = H2hSettings.defaults;
  final List<(H2hAdminActionKind, Map<String, Object?>)> log = [];

  @override
  Future<Result<H2hSettings>> settings() async => Result.ok(knobs);

  @override
  Future<Result<void>> record({
    required String id,
    required H2hAdminActionKind action,
    required UserId? by,
    required Map<String, Object?> detail,
  }) async {
    log.add((action, detail));
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveSettings({
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
    required UserId by,
  }) => throw UnimplementedError();

  @override
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  }) => throw UnimplementedError();

  @override
  Future<Result<bool>> exclude({required DateTime day, required UserId by}) =>
      throw UnimplementedError();

  @override
  Future<Result<bool>> include(DateTime day) => throw UnimplementedError();

  @override
  Future<Result<void>> addSeat({
    required H2hLeagueId leagueId,
    required DateTime monthStart,
    required UserId userId,
    required int slot,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<H2hAdminAction>>> recentActions(int limit) =>
      throw UnimplementedError();
}

/// October drawn as the pilot, with one first-division group of twenty.
Future<FakeH2hLeagueStore> _drawnOctober() async {
  final leagues = FakeH2hLeagueStore();
  await leagues.draw(
    monthStart: _october,
    isPilot: true,
    groups: [
      H2hDrawnGroup(
        leagueId: const H2hLeagueId('11111111-1111-4111-8111-111111111111'),
        group: H2hDrawGroup(
          division: H2hDivision.first,
          groupIndex: 0,
          seats: [
            for (final (i, u) in _players(20, from: 900).indexed)
              H2hDrawSeat(userId: u, slot: i),
          ],
        ),
      ),
    ],
    capacity: H2hLeaguePolicy.groupCapacity,
  );
  return leagues;
}

AddH2hGroups _useCase(
  FakeH2hLeagueStore leagues,
  _Extension extension,
  _Controls controls,
) => AddH2hGroups(
  leagues: leagues,
  extension: extension,
  controls: controls,
  idGenerator: SequenceIds(),
  clock: AtClock(_now),
);

void main() {
  test('three groups after the first: second, third and open', () async {
    final leagues = await _drawnOctober();
    final extension = _Extension(_players(72));
    final controls = _Controls();

    final result = await _useCase(leagues, extension, controls)(
      principal: _admin,
      groups: 3,
    );

    final added = (result as Ok<H2hGroupsAdded>).value;
    expect(added.monthStart, _october);
    expect(added.seats, 60);
    expect(added.waiting, 12);
    expect(
      [for (final g in added.groups) g.group.division],
      [H2hDivision.second, H2hDivision.third, H2hDivision.fourth],
    );
    expect(extension.written, hasLength(3));
    expect(extension.written.first.group.seats.first.userId, _players(1).first);
    expect(extension.askedMinDays, H2hLeaguePolicy.minActiveDays);

    final (action, detail) = controls.log.single;
    expect(action, H2hAdminActionKind.groupsAdded);
    expect(detail['month'], '2026-10-01');
    expect(detail['groups'], 3);
    expect(detail['seats'], 60);
  });

  test("the settings' active days decide who waits", () async {
    final leagues = await _drawnOctober();
    final extension = _Extension(_players(30));
    final controls = _Controls()
      ..knobs = const H2hSettings(
        autoApprove: true,
        leadHours: 24,
        minActiveDays: 3,
      );

    await _useCase(leagues, extension, controls)(principal: _admin, groups: 1);

    expect(extension.askedMinDays, 3);
  });

  test('a player is refused', () async {
    final result = await _useCase(
      await _drawnOctober(),
      _Extension(_players(40)),
      _Controls(),
    )(principal: _player, groups: 1);

    expect((result as Err<H2hGroupsAdded>).error.kind, ErrorKind.authorization);
  });

  test('zero or eleven groups are out of range', () async {
    for (final groups in [0, 11]) {
      final result = await _useCase(
        await _drawnOctober(),
        _Extension(_players(40)),
        _Controls(),
      )(principal: _admin, groups: groups);

      expect(
        (result as Err<H2hGroupsAdded>).error.code,
        'h2h.groups_out_of_range',
      );
    }
  });

  test('a month not drawn is refused', () async {
    final result = await _useCase(
      FakeH2hLeagueStore(),
      _Extension(_players(40)),
      _Controls(),
    )(principal: _admin, groups: 1);

    expect((result as Err<H2hGroupsAdded>).error.code, 'h2h.month_not_drawn');
  });

  test('a judged month is refused', () async {
    final leagues = await _drawnOctober();
    leagues.closed[_october] = 20;

    final result = await _useCase(
      leagues,
      _Extension(_players(40)),
      _Controls(),
    )(principal: _admin, groups: 1);

    expect((result as Err<H2hGroupsAdded>).error.code, 'h2h.month_closed');
  });

  test('fewer than two waiting is refused, nothing written', () async {
    final extension = _Extension(_players(1));
    final controls = _Controls();

    final result = await _useCase(await _drawnOctober(), extension, controls)(
      principal: _admin,
      groups: 2,
    );

    expect((result as Err<H2hGroupsAdded>).error.code, 'h2h.groups_no_players');
    expect(extension.written, isEmpty);
    expect(controls.log, isEmpty);
  });

  test('a refused write is answered and not logged', () async {
    final extension = _Extension(_players(40))
      ..writeError = const AppError.invariant('h2h.player_seated', 'seated');
    final controls = _Controls();

    final result = await _useCase(await _drawnOctober(), extension, controls)(
      principal: _admin,
      groups: 2,
    );

    expect((result as Err<H2hGroupsAdded>).error.code, 'h2h.player_seated');
    expect(controls.log, isEmpty);
  });
}
