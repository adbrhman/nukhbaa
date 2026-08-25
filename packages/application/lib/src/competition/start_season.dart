import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: start a new [CompetitionSeason] under an existing competition
/// (Application ADR, Section 2: command intent StartSeason).
///
/// Phase 7.2: calendar-driven monthly season. The admin selects [year]/
/// [month]; this use-case computes the UTC month window itself (startAt =
/// 1st of the month 00:00:00.000Z, endAt = 1st of the next month,
/// inclusive-start/exclusive-end) -- a caller never supplies startAt/endAt
/// directly. [label] is derived as "MM/YYYY".
final class StartSeason {
  const StartSeason({
    required CompetitionRepository repository,
    required IdGenerator idGenerator,
  }) : _repository = repository,
       _idGenerator = idGenerator;

  final CompetitionRepository _repository;
  final IdGenerator _idGenerator;

  Future<Result<CompetitionSeason>> call({
    required AuthenticatedUser principal,
    required String competitionId,
    required int year,
    required int month,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final competitionIdResult = CompetitionId.tryParse(competitionId);
    if (competitionIdResult is Err<CompetitionId>) {
      return Result.err(competitionIdResult.error);
    }
    final compId = (competitionIdResult as Ok<CompetitionId>).value;

    if (month < 1 || month > 12) {
      return const Result.err(
        AppError.validation(
          'competition.season_month_invalid',
          'month must be between 1 and 12',
        ),
      );
    }
    if (year < 2000 || year > 2100) {
      return const Result.err(
        AppError.validation(
          'competition.season_year_invalid',
          'year must be between 2000 and 2100',
        ),
      );
    }

    final competition = await _repository.findCompetition(compId);
    if (competition is Err<Competition>) {
      return Result.err(competition.error);
    }

    final seasonIdResult = SeasonId.tryParse(_idGenerator.newUuid());
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }

    final startAt = DateTime.utc(year, month);
    final endAt = DateTime.utc(year, month + 1);
    final label =
        '${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}';

    final seasonResult = CompetitionSeason.create(
      id: (seasonIdResult as Ok<SeasonId>).value,
      competitionId: compId,
      label: label,
      startAt: startAt,
      endAt: endAt,
    );
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }
    final season = (seasonResult as Ok<CompetitionSeason>).value;

    final saved = await _repository.saveSeason(season);
    return switch (saved) {
      Ok<void>() => Result.ok(season),
      Err<void>(:final error) => Result.err(error),
    };
  }
}
