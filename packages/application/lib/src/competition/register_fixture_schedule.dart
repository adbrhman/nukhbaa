import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/competition/ports/same_match_finder.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin command: register a new fixture's identity. [call]'s `isTest`
/// files it as a test fixture (migration 0098) -- admins only, never
/// scored -- and that choice cannot be changed later.
///
/// A match already on the schedule -- the same two sides within
/// [duplicateWindow] of the kickoff, added by the fixtures sync or by an
/// admin -- is refused with `competition.fixture_duplicate`, so one match
/// never appears twice (the Europa League evening of 2026-10-15 did). A
/// test fixture is never checked.
final class RegisterFixtureSchedule {
  const RegisterFixtureSchedule({
    required FixtureScheduleRepository repository,
    required IdGenerator idGenerator,
    SameMatchFinder? sameMatchFinder,
    this.duplicateWindow = const Duration(hours: 12),
  }) : _repository = repository,
       _idGenerator = idGenerator,
       _sameMatch = sameMatchFinder;

  final FixtureScheduleRepository _repository;
  final IdGenerator _idGenerator;
  final SameMatchFinder? _sameMatch;

  /// A fixture of the same two sides kicking off this close is the same
  /// match -- the window the fixtures sync uses to adopt one.
  final Duration duplicateWindow;

  /// The stable code of the refusal for a match already on the schedule.
  static const String duplicateCode = 'competition.fixture_duplicate';

  /// The stable code of the refusal for a match of a club whose matches
  /// never appear (migration 0174, script 92); the schedule's trigger
  /// refuses it, whoever writes the fixture or shows it again.
  static const String blockedClubCode = 'competition.fixture_blocked_club';

  /// The refusal for such a match: Arabic, so the admin sees it as it is.
  static const AppError blockedClub = AppError.invariant(
    blockedClubCode,
    'مباريات هذا النادي ممنوعة في نُخبة، فلم تُحفظ ولا تُظهَر.',
  );

  Future<Result<FixtureSchedule>> call({
    required AuthenticatedUser principal,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoffAt,
    String? homeTeamId,
    String? awayTeamId,
    String? leagueId,
    bool isTest = false,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(_idGenerator.newUuid());
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }

    final homeTeamRefResult = _parseOptionalTeamRef(homeTeamId);
    if (homeTeamRefResult is Err<TeamRef?>) {
      return Result.err(homeTeamRefResult.error);
    }
    final awayTeamRefResult = _parseOptionalTeamRef(awayTeamId);
    if (awayTeamRefResult is Err<TeamRef?>) {
      return Result.err(awayTeamRefResult.error);
    }

    final leagueRefResult = _parseOptionalLeagueRef(leagueId);
    if (leagueRefResult is Err<LeagueRef?>) {
      return Result.err(leagueRefResult.error);
    }

    final scheduleResult = FixtureSchedule.create(
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
      homeTeamId: (homeTeamRefResult as Ok<TeamRef?>).value,
      awayTeamId: (awayTeamRefResult as Ok<TeamRef?>).value,
      leagueId: (leagueRefResult as Ok<LeagueRef?>).value,
      isTest: isTest,
    );
    if (scheduleResult is Err<FixtureSchedule>) {
      return Result.err(scheduleResult.error);
    }
    final schedule = (scheduleResult as Ok<FixtureSchedule>).value;

    final finder = _sameMatch;
    if (finder != null && !isTest) {
      final kickoff = schedule.kickoffAt.toUtc();
      final found = await finder.find(
        homeTeam: schedule.homeTeam,
        awayTeam: schedule.awayTeam,
        homeTeamId: schedule.homeTeamId?.value,
        awayTeamId: schedule.awayTeamId?.value,
        from: kickoff.subtract(duplicateWindow),
        to: kickoff.add(duplicateWindow),
      );
      if (found is Err<SameMatch?>) {
        return Result.err(found.error);
      }
      final same = (found as Ok<SameMatch?>).value;
      if (same != null) {
        return Result.err(duplicateOf(same));
      }
    }

    final saved = await _repository.upsert(schedule);
    return switch (saved) {
      Ok<void>() => Result.ok(schedule),
      Err<void>(:final error) => Result.err(error),
    };
  }

  /// The refusal for a match already on the schedule as [same]: Arabic,
  /// so the admin form shows it as it is, with the stored sides and the
  /// kickoff in Riyadh time (UTC+3).
  static AppError duplicateOf(SameMatch same) {
    final riyadh = same.kickoffAt.toUtc().add(const Duration(hours: 3));
    String two(int n) => n.toString().padLeft(2, '0');
    return AppError.invariant(
      duplicateCode,
      'هذه المباراة مضافة من قبل: '
      '${same.homeTeam} - ${same.awayTeam}، '
      '${two(riyadh.day)}/${two(riyadh.month)} '
      'الساعة ${two(riyadh.hour)}:${two(riyadh.minute)} '
      'بتوقيت الرياض. '
      'لم تُضَف مرة ثانية.',
    );
  }

  /// Parses an optional client-supplied team id: absent stays absent (the
  /// enrichment is opt-in, Football Data phase), present must be a valid
  /// [TeamRef].
  static Result<TeamRef?> _parseOptionalTeamRef(String? raw) {
    if (raw == null) {
      return const Result.ok(null);
    }
    final parsed = TeamRef.tryParse(raw);
    return switch (parsed) {
      Ok<TeamRef>(:final value) => Result.ok(value),
      Err<TeamRef>(:final error) => Result.err(error),
    };
  }

  /// Parses an optional client-supplied league id: absent stays absent
  /// (a fixture without a league is legitimate), present must be a valid
  /// [LeagueRef].
  static Result<LeagueRef?> _parseOptionalLeagueRef(String? raw) {
    if (raw == null) {
      return const Result.ok(null);
    }
    final parsed = LeagueRef.tryParse(raw);
    return switch (parsed) {
      Ok<LeagueRef>(:final value) => Result.ok(value),
      Err<LeagueRef>(:final error) => Result.err(error),
    };
  }
}
