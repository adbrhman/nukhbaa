/// Use-case: read the caller's own daily challenge.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/daily_challenge_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reports how much of today's match day the caller has covered (P1-6).
///
/// The read half of the challenge that [DailyChallengeRepository] already
/// backs on the write path: `SubmitFixturePrediction` asks the same question
/// after a prediction lands, to decide whether to raise
/// `daily_challenge_completed`. This use-case asks it on demand, so the
/// number a screen shows and the number that raises the event come from one
/// query, never from two definitions that can drift.
///
/// **Today** is the Riyadh day (`riyadhDayOf`), the boundary the whole
/// gamification plan uses. The per-user UTC offset is for notification
/// timing only and is deliberately not consulted here.
///
/// **Which fixtures count.** Only the seasons the caller is an active
/// participant in, summed. That is the same scoping the streak calendar uses
/// since migration 0060: a day a user cannot play is not their day. One
/// extra round trip per active season is paid to resolve the participant;
/// the platform runs a single monthly season at a time, so that is one, and
/// the loop is bounded by participations, never by fixtures.
///
/// Only the caller's own challenge, always: there is no surface for reading
/// someone else's, so the principal is the whole of the authority check.
///
/// Never throws; returns a typed [Result].
final class GetMyDailyChallenge {
  /// Creates the use-case over its collaborators.
  const GetMyDailyChallenge({
    required CompetitionRepository competitionRepository,
    required DailyChallengeRepository dailyChallenges,
    required Clock clock,
  }) : _competition = competitionRepository,
       _challenges = dailyChallenges,
       _clock = clock;

  final CompetitionRepository _competition;
  final DailyChallengeRepository _challenges;
  final Clock _clock;

  /// Reads [principal]'s challenge for the Riyadh day that is open now.
  Future<Result<MyDailyChallenge>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final nowUtc = _clock.nowUtc();
    final day = riyadhDayOf(nowUtc);

    final seasonsResult = await _competition.listActiveParticipantSeasons(
      userId: principal.userId,
      nowUtc: nowUtc,
    );
    if (seasonsResult is Err<List<ParticipantSeasonFeedEntry>>) {
      return Result.err(seasonsResult.error);
    }
    final seasons =
        (seasonsResult as Ok<List<ParticipantSeasonFeedEntry>>).value;

    var total = 0;
    var predicted = 0;
    for (final season in seasons) {
      final participantResult = await _competition.findParticipant(
        season.seasonId,
        principal.userId,
      );
      if (participantResult is Err<Participant?>) {
        return Result.err(participantResult.error);
      }
      final participant = (participantResult as Ok<Participant?>).value;
      // listActiveParticipantSeasons already filtered on an active
      // participation, so a null here means the row went away between the two
      // reads. Skipping is the honest reading: that season is not the
      // caller's any more.
      if (participant == null) {
        continue;
      }

      final progressResult = await _challenges.progressOn(
        seasonId: season.seasonId,
        participantId: participant.id,
        day: day,
      );
      if (progressResult is Err<DailyChallengeProgress>) {
        return Result.err(progressResult.error);
      }
      final progress = (progressResult as Ok<DailyChallengeProgress>).value;
      total += progress.total;
      predicted += progress.predicted;
    }

    return Result.ok(
      MyDailyChallenge(day: day, total: total, predicted: predicted),
    );
  }
}

/// The caller's coverage of today's match day.
final class MyDailyChallenge {
  /// Creates a reading.
  const MyDailyChallenge({
    required this.day,
    required this.total,
    required this.predicted,
  });

  /// The Riyadh day this reading is about, as a UTC midnight.
  final DateTime day;

  /// How many fixtures the caller's seasons hold today.
  final int total;

  /// How many of them the caller has predicted.
  final int predicted;

  /// Whether today is covered in full.
  ///
  /// A day with no fixtures is NOT complete, exactly as
  /// [DailyChallengeProgress.isComplete] decides it on the write path: an
  /// empty day is not an achievement.
  bool get isComplete => total > 0 && predicted >= total;
}
