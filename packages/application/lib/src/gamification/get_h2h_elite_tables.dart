/// Use-case: the tables of the four elite groups of the head-to-head league
/// (2026-11-08), read by any player. The player's own league shows only the
/// player's group; the elite groups are the month's showcase, so every
/// player may see all four (names, records and points -- never a match
/// still secret, never a prediction).
library;

import 'package:application/src/gamification/admin_h2h_groups.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the elite groups of the current month.
///
/// It adds no ranking of its own: the tables are [AdminGetH2hGroups]'s
/// (the same ones the admin reads), narrowed to the elite division and to
/// the months drawn by the elite draw. A month that is not drawn, is a
/// hidden pilot, or predates the elite draw has no elite groups: the result
/// is then a month with an empty `groups`.
///
/// Never throws; returns a typed [Result].
final class GetH2hEliteTables {
  /// Creates the use-case over the admin reading it narrows.
  const GetH2hEliteTables({required AdminGetH2hGroups groups})
    : _groups = groups;

  final AdminGetH2hGroups _groups;

  /// Reads the current month's elite groups for [principal], any player.
  Future<Result<H2hAdminMonth>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final read = await _groups.readMonth();
    if (read is Err<H2hAdminMonth>) {
      return Result.err(read.error);
    }
    final month = (read as Ok<H2hAdminMonth>).value;
    final info = month.info;
    final shown =
        info != null &&
        !info.isPilot &&
        H2hLeaguePolicy.usesEliteDraw(month.monthStart);
    final elite = <H2hAdminGroup>[
      if (shown)
        for (final group in month.groups)
          if (group.ref.division == H2hLeaguePolicy.eliteDivision) group,
    ];
    final seated = <UserId>{
      for (final group in elite)
        for (final member in group.members) member.userId,
    };
    return Result.ok(
      H2hAdminMonth(
        monthStart: month.monthStart,
        info: info,
        rounds: const [],
        groups: List<H2hAdminGroup>.unmodifiable(elite),
        profiles: <UserId, WeeklyLeagueMemberProfile>{
          for (final entry in month.profiles.entries)
            if (seated.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
  }
}
