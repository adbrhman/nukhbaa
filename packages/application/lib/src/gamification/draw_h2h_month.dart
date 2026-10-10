import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_draw_source.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: draws the head-to-head month that is open now (migration 0100).
///
/// **Once, on the month's first night.** The draw writes every group and
/// seat of the month and the month row in one transaction; a month that has
/// its row is never drawn again. Run by the scheduler after
/// `CloseH2hMonth`, so last month's standings exist before this month is
/// seated.
///
/// **Who.** The first public month (`H2hLeaguePolicy.firstMonth`), and any
/// month that follows a month with no draw or a pilot month, is SEEDED: the
/// players who predicted on five days of the month before, best points
/// first, cut twenty to a division. Every other month CARRIES: the members
/// last month's events sent on, in their next division, then the new
/// players who predicted on five days, at the end. A carrying month waits
/// until last month is judged; until then the run draws nothing.
///
/// **Before the league opens** nothing is drawn here: the pilot month is
/// started by an admin (`StartH2hPilot`).
///
/// **The admin's settings (0101)**, when [controls] is given: the days
/// of predictions that put a player into the draw are the settings'
/// `min_active_days` (five by default); unreadable settings draw nothing
/// and the next run tries again.
///
/// Never throws; returns a typed [Result] with the number of seats drawn.
final class DrawH2hMonth {
  /// Creates the use-case over its collaborators.
  const DrawH2hMonth({
    required H2hLeagueStore leagues,
    required H2hDrawSource source,
    required IdGenerator idGenerator,
    H2hControlStore? controls,
  }) : _leagues = leagues,
       _source = source,
       _ids = idGenerator,
       _controls = controls;

  final H2hLeagueStore _leagues;
  final H2hDrawSource _source;
  final IdGenerator _ids;
  final H2hControlStore? _controls;

  /// Draws the month containing [now] if it is due and not drawn yet.
  Future<Result<int>> call({required DateTime now}) async {
    final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(now));
    if (month.isBefore(H2hLeaguePolicy.firstMonth)) {
      return const Result.ok(0);
    }

    final drawnResult = await _leagues.monthOf(month);
    if (drawnResult is Err<H2hMonthInfo?>) {
      return Result.err(drawnResult.error);
    }
    if ((drawnResult as Ok<H2hMonthInfo?>).value != null) {
      return const Result.ok(0);
    }

    final previous = H2hLeaguePolicy.previousMonthOf(month);
    final previousResult = await _leagues.monthOf(previous);
    if (previousResult is Err<H2hMonthInfo?>) {
      return Result.err(previousResult.error);
    }
    final previousInfo = (previousResult as Ok<H2hMonthInfo?>).value;

    var minActiveDays = H2hLeaguePolicy.minActiveDays;
    final controls = _controls;
    if (controls != null) {
      final settings = await controls.settings();
      if (settings is Err<H2hSettings>) {
        return Result.err(settings.error);
      }
      minActiveDays = (settings as Ok<H2hSettings>).value.minActiveDays;
    }

    final activeResult = await _source.activeOrder(
      monthStart: previous,
      minActiveDays: minActiveDays,
    );
    if (activeResult is Err<List<UserId>>) {
      return Result.err(activeResult.error);
    }
    final active = (activeResult as Ok<List<UserId>>).value;

    final seeded =
        month == H2hLeaguePolicy.firstMonth ||
        previousInfo == null ||
        previousInfo.isPilot;

    final List<UserId> order;
    if (seeded) {
      order = active;
    } else {
      final closedResult = await _leagues.isClosed(previous);
      if (closedResult is Err<bool>) {
        return Result.err(closedResult.error);
      }
      if (!(closedResult as Ok<bool>).value) {
        // Last month is not judged yet: its standings decide this draw.
        return const Result.ok(0);
      }
      final carriedResult = await _source.carriedFrom(previous);
      if (carriedResult is Err<List<H2hCarry>>) {
        return Result.err(carriedResult.error);
      }
      final carried = List<H2hCarry>.of(
        (carriedResult as Ok<List<H2hCarry>>).value,
      )..sort(_compareCarry);
      final carriedIds = <UserId>{for (final c in carried) c.userId};
      order = <UserId>[
        for (final c in carried) c.userId,
        for (final userId in active)
          if (!carriedIds.contains(userId)) userId,
      ];
    }

    return drawInto(
      leagues: _leagues,
      ids: _ids,
      monthStart: month,
      isPilot: false,
      order: order,
    );
  }

  /// Cuts [order] into divisions, splits them into groups and stores them
  /// for [monthStart]. Shared with `StartH2hPilot`.
  static Future<Result<int>> drawInto({
    required H2hLeagueStore leagues,
    required IdGenerator ids,
    required DateTime monthStart,
    required bool isPilot,
    required List<UserId> order,
  }) async {
    final groups = H2hLeaguePolicy.draw(H2hLeaguePolicy.cut(order));
    final drawn = <H2hDrawnGroup>[];
    for (final group in groups) {
      final idResult = H2hLeagueId.tryParse(ids.newUuid());
      if (idResult is Err<H2hLeagueId>) {
        return Result.err(idResult.error);
      }
      drawn.add(
        H2hDrawnGroup(
          leagueId: (idResult as Ok<H2hLeagueId>).value,
          group: group,
        ),
      );
    }
    return leagues.draw(
      monthStart: monthStart,
      isPilot: isPilot,
      groups: drawn,
      capacity: H2hLeaguePolicy.groupCapacity,
    );
  }

  static int _compareCarry(H2hCarry a, H2hCarry b) {
    final byNext = a.nextDivision.level.compareTo(b.nextDivision.level);
    if (byNext != 0) {
      return byNext;
    }
    final byDivision = a.division.level.compareTo(b.division.level);
    if (byDivision != 0) {
      return byDivision;
    }
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) {
      return byRank;
    }
    return a.userId.value.compareTo(b.userId.value);
  }
}
