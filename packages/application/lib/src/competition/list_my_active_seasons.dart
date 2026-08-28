import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: every season [principal] is an **active** participant in,
/// right now (docs/project-context.md; the participant-scoped analogue of
/// [ListMyFixturePredictions], backing a "my seasons" mobile read that then
/// fans out to the existing `BrowseSeasonFixtures` read, `GET
/// /seasons/{id}/fixtures`, per season it returns).
///
/// "Active, right now" is always computed fresh against "now" via [Clock]
/// and [CompetitionSeason.isCurrentAt] — the same "computed, never stored"
/// principle [GetCurrentSeason] already establishes; there is no persisted
/// "my seasons" state to drift out of sync.
///
/// **Visibility:** there is no season-membership gate to check here — the
/// repository already scopes to `principal.userId`, so nothing here can
/// reveal another user's participation.
///
/// A caller with no active participation covered by any season's window
/// right now yields `Ok(<empty list>)`, never an error — a legitimate "not
/// in any season right now" outcome (e.g. a brand-new user who has not yet
/// made a first prediction, since `FixturePredictionController` auto-joins
/// only on the first successful submission).
///
/// Never throws; returns a typed [Result].
final class ListMyActiveSeasons {
  /// Creates the use-case over its collaborators.
  const ListMyActiveSeasons({
    required CompetitionRepository competitionRepository,
    required Clock clock,
  }) : _competition = competitionRepository,
       _clock = clock;

  final CompetitionRepository _competition;
  final Clock _clock;

  /// Lists every season [principal] is an active participant in right now,
  /// ordered per [CompetitionRepository.listActiveParticipantSeasons].
  Future<Result<List<ParticipantSeasonFeedEntry>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _competition.listActiveParticipantSeasons(
      userId: principal.userId,
      nowUtc: _clock.nowUtc(),
    );
  }
}
