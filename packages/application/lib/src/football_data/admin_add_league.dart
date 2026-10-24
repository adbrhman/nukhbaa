import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/football_data/ports/league_catalog_writer.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin command: add a league to the league catalog
/// (`POST /admin/leagues`, script 139), so a match of a competition the
/// list lacks is filed under its own name.
///
/// Some competitions play rarely but carry strong matches, and the list
/// held only what the seed migrations put there. Asked by the owner on
/// 2026-10-24: a "new league" entry in the add-match form's league list.
///
/// The league is added continental (`League.isContinental`), as migration
/// 0104 filed the big derbies: its clubs come from the whole catalog and no
/// club is tagged to it. A name whose spelling key is already in the
/// catalog is refused with [existsCode], naming the league on file, and
/// nothing is written. Every league added is audited
/// ([AuditAction.leagueAdded], the reason its name).
///
/// Never throws; returns the league added.
final class AdminAddLeague {
  /// Creates the command over its collaborators.
  const AdminAddLeague({
    required LeagueCatalogWriter writer,
    required AuditRecorder auditRecorder,
  }) : _writer = writer,
       _audit = auditRecorder;

  /// The longest league name taken, after its spaces are folded.
  static const int maxNameLength = 80;

  /// The stable code of the refusal for a league already in the catalog.
  static const String existsCode = 'football_data.league_exists';

  /// The stable code of the refusal for an empty or overlong name.
  static const String nameInvalidCode = 'football_data.league_name_invalid';

  final LeagueCatalogWriter _writer;
  final AuditRecorder _audit;

  /// Adds [name] on behalf of admin [principal].
  Future<Result<League>> call({
    required AuthenticatedUser principal,
    required String name,
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
          'اكتب اسم الدوري، $maxNameLength حرفًا على الأكثر.',
        ),
      );
    }

    final added = await _writer.add(name: folded);
    if (added is Err<LeagueAddition>) {
      return Result.err(added.error);
    }
    final addition = (added as Ok<LeagueAddition>).value;
    if (addition.existed) {
      return Result.err(existsOf(addition.league));
    }

    final recorded = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.leagueAdded,
      targetRef: addition.league.id.value,
      reason: addition.league.name,
    );
    if (recorded is Err<AuditEntry>) {
      return Result.err(recorded.error);
    }
    return Result.ok(addition.league);
  }

  /// The refusal for a league already in the catalog as [league]: Arabic,
  /// so the admin's dialog shows it as it is.
  static AppError existsOf(League league) => AppError.invariant(
    existsCode,
    'الدوري «${league.name}» في القائمة من قبل، فاختره منها. '
    'لم يُضَف مرة ثانية.',
  );
}
