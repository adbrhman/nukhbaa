import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// System use-case: make sure the next monthly contest exists before the
/// current one ends, so the app never opens a month with no contest.
///
/// The contest is the calendar month (a `MM/YYYY` season). Creating the next
/// one used to be a manual admin step; if it was missed, the 1st of the month
/// arrived with nothing to enrol into. This runs from the server's scheduler,
/// never from a request, so it takes no principal.
///
/// **Rule:** take the newest monthly season (by start) and its competition.
/// While the month that follows it starts within [lead] of now, create that
/// month under the same competition -- the same UTC window and `MM/YYYY`
/// label `StartSeason` produces. At most [maxPerRun] months are created per
/// call, so a server that was down for a long time catches up gradually and a
/// bug can never flood the table.
///
/// **Additive only:** it never edits or removes a season, and it skips a
/// month whose label already exists under that competition (re-read before
/// every write, so an admin creating the same month meanwhile is respected).
/// With no monthly season at all there is nothing to follow, and it does
/// nothing.
///
/// A season with no fixtures enrols nobody (`EnrolInOpenSeasons` only joins
/// seasons that have fixtures), so creating a month early is invisible to
/// users until the admin adds that month's first fixture.
///
/// Never throws; returns how many seasons it created.
final class EnsureUpcomingMonthlySeasons {
  /// Creates the use-case.
  const EnsureUpcomingMonthlySeasons({
    required CompetitionRepository repository,
    required IdGenerator idGenerator,
    this.lead = const Duration(days: 7),
    this.maxPerRun = 3,
  }) : _repository = repository,
       _idGenerator = idGenerator;

  final CompetitionRepository _repository;
  final IdGenerator _idGenerator;

  /// How long before a month starts it must already exist.
  final Duration lead;

  /// The most months one call may create.
  final int maxPerRun;

  static final RegExp _monthlyLabel = RegExp(r'^\d{2}/\d{4}$');

  /// Runs the rule at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final horizon = now.toUtc().add(lead);
    var created = 0;

    while (created < maxPerRun) {
      final seasonsResult = await _repository.listMonthlySeasons();
      if (seasonsResult is Err<List<CompetitionSeason>>) {
        return Result.err(seasonsResult.error);
      }
      final monthly = (seasonsResult as Ok<List<CompetitionSeason>>).value
          .where((season) => _monthlyLabel.hasMatch(season.label))
          .toList(growable: false);
      if (monthly.isEmpty) {
        return Result.ok(created);
      }

      var latest = monthly.first;
      for (final season in monthly) {
        if (season.startAt.isAfter(latest.startAt)) {
          latest = season;
        }
      }

      final previousEnd = latest.endAt.toUtc();
      final nextStart = DateTime.utc(previousEnd.year, previousEnd.month);
      if (nextStart.isAfter(horizon)) {
        return Result.ok(created);
      }

      final label = _labelFor(nextStart);
      final exists = monthly.any(
        (season) =>
            season.label == label &&
            season.competitionId == latest.competitionId,
      );
      if (exists) {
        // The newest season is not the latest month (labels and windows
        // disagree); refuse to guess rather than loop.
        return Result.ok(created);
      }

      final idResult = SeasonId.tryParse(_idGenerator.newUuid());
      if (idResult is Err<SeasonId>) {
        return Result.err(idResult.error);
      }
      final seasonResult = CompetitionSeason.create(
        id: (idResult as Ok<SeasonId>).value,
        competitionId: latest.competitionId,
        label: label,
        startAt: nextStart,
        endAt: DateTime.utc(nextStart.year, nextStart.month + 1),
      );
      if (seasonResult is Err<CompetitionSeason>) {
        return Result.err(seasonResult.error);
      }
      final saved = await _repository.saveSeason(
        (seasonResult as Ok<CompetitionSeason>).value,
      );
      if (saved is Err<void>) {
        return Result.err(saved.error);
      }
      created++;
    }
    return Result.ok(created);
  }

  static String _labelFor(DateTime monthStart) =>
      '${monthStart.month.toString().padLeft(2, '0')}/'
      '${monthStart.year.toString().padLeft(4, '0')}';
}
