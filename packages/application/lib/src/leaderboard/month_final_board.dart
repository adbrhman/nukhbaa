import 'package:application/src/leaderboard/ports/fixture_totals_reader.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:application/src/ledger/ports/participant_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One line of a month's final board, with the player behind it.
final class ChampionCandidate {
  /// Creates the line.
  const ChampionCandidate({required this.entry, required this.userId});

  /// The ranked line, exactly as the monthly board shows it.
  final FixtureLeaderboardEntry entry;

  /// The player behind [entry]'s participant.
  final UserId userId;
}

/// Builds a month's final board the way the live monthly board is built
/// (`GetSeasonFixtureLeaderboard`): the stored totals of every fixture linked
/// to the month, ranked by `FixtureLeaderboard.rankTotals` -- prediction
/// points, then the month's invitation points, then exact scorelines, level
/// on all three sharing a rank. No movement arrows: the board is final.
///
/// Never throws; returns a typed [Result].
final class MonthFinalBoard {
  /// Creates the board over its readers.
  const MonthFinalBoard({
    required FixtureTotalsReader fixtureTotalsReader,
    required ParticipantReader participantReader,
  }) : _totals = fixtureTotalsReader,
       _participants = participantReader;

  final FixtureTotalsReader _totals;
  final ParticipantReader _participants;

  /// The first [limit] lines of [month]'s board, never cutting a tie for
  /// first place: every player ranked first is always included.
  Future<Result<List<ChampionCandidate>>> top(
    ChampionMonth month, {
    required int limit,
  }) async {
    final totalsResult = await _totals.totalsFor(month.fixtures);
    if (totalsResult is Err<List<ParticipantFixtureTotals>>) {
      return Result.err(totalsResult.error);
    }
    final totals = (totalsResult as Ok<List<ParticipantFixtureTotals>>).value;
    if (totals.isEmpty) {
      return const Result.ok(<ChampionCandidate>[]);
    }

    final ids = <ParticipantId>{
      for (final line in totals) line.participantId,
    }.toList(growable: false);
    final namesResult = await _participants.findDisplayNames(ids);
    if (namesResult is Err<Map<String, String>>) {
      return Result.err(namesResult.error);
    }
    // A picture is decoration: a failed read leaves the pictures out rather
    // than failing the board, as on the live board.
    final avatars = switch (await _participants.findAvatarRefs(ids)) {
      Ok<Map<String, ParticipantAvatarRef>>(:final value) => value,
      Err<Map<String, ParticipantAvatarRef>>() =>
        const <String, ParticipantAvatarRef>{},
    };

    final boardResult = FixtureLeaderboard.rankTotals(
      seasonId: month.seasonId,
      totals: totals,
      displayNames: (namesResult as Ok<Map<String, String>>).value,
      avatarUserIds: {
        for (final entry in avatars.entries) entry.key: entry.value.userId,
      },
      avatarUpdatedAt: {
        for (final entry in avatars.entries) entry.key: entry.value.updatedAt,
      },
    );
    if (boardResult is Err<FixtureLeaderboard>) {
      return Result.err(boardResult.error);
    }
    final entries = (boardResult as Ok<FixtureLeaderboard>).value.entries;

    final int leaders = entries.takeWhile((entry) => entry.rank == 1).length;
    final int take = leaders > limit ? leaders : limit;
    final out = <ChampionCandidate>[];
    for (final entry in entries.take(take)) {
      final participantResult = await _participants.findParticipantById(
        entry.participantId,
      );
      if (participantResult is Err<Participant?>) {
        return Result.err(participantResult.error);
      }
      final participant = (participantResult as Ok<Participant?>).value;
      if (participant == null) {
        return const Result.err(
          AppError.invariant(
            'champion.board_inconsistent',
            'A ranked participant has no player behind it',
          ),
        );
      }
      out.add(ChampionCandidate(entry: entry, userId: participant.userId));
    }
    return Result.ok(List<ChampionCandidate>.unmodifiable(out));
  }
}
