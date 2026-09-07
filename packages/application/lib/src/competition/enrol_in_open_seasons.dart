/// Use-case: put the caller into whatever contest is currently running.
library;

import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Enrols an authenticated user in every season that is open right now and
/// actually has fixtures.
///
/// ## Why this exists
/// Joining used to be something a user had to find and do. In practice they
/// did not: of 97 accounts, 28 had joined nothing at all and 23 had joined
/// only league seasons that carry no fixtures -- so half the user base opened
/// the leaderboard and were told to "join a season" while the month's contest
/// ran without them. Membership is not a decision this product asks anyone to
/// make: if you are in the app, you are in this month.
///
/// ## Idempotence
/// Runs on every `GET /me`, so it must converge rather than accumulate. It
/// checks membership first, and the database's
/// `participants_season_user_uniq` is the backstop underneath that check --
/// two concurrent opens cannot produce two enrolments. An already-joined user
/// is left exactly as they are: their original `joined_at` is never rewritten.
///
/// ## Failure posture
/// Enrolment is a side benefit of a read, never its purpose. Every failure is
/// swallowed into `Ok`: a user must still be able to see who they are when
/// the enrolment write is unavailable. The next call retries by construction.
final class EnrolInOpenSeasons {
  /// Creates the use-case over its repository port.
  const EnrolInOpenSeasons({
    required CompetitionRepository competitionRepository,
    required IdGenerator idGenerator,
  }) : _competition = competitionRepository,
       _idGenerator = idGenerator;

  final CompetitionRepository _competition;
  final IdGenerator _idGenerator;

  /// Enrols [principal] wherever a contest is running. Always returns `Ok`.
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required DateTime now,
  }) async {
    final seasonsResult = await _competition.listOpenSeasonsWithFixtures(
      now.toUtc(),
    );
    if (seasonsResult is Err<List<CompetitionSeason>>) {
      return const Result.ok(null);
    }
    final seasons = (seasonsResult as Ok<List<CompetitionSeason>>).value;

    for (final season in seasons) {
      final existing = await _competition.findParticipant(
        season.id,
        principal.userId,
      );
      if (existing is Err<Participant?>) {
        continue;
      }
      if ((existing as Ok<Participant?>).value != null) {
        continue;
      }

      final idResult = ParticipantId.tryParse(_idGenerator.newUuid());
      if (idResult is Err<ParticipantId>) {
        continue;
      }
      final participant = Participant.join(
        id: (idResult as Ok<ParticipantId>).value,
        seasonId: season.id,
        userId: principal.userId,
        joinedAt: now.toUtc(),
      );
      if (participant is Err<Participant>) {
        continue;
      }
      // A concurrent open may have won the race; the unique constraint turns
      // that into an error we deliberately drop, because the outcome it
      // reports -- the user is a member -- is the one we wanted.
      await _competition.saveParticipant(
        (participant as Ok<Participant>).value,
      );
    }

    return const Result.ok(null);
  }
}
