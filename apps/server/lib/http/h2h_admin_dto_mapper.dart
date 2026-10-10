/// Projects the admin's readings of the head-to-head league onto their wire
/// shapes (migrations 0100/0101), in one place: every group of a month,
/// every match of a round in one group, the controls, the month report and
/// a manual run of the jobs.
///
/// Integrity boundary (Axioms 2/5): every number here is server-produced
/// and echoed as the policy and the stores produced it. No prediction of
/// anybody is read or sent.
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';
import 'package:server/http/avatar_url.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';

/// Every group of a month as `GET /admin/h2h/groups` sends it.
H2hAdminGroupsDto h2hAdminGroupsToDto(H2hAdminMonth month) {
  final info = month.info;
  return H2hAdminGroupsDto(
    monthStart: isoDayOf(month.monthStart),
    drawn: info != null,
    isPilot: info?.isPilot ?? false,
    seatedCount: info?.seatedCount ?? 0,
    rounds: [for (final round in month.rounds) h2hRoundToDto(round)],
    groups: [
      for (final group in month.groups) _groupToDto(group, month.profiles),
    ],
  );
}

H2hAdminGroupDto _groupToDto(
  H2hAdminGroup group,
  Map<UserId, WeeklyLeagueMemberProfile> profiles,
) {
  final taken = <int>{for (final member in group.members) member.slot};
  return H2hAdminGroupDto(
    leagueId: group.ref.leagueId.value,
    division: group.ref.division.level,
    groupIndex: group.ref.groupIndex,
    capacity: group.ref.capacity,
    promotionZone: group.promotionZone,
    relegationZone: group.relegationZone,
    standings: [
      for (final placing in group.placings) _standingToDto(placing, profiles),
    ],
    freeSlots: [
      for (var slot = 0; slot < group.ref.capacity; slot++)
        if (!taken.contains(slot)) slot,
    ],
  );
}

H2hStandingDto _standingToDto(
  H2hPlacing placing,
  Map<UserId, WeeklyLeagueMemberProfile> profiles,
) {
  final standing = placing.standing;
  final matches = [...standing.matches]
    ..sort((a, b) => a.round.compareTo(b.round));
  final recent = matches.length > h2hFormLength
      ? matches.sublist(matches.length - h2hFormLength)
      : matches;
  return H2hStandingDto(
    rank: placing.rank,
    userId: standing.userId.value,
    displayName: profiles[standing.userId]?.displayName ?? '',
    played: standing.played,
    won: standing.won,
    drawn: standing.drawn,
    lost: standing.lost,
    leaguePoints: standing.leaguePoints,
    pointsFor: standing.pointsFor,
    exactCount: standing.exactCount,
    form: [for (final match in recent) match.result.wireName],
    isMe: false,
    avatarUrl: _avatarOf(standing.userId, profiles),
  );
}

/// Every match of one round in one group as
/// `GET /admin/h2h/groups/{id}/rounds/{n}` sends it: names, pictures and
/// stored points only.
H2hGroupRoundDto h2hAdminGroupRoundToDto(H2hAdminGroupRound group) =>
    H2hGroupRoundDto(
      round: group.round.number,
      day: isoDayOf(group.round.day),
      status: group.phase.name,
      matches: [
        for (final pair in group.pairs)
          H2hGroupMatchDto(
            homeUserId: pair.home.value,
            homeName: group.profiles[pair.home]?.displayName ?? '',
            homeAvatarUrl: _avatarOf(pair.home, group.profiles),
            homePoints: pair.homePoints,
            awayUserId: pair.away?.value,
            awayName: pair.away == null
                ? null
                : group.profiles[pair.away]?.displayName ?? '',
            awayAvatarUrl: pair.away == null
                ? null
                : _avatarOf(pair.away!, group.profiles),
            awayPoints: pair.awayPoints,
            winner: pair.winner?.wireName,
          ),
      ],
    );

/// The settings as the controls and `PUT /admin/h2h/settings` send them.
H2hSettingsDto h2hSettingsToDto(
  H2hSettings settings, {
  Map<UserId, String> names = const <UserId, String>{},
}) {
  final by = settings.updatedBy;
  return H2hSettingsDto(
    autoApprove: settings.autoApprove,
    leadHours: settings.leadHours,
    minActiveDays: settings.minActiveDays,
    leadHoursMin: H2hSettings.minLeadHours,
    leadHoursMax: H2hSettings.maxLeadHours,
    minActiveDaysMin: H2hSettings.minActiveDaysFloor,
    minActiveDaysMax: H2hSettings.minActiveDaysCeiling,
    updatedByName: by == null ? null : names[by] ?? '',
    updatedAt: settings.updatedAt?.toUtc().toIso8601String(),
  );
}

/// The controls of a month as `GET /admin/h2h/controls` sends them.
H2hControlsDto h2hControlsToDto(H2hControlsView view) => H2hControlsDto(
  monthStart: isoDayOf(view.monthStart),
  settings: h2hSettingsToDto(view.settings, names: view.names),
  days: [
    for (final day in view.days)
      H2hControlDayDto(
        day: isoDayOf(day.fixtures.day),
        fixtureCount: day.fixtures.fixtureCount,
        excluded: day.excluded,
        firstKickoff: day.fixtures.firstKickoff?.toUtc().toIso8601String(),
        round: day.round,
      ),
  ],
  actions: [
    for (final action in view.actions)
      H2hAdminActionDto(
        id: action.id,
        action: action.action.wireName,
        detail: action.detail,
        actedAt: action.actedAt.toUtc().toIso8601String(),
        actorId: action.actor?.value,
        actorName: action.actor == null ? null : view.names[action.actor] ?? '',
      ),
  ],
);

/// How a month went as `GET /admin/h2h/report` sends it.
H2hMonthReportDto h2hMonthReportToDto(H2hMonthReport report) =>
    H2hMonthReportDto(
      monthStart: isoDayOf(report.monthStart),
      drawn: report.drawnAt != null,
      isPilot: report.isPilot,
      drawnSeats: report.drawnSeats,
      seats: report.seats,
      groupsByDivision: <String, int>{
        for (final entry in report.groupsByDivision.entries)
          '${entry.key}': entry.value,
      },
      closed: report.closedAt != null,
      closedMembers: report.closedMembers,
      outcomes: Map<String, int>.of(report.outcomes),
      drawnAt: report.drawnAt?.toUtc().toIso8601String(),
      closedAt: report.closedAt?.toUtc().toIso8601String(),
    );

/// A manual run of the jobs as `POST /admin/h2h/jobs` sends it.
H2hJobsRunDto h2hJobsRunToDto(H2hJobsRun run) => H2hJobsRunDto(
  approved: run.approved,
  locked: run.locked,
  closedMonths: run.closedMonths,
  drawnSeats: run.drawnSeats,
);

String? _avatarOf(
  UserId userId,
  Map<UserId, WeeklyLeagueMemberProfile> profiles,
) {
  final updatedAt = profiles[userId]?.avatarUpdatedAt;
  if (updatedAt == null) {
    return null;
  }
  return avatarUrlOf(userId: userId, updatedAt: updatedAt);
}
