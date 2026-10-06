import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/fixture_totals_reader.dart';
import 'package:application/src/ledger/ports/participant_reader.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: a private group's month board -- the friends' league of
/// phase 2 of the plan. The same points and the same ranking rule as the
/// month's board (`GetSeasonFixtureLeaderboard`, from the per-fixture
/// scores), narrowed to the group's members and ranked among themselves,
/// so a friend's place here can never disagree with their points there.
///
/// Only a member of the group sees it, refused otherwise as
/// [ErrorKind.authorization] `group.not_a_member`, the same answer whether
/// or not the group exists. A member who has not scored this month is not
/// on it, as on the month's board. No movement arrows: the daily rank
/// snapshot is the whole month's.
///
/// Never throws; returns a typed [Result].
final class GetGroupMonthBoard {
  /// Creates the use-case over its collaborators.
  const GetGroupMonthBoard({
    required GroupRepository groups,
    required CompetitionRepository competition,
    required FixturePredictionRepository fixturePredictions,
    required FixtureTotalsReader totals,
    required ParticipantReader participants,
  }) : _groups = groups,
       _competition = competition,
       _fixturePredictions = fixturePredictions,
       _totals = totals,
       _participants = participants;

  final GroupRepository _groups;
  final CompetitionRepository _competition;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureTotalsReader _totals;
  final ParticipantReader _participants;

  /// [groupId]'s board for the month contest [seasonId].
  Future<Result<FixtureLeaderboard>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String seasonId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final groupResult = GroupId.tryParse(groupId);
    if (groupResult is Err<GroupId>) {
      return Result.err(groupResult.error);
    }
    final GroupId group = (groupResult as Ok<GroupId>).value;
    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) {
      return Result.err(seasonResult.error);
    }
    final SeasonId season = (seasonResult as Ok<SeasonId>).value;

    final membership = await _groups.findMembership(group, principal.userId);
    if (membership is Err<GroupMembership?>) {
      return Result.err(membership.error);
    }
    if ((membership as Ok<GroupMembership?>).value == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may view its leaderboard',
        ),
      );
    }

    final members = await _groups.listMemberships(group);
    if (members is Err<List<GroupMembership>>) {
      return Result.err(members.error);
    }
    final Set<String> inGroup = <String>{};
    for (final GroupMembership m
        in (members as Ok<List<GroupMembership>>).value) {
      final participant = await _competition.findParticipant(season, m.userId);
      if (participant is Err<Participant?>) {
        return Result.err(participant.error);
      }
      final Participant? p = (participant as Ok<Participant?>).value;
      if (p != null) inGroup.add(p.id.value);
    }

    final fixtures = await _fixturePredictions.listSeasonFixtures(season);
    if (fixtures is Err<List<FixtureRef>>) {
      return Result.err(fixtures.error);
    }
    final totalsResult = await _totals.totalsFor(
      (fixtures as Ok<List<FixtureRef>>).value,
    );
    if (totalsResult is Err<List<ParticipantFixtureTotals>>) {
      return Result.err(totalsResult.error);
    }
    final List<ParticipantFixtureTotals> totals = <ParticipantFixtureTotals>[
      for (final ParticipantFixtureTotals line
          in (totalsResult as Ok<List<ParticipantFixtureTotals>>).value)
        if (inGroup.contains(line.participantId.value)) line,
    ];

    final List<ParticipantId> ids = <ParticipantId>[
      for (final ParticipantFixtureTotals line in totals) line.participantId,
    ];
    final names = await _participants.findDisplayNames(ids);
    if (names is Err<Map<String, String>>) {
      return Result.err(names.error);
    }
    // A picture is decoration: a failed read shows the board without them.
    final avatars = switch (await _participants.findAvatarRefs(ids)) {
      Ok<Map<String, ParticipantAvatarRef>>(:final value) => value,
      Err<Map<String, ParticipantAvatarRef>>() =>
        const <String, ParticipantAvatarRef>{},
    };

    return FixtureLeaderboard.rankTotals(
      seasonId: season,
      totals: totals,
      displayNames: (names as Ok<Map<String, String>>).value,
      avatarUserIds: {
        for (final entry in avatars.entries) entry.key: entry.value.userId,
      },
      avatarUpdatedAt: {
        for (final entry in avatars.entries) entry.key: entry.value.updatedAt,
      },
    );
  }
}
