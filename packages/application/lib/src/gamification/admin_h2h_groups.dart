/// Admin use-cases that read the head-to-head league as a whole (migration
/// 0100): every group of a month with its table, every match of a round in
/// any group, and the month as one player sees it. They read; they change
/// nothing, and no prediction of anybody is read.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/get_my_h2h_group_round.dart';
import 'package:application/src/gamification/get_my_h2h_league.dart';
import 'package:application/src/gamification/get_my_h2h_month.dart';
import 'package:application/src/gamification/h2h_group_pairs.dart';
import 'package:application/src/gamification/h2h_round_phase.dart';
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One group of the month as an admin sees it.
final class H2hAdminGroup {
  /// Creates a group reading.
  const H2hAdminGroup({
    required this.ref,
    required this.members,
    required this.placings,
    required this.promotionZone,
    required this.relegationZone,
  });

  /// The group.
  final H2hGroupRef ref;

  /// Its seats, suspended members left out (their seat plays the average).
  final List<H2hMember> members;

  /// The table over the settled rounds, best first.
  final List<H2hPlacing> placings;

  /// How many places from the top go up if the month ended now.
  final int promotionZone;

  /// How many places from the bottom go down if the month ended now.
  final int relegationZone;
}

/// Every group of a month.
final class H2hAdminMonth {
  /// Creates the reading.
  const H2hAdminMonth({
    required this.monthStart,
    required this.info,
    required this.rounds,
    required this.groups,
    required this.profiles,
  });

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// The month row, or null when it was not drawn.
  final H2hMonthInfo? info;

  /// The approved rounds of the month, in order.
  final List<H2hRound> rounds;

  /// The groups, by division then index.
  final List<H2hAdminGroup> groups;

  /// The name and picture version of every member.
  final Map<UserId, WeeklyLeagueMemberProfile> profiles;
}

/// Every match of one round in one group, as an admin sees it.
final class H2hAdminGroupRound {
  /// Creates the reading.
  const H2hAdminGroupRound({
    required this.round,
    required this.phase,
    required this.pairs,
    required this.profiles,
  });

  /// The round.
  final H2hRound round;

  /// Its phase in the month.
  final H2hRoundPhase phase;

  /// The matches, by seat.
  final List<H2hGroupPair> pairs;

  /// The name and picture version of each member.
  final Map<UserId, WeeklyLeagueMemberProfile> profiles;
}

/// The month and group behind an admin read.
DateTime _monthOf(DateTime? day, Clock clock) =>
    H2hLeaguePolicy.monthStartOf(day ?? riyadhDayOf(clock.nowUtc()));

/// Where a locked or unlocked round stands, from a group's sheet.
H2hRoundStatus _statusOf(H2hRound round, H2hGroupSheet sheet) {
  if (!round.locked) {
    return H2hRoundStatus.upcoming;
  }
  if (sheet.voidRounds.contains(round.number)) {
    return H2hRoundStatus.voided;
  }
  if (sheet.settledRounds.contains(round.number)) {
    return H2hRoundStatus.settled;
  }
  return H2hRoundStatus.live;
}

/// Reads every group of the month containing `day` (the current Riyadh
/// month when null): members, tables over the settled rounds, zones.
/// Admin only. Never throws.
final class AdminGetH2hGroups {
  /// Creates the use-case over its collaborators.
  const AdminGetH2hGroups({
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hSheetReader sheets,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _profiles = profiles,
       _clock = clock;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads the month for [principal], who must be an admin.
  Future<Result<H2hAdminMonth>> call({
    required AuthenticatedUser principal,
    DateTime? day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final month = _monthOf(day, _clock);

    final infoResult = await _leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    final rounds = (roundsResult as Ok<List<H2hRound>>).value;
    final refsResult = await _leagues.groupsOf(month);
    if (refsResult is Err<List<H2hGroupRef>>) {
      return Result.err(refsResult.error);
    }
    final refs =
        List<H2hGroupRef>.of((refsResult as Ok<List<H2hGroupRef>>).value)..sort(
          (a, b) => a.division.level != b.division.level
              ? a.division.level.compareTo(b.division.level)
              : a.groupIndex.compareTo(b.groupIndex),
        );

    final groupsPerDivision = <H2hDivision, int>{};
    for (final ref in refs) {
      groupsPerDivision[ref.division] =
          (groupsPerDivision[ref.division] ?? 0) + 1;
    }

    final groups = <H2hAdminGroup>[];
    final everyone = <UserId>[];
    for (final ref in refs) {
      final sheetResult = await _sheets.sheetOf(
        leagueId: ref.leagueId,
        rounds: rounds,
      );
      if (sheetResult is Err<H2hGroupSheet>) {
        return Result.err(sheetResult.error);
      }
      final sheet = (sheetResult as Ok<H2hGroupSheet>).value;
      final settled = <H2hRoundRef>[
        for (final round in rounds)
          if (_statusOf(round, sheet) == H2hRoundStatus.settled) round.ref,
      ];
      final size = sheet.members.length;
      final single = H2hLeaguePolicy.promotionCount(ref.division, size);
      final divisionGroups = groupsPerDivision[ref.division] ?? 1;
      final certain = H2hLeaguePolicy.maxMovement ~/ divisionGroups;
      groups.add(
        H2hAdminGroup(
          ref: ref,
          members: sheet.members,
          placings: H2hLeaguePolicy.order(
            H2hLeaguePolicy.table(
              capacity: ref.capacity,
              members: sheet.members,
              rounds: settled,
              scores: sheet.scores,
            ),
          ),
          promotionZone: divisionGroups <= 1
              ? single
              : (certain < single ? certain : single),
          relegationZone: H2hLeaguePolicy.relegationCount(ref.division, size),
        ),
      );
      everyone.addAll([for (final m in sheet.members) m.userId]);
    }

    final profilesResult = await _profiles.profilesOf(everyone);
    if (profilesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profilesResult.error);
    }
    return Result.ok(
      H2hAdminMonth(
        monthStart: month,
        info: (infoResult as Ok<H2hMonthInfo?>).value,
        rounds: rounds,
        groups: List<H2hAdminGroup>.unmodifiable(groups),
        profiles: (profilesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>)
            .value,
      ),
    );
  }
}

/// Reads every match of round `round` in group `leagueId` of the month
/// containing `day`. Admin only. Never throws; a group or round the month
/// does not have is `h2h.group_unknown` / `h2h.round_unknown`.
final class AdminGetH2hGroupRound {
  /// Creates the use-case over its collaborators.
  const AdminGetH2hGroupRound({
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hSheetReader sheets,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _profiles = profiles,
       _clock = clock;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads the round for [principal], who must be an admin.
  Future<Result<H2hAdminGroupRound>> call({
    required AuthenticatedUser principal,
    required H2hLeagueId leagueId,
    required int round,
    DateTime? day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final month = _monthOf(day, _clock);

    final refsResult = await _leagues.groupsOf(month);
    if (refsResult is Err<List<H2hGroupRef>>) {
      return Result.err(refsResult.error);
    }
    H2hGroupRef? ref;
    for (final candidate in (refsResult as Ok<List<H2hGroupRef>>).value) {
      if (candidate.leagueId == leagueId) {
        ref = candidate;
        break;
      }
    }
    if (ref == null) {
      return const Result.err(
        AppError.invariant('h2h.group_unknown', 'The month has no such group'),
      );
    }

    final roundsResult = await _rounds.roundsOf(month);
    if (roundsResult is Err<List<H2hRound>>) {
      return Result.err(roundsResult.error);
    }
    final rounds = (roundsResult as Ok<List<H2hRound>>).value;
    H2hRound? target;
    for (final candidate in rounds) {
      if (candidate.number == round) {
        target = candidate;
        break;
      }
    }
    if (target == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_unknown',
          'The month has no round with this number',
        ),
      );
    }

    final sheetResult = await _sheets.sheetOf(
      leagueId: ref.leagueId,
      rounds: rounds,
    );
    if (sheetResult is Err<H2hGroupSheet>) {
      return Result.err(sheetResult.error);
    }
    final sheet = (sheetResult as Ok<H2hGroupSheet>).value;

    final profilesResult = await _profiles.profilesOf([
      for (final m in sheet.members) m.userId,
    ]);
    if (profilesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profilesResult.error);
    }

    // The phase the players see: the server's state, `open` for the first
    // round not started.
    final views = <MyH2hRound>[
      for (final r in rounds)
        MyH2hRound(
          round: r,
          status: _statusOf(r, sheet),
          opponentId: null,
          match: null,
        ),
    ];
    return Result.ok(
      H2hAdminGroupRound(
        round: target,
        phase: h2hRoundPhasesOf(views)[target.number]!,
        pairs: h2hGroupPairs(
          members: sheet.members,
          capacity: ref.capacity,
          round: target.ref,
          status: _statusOf(target, sheet),
          scores: sheet.scores,
        ),
        profiles: (profilesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>)
            .value,
      ),
    );
  }
}

/// Reads the current month exactly as player `userId` sees it -- the same
/// reading [GetMyH2hMonth] makes for them: their seat, table, rounds,
/// opponents and points. Admin only. Never throws.
final class AdminGetH2hPlayer {
  /// Creates the use-case over the players' own reading.
  const AdminGetH2hPlayer({required GetMyH2hMonth month}) : _month = month;

  final GetMyH2hMonth _month;

  /// Reads [userId]'s month for [principal], who must be an admin.
  Future<Result<MyH2hMonth>> call({
    required AuthenticatedUser principal,
    required UserId userId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _month(
      principal: AuthenticatedUser(userId: userId, role: PlatformRole.user),
    );
  }
}
