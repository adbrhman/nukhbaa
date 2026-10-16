import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/football_data/ports/team_catalog_writer.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin command: add a club to the team catalog (`POST /admin/teams`,
/// script 91), so a match is always added with both its clubs picked from
/// the list.
///
/// A name typed into a match carried no team id, so neither the server's
/// check ([RegisterFixtureSchedule], batch 138) nor the schedule's trigger
/// (migration 0110) could see that "هوفنهايم - بيشتكاش" was the
/// "هوفنهايم - بشكتاش" the fixtures sync had added (2026-10-15). Decided by
/// the owner on 2026-10-16: a club the list lacks is added to the list.
///
/// A name whose spelling key is already in the catalog is refused with
/// [existsCode], naming the club on file, and nothing is written. The club
/// added has no crest and no short name: the app draws its initials. Every
/// club added is audited ([AuditAction.teamAdded], the reason its name).
///
/// Never throws; returns the club added.
final class AdminAddTeam {
  /// Creates the command over its collaborators.
  const AdminAddTeam({
    required TeamCatalogWriter writer,
    required AuditRecorder auditRecorder,
  }) : _writer = writer,
       _audit = auditRecorder;

  /// The longest club name taken, after its spaces are folded.
  static const int maxNameLength = 80;

  /// The stable code of the refusal for a club already in the catalog.
  static const String existsCode = 'football_data.team_exists';

  /// The stable code of the refusal for an empty or overlong name.
  static const String nameInvalidCode = 'football_data.team_name_invalid';

  final TeamCatalogWriter _writer;
  final AuditRecorder _audit;

  /// Adds [name] under [leagueId] (none when `null`) on behalf of admin
  /// [principal].
  Future<Result<Team>> call({
    required AuthenticatedUser principal,
    required String name,
    String? leagueId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final folded = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (folded.isEmpty || folded.length > maxNameLength) {
      return const Result.err(
        AppError.validation(
          nameInvalidCode,
          'اكتب اسم النادي، $maxNameLength حرفًا على الأكثر.',
        ),
      );
    }

    LeagueRef? league;
    if (leagueId != null) {
      final parsed = LeagueRef.tryParse(leagueId);
      if (parsed is Err<LeagueRef>) {
        return Result.err(parsed.error);
      }
      league = (parsed as Ok<LeagueRef>).value;
    }

    final added = await _writer.add(name: folded, leagueId: league);
    if (added is Err<TeamAddition>) {
      return Result.err(added.error);
    }
    final addition = (added as Ok<TeamAddition>).value;
    if (addition.existed) {
      return Result.err(existsOf(addition.team));
    }

    final recorded = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.teamAdded,
      targetRef: addition.team.id.value,
      reason: addition.team.name,
    );
    if (recorded is Err<AuditEntry>) {
      return Result.err(recorded.error);
    }
    return Result.ok(addition.team);
  }

  /// The refusal for a club already in the catalog as [team]: Arabic, so
  /// the admin's dialog shows it as it is.
  static AppError existsOf(Team team) => AppError.invariant(
    existsCode,
    'النادي «${team.name}» في القائمة من قبل، فاختره منها. '
    'لم يُضَف مرة ثانية.',
  );
}
