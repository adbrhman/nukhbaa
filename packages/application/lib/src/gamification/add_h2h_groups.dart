import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_group_extension.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What [AddH2hGroups] opened.
final class H2hGroupsAdded {
  /// Creates the outcome.
  const H2hGroupsAdded({
    required this.monthStart,
    required this.groups,
    required this.seats,
    required this.waiting,
  });

  /// The month the groups were added to.
  final DateTime monthStart;

  /// The new groups, each with its id and seats, in the order opened.
  final List<H2hDrawnGroup> groups;

  /// Seats handed out.
  final int seats;

  /// Players who qualified and are still without a seat.
  final int waiting;
}

/// Use-case: an admin adds groups to the head-to-head month open now
/// (decided 2026-10-11, when the pilot of October grew from one group to
/// four).
///
/// **Who.** The players with no seat this month who predicted on the
/// settings' `min_active_days` (five by default) of its days, the most days
/// first, then the most points: those who play the most get a seat first.
///
/// **Where.** `H2hLeaguePolicy.extend`: twenty to a group, into each
/// division above the open one that has no group yet, top down, then new
/// groups of the open division. The schedule is the slot's and the rounds
/// are the month's, so a new group plays every round of the month, the ones
/// already played included, from its members' own predictions.
///
/// **When.** The month must be drawn (`h2h.month_not_drawn`) and not judged
/// (`h2h.month_closed`); one to [maxGroups] groups at a time
/// (`h2h.groups_out_of_range`); at least two players waiting
/// (`h2h.groups_no_players`). The groups are written together or not at
/// all, and the addition goes to the admin log.
///
/// Never throws; returns a typed [Result].
final class AddH2hGroups {
  /// Creates the use-case over its collaborators.
  const AddH2hGroups({
    required H2hLeagueStore leagues,
    required H2hGroupExtension extension,
    required H2hControlStore controls,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _leagues = leagues,
       _extension = extension,
       _controls = controls,
       _ids = idGenerator,
       _clock = clock;

  final H2hLeagueStore _leagues;
  final H2hGroupExtension _extension;
  final H2hControlStore _controls;
  final IdGenerator _ids;
  final Clock _clock;

  /// The most groups one request may open.
  static const int maxGroups = 10;

  /// Opens up to [groups] new groups this month for [principal], an admin.
  Future<Result<H2hGroupsAdded>> call({
    required AuthenticatedUser principal,
    required int groups,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (groups < 1 || groups > maxGroups) {
      return const Result.err(
        AppError.validation(
          'h2h.groups_out_of_range',
          'Add between one and ten groups at a time',
        ),
      );
    }
    final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(_clock.nowUtc()));

    final infoResult = await _leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    if ((infoResult as Ok<H2hMonthInfo?>).value == null) {
      return const Result.err(
        AppError.invariant('h2h.month_not_drawn', 'The month was not drawn'),
      );
    }
    final closedResult = await _leagues.isClosed(month);
    if (closedResult is Err<bool>) {
      return Result.err(closedResult.error);
    }
    if ((closedResult as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant('h2h.month_closed', 'The month was already judged'),
      );
    }

    final settingsResult = await _controls.settings();
    if (settingsResult is Err<H2hSettings>) {
      return Result.err(settingsResult.error);
    }
    final minActiveDays =
        (settingsResult as Ok<H2hSettings>).value.minActiveDays;

    final waitingResult = await _extension.waitingByParticipation(
      monthStart: month,
      minActiveDays: minActiveDays,
    );
    if (waitingResult is Err<List<UserId>>) {
      return Result.err(waitingResult.error);
    }
    final waiting = (waitingResult as Ok<List<UserId>>).value;

    final refsResult = await _leagues.groupsOf(month);
    if (refsResult is Err<List<H2hGroupRef>>) {
      return Result.err(refsResult.error);
    }
    final planned = H2hLeaguePolicy.extend(
      existing: [
        for (final ref in (refsResult as Ok<List<H2hGroupRef>>).value)
          (division: ref.division, groupIndex: ref.groupIndex),
      ],
      order: waiting,
      groups: groups,
    );
    if (planned.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'h2h.groups_no_players',
          'Fewer than two qualified players are waiting for a seat',
        ),
      );
    }

    final drawn = <H2hDrawnGroup>[];
    for (final group in planned) {
      final idResult = H2hLeagueId.tryParse(_ids.newUuid());
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

    final addedResult = await _extension.addGroups(
      monthStart: month,
      groups: drawn,
      capacity: H2hLeaguePolicy.groupCapacity,
    );
    if (addedResult is Err<int>) {
      return Result.err(addedResult.error);
    }
    final seats = (addedResult as Ok<int>).value;

    await _controls.record(
      id: _ids.newUuid(),
      action: H2hAdminActionKind.groupsAdded,
      by: principal.userId,
      detail: {
        'month': _isoDay(month),
        'groups': drawn.length,
        'seats': seats,
        'min_active_days': minActiveDays,
        'added': [
          for (final d in drawn)
            {
              'league_id': d.leagueId.value,
              'division': d.group.division.level,
              'group_index': d.group.groupIndex,
              'seats': d.group.seats.length,
            },
        ],
      },
    );

    return Result.ok(
      H2hGroupsAdded(
        monthStart: month,
        groups: List<H2hDrawnGroup>.unmodifiable(drawn),
        seats: seats,
        waiting: waiting.length - seats,
      ),
    );
  }

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
