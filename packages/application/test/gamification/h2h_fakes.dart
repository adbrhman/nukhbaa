import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Ids `00000000-0000-4000-8000-000000000001`, `...002`, ... in order.
final class SequenceIds implements IdGenerator {
  int _next = 0;

  @override
  String newUuid() {
    _next++;
    return '00000000-0000-4000-8000-${_next.toString().padLeft(12, '0')}';
  }
}

/// A fixed instant.
final class AtClock implements Clock {
  AtClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// In-memory [H2hLeagueStore].
final class FakeH2hLeagueStore implements H2hLeagueStore {
  final Map<DateTime, H2hMonthInfo> months = <DateTime, H2hMonthInfo>{};
  final Map<DateTime, int> closed = <DateTime, int>{};
  final Map<DateTime, List<H2hDrawnGroup>> drawn =
      <DateTime, List<H2hDrawnGroup>>{};
  final Map<String, H2hSeat> seats = <String, H2hSeat>{};
  int drawCalls = 0;
  AppError? failWith;

  static String _key(UserId userId, DateTime month) =>
      '${userId.value}|${month.toIso8601String()}';

  /// Seats [userId] directly, for reads that need a seat but no draw.
  void seat(UserId userId, H2hSeat seat) {
    seats[_key(userId, seat.monthStart)] = seat;
  }

  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(months[monthStart]);
  }

  @override
  Future<Result<bool>> isClosed(DateTime monthStart) async =>
      Result.ok(closed.containsKey(monthStart));

  @override
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) async {
    drawCalls++;
    if (months.containsKey(monthStart)) {
      return const Result.ok(0);
    }
    var count = 0;
    for (final drawnGroup in groups) {
      final group = drawnGroup.group;
      final divisionGroups = groups
          .where((g) => g.group.division == group.division)
          .length;
      for (final s in group.seats) {
        seats[_key(s.userId, monthStart)] = H2hSeat(
          leagueId: drawnGroup.leagueId,
          monthStart: monthStart,
          division: group.division,
          groupIndex: group.groupIndex,
          slot: s.slot,
          capacity: capacity,
          divisionGroups: divisionGroups,
          isPilot: isPilot,
          joinedAt: monthStart,
        );
        count++;
      }
    }
    drawn[monthStart] = List<H2hDrawnGroup>.of(groups);
    months[monthStart] = H2hMonthInfo(
      monthStart: monthStart,
      isPilot: isPilot,
      seatedCount: count,
    );
    return Result.ok(count);
  }

  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) async => Result.ok(seats[_key(userId, monthStart)]);

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) async =>
      Result.ok([
        for (final g in drawn[monthStart] ?? const <H2hDrawnGroup>[])
          H2hGroupRef(
            leagueId: g.leagueId,
            division: g.group.division,
            groupIndex: g.group.groupIndex,
            capacity: H2hLeaguePolicy.groupCapacity,
          ),
      ]);

  @override
  Future<Result<DateTime?>> nextUnclosedMonth() async {
    final open = months.keys.where((m) => !closed.containsKey(m)).toList()
      ..sort();
    return Result.ok(open.isEmpty ? null : open.first);
  }

  @override
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  }) async {
    closed[monthStart] = memberCount;
    return const Result.ok(null);
  }
}

/// In-memory [H2hRoundStore].
final class FakeH2hRoundStore implements H2hRoundStore {
  final Map<DateTime, List<H2hRound>> byMonth = <DateTime, List<H2hRound>>{};
  final Map<DateTime, H2hDayFixtures> days = <DateTime, H2hDayFixtures>{};
  final List<H2hRoundId> lockCalls = <H2hRoundId>[];
  final List<H2hRoundId> withdrawCalls = <H2hRoundId>[];

  /// Declares [fixtures] fixtures on [day], the first at [firstKickoff].
  void dayOf(DateTime day, int fixtures, DateTime? firstKickoff) {
    days[day] = H2hDayFixtures(
      day: day,
      fixtureCount: fixtures,
      firstKickoff: firstKickoff,
    );
  }

  /// Adds an approved round directly.
  void addRound(H2hRound round) {
    (byMonth[round.monthStart] ??= <H2hRound>[]).add(round);
  }

  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async =>
      Result.ok(List<H2hRound>.of(byMonth[monthStart] ?? const <H2hRound>[]));

  @override
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day) async => Result.ok(
    days[day] ?? H2hDayFixtures(day: day, fixtureCount: 0, firstKickoff: null),
  );

  @override
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  }) async {
    final list =
        days.values
            .where(
              (d) =>
                  d.fixtureCount > 0 &&
                  !d.day.isBefore(from) &&
                  !d.day.isAfter(through),
            )
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));
    return Result.ok(list);
  }

  @override
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  }) async {
    addRound(
      H2hRound(
        id: id,
        monthStart: monthStart,
        number: number,
        day: day,
        fixtureCount: fixtureCount,
        approvedBy: approvedBy,
        lockedAt: null,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> withdraw(H2hRoundId roundId) async {
    withdrawCalls.add(roundId);
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  }) async {
    lockCalls.add(roundId);
    for (final list in byMonth.values) {
      for (var i = 0; i < list.length; i++) {
        final r = list[i];
        if (r.id == roundId) {
          list[i] = H2hRound(
            id: r.id,
            monthStart: r.monthStart,
            number: r.number,
            day: r.day,
            fixtureCount: r.fixtureCount,
            approvedBy: r.approvedBy,
            lockedAt: DateTime.utc(2000),
          );
        }
      }
    }
    return Result.ok(days[day]?.fixtureCount ?? 0);
  }
}

/// Scripted [H2hDrawSource].
final class FakeH2hDrawSource implements H2hDrawSource {
  final Map<DateTime, List<UserId>> active = <DateTime, List<UserId>>{};
  final Map<DateTime, List<H2hCarry>> carried = <DateTime, List<H2hCarry>>{};
  List<UserId> pilot = <UserId>[];
  final List<DateTime> carriedAsked = <DateTime>[];

  @override
  Future<Result<List<UserId>>> activeOrder({
    required DateTime monthStart,
    required int minActiveDays,
  }) async => Result.ok(active[monthStart] ?? const <UserId>[]);

  @override
  Future<Result<List<H2hCarry>>> carriedFrom(DateTime monthStart) async {
    carriedAsked.add(monthStart);
    return Result.ok(carried[monthStart] ?? const <H2hCarry>[]);
  }

  @override
  Future<Result<List<UserId>>> pilotOrder(DateTime monthStart) async =>
      Result.ok(pilot);
}

/// Scripted [H2hSheetReader].
final class FakeH2hSheetReader implements H2hSheetReader {
  final Map<H2hLeagueId, H2hGroupSheet> sheets = <H2hLeagueId, H2hGroupSheet>{};
  final Map<UserId, int> activeDays = <UserId, int>{};

  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async => Result.ok(
    sheets[leagueId] ??
        const H2hGroupSheet(
          members: <H2hMember>[],
          scores: <H2hRoundScore>[],
          settledRounds: <int>{},
          voidRounds: <int>{},
        ),
  );

  @override
  Future<Result<Map<UserId, int>>> activeDaysOf(DateTime monthStart) async =>
      Result.ok(Map<UserId, int>.of(activeDays));
}

/// Records events; fails from the [failFrom]-th record on, when set.
final class RecordingEvents implements GamificationEventSink {
  RecordingEvents({this.failFrom});

  final int? failFrom;
  final List<GamificationEvent> recorded = <GamificationEvent>[];

  @override
  Future<Result<void>> record(GamificationEvent event) async {
    final limit = failFrom;
    if (limit != null && recorded.length >= limit) {
      return const Result.err(
        AppError.transient('test.sink_down', 'sink down'),
      );
    }
    recorded.add(event);
    return const Result.ok(null);
  }
}

/// Names every user it is asked about after their id.
final class NamingProfiles implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final id in userIds)
      id: WeeklyLeagueMemberProfile(displayName: 'name ${id.value}'),
  });
}

/// A canonical user id numbered [n].
UserId userNo(int n) =>
    UserId('00000000-0000-4000-9000-${n.toString().padLeft(12, '0')}');

/// The admin and the player principals.
const admin = AuthenticatedUser(
  userId: UserId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  role: PlatformRole.admin,
);

/// A plain player.
const player = AuthenticatedUser(
  userId: UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  role: PlatformRole.user,
);
