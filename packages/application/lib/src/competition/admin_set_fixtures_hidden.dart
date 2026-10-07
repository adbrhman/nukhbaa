import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/competition/ports/fixture_visibility_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin command: hide fixtures from the players, or show them again
/// (migration 0098). One fixture or many at once, the same command.
///
/// Hiding deletes nothing: predictions, results, scores and ledger entries
/// stay as they are. While a fixture is hidden no player reads it, nobody
/// can predict it, and it is not scored; shown again, it is back in every
/// read and the rescore sweep finishes whatever waited.
///
/// Every fixture whose state changed is audited (`fixture_hidden` /
/// `fixture_shown`), so the log names each one.
///
/// Never throws; returns the fixtures that changed.
final class AdminSetFixturesHidden {
  /// Creates the command over its collaborators.
  const AdminSetFixturesHidden({
    required FixtureVisibilityStore store,
    required AuditRecorder auditRecorder,
  }) : _store = store,
       _audit = auditRecorder;

  /// The most fixtures one call may change: a month's worth, with room.
  static const int maxFixtures = 200;

  final FixtureVisibilityStore _store;
  final AuditRecorder _audit;

  /// Hides ([hidden] true) or shows [fixtureIds] on behalf of admin
  /// [principal].
  Future<Result<List<FixtureRef>>> call({
    required AuthenticatedUser principal,
    required List<String> fixtureIds,
    required bool? hidden,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (hidden == null) {
      return const Result.err(
        AppError.validation(
          'competition.fixture_visibility_missing',
          'Field "hidden" is required and must be true or false',
        ),
      );
    }
    if (fixtureIds.isEmpty || fixtureIds.length > maxFixtures) {
      return const Result.err(
        AppError.validation(
          'competition.fixture_ids_invalid',
          'Field "fixture_ids" must name between 1 and $maxFixtures fixtures',
        ),
      );
    }

    final seen = <String>{};
    final fixtures = <FixtureRef>[];
    for (final raw in fixtureIds) {
      final parsed = FixtureRef.tryParse(raw);
      if (parsed is Err<FixtureRef>) {
        return Result.err(parsed.error);
      }
      final fixture = (parsed as Ok<FixtureRef>).value;
      if (seen.add(fixture.value)) {
        fixtures.add(fixture);
      }
    }

    final changedResult = await _store.setHidden(fixtures, hidden: hidden);
    if (changedResult is Err<List<FixtureRef>>) {
      return Result.err(changedResult.error);
    }
    final changed = (changedResult as Ok<List<FixtureRef>>).value;

    final action = hidden
        ? AuditAction.fixtureHidden
        : AuditAction.fixtureShown;
    for (final fixture in changed) {
      final recorded = await _audit.record(
        actorId: principal.userId,
        action: action,
        targetRef: fixture.value,
      );
      if (recorded is Err<AuditEntry>) {
        return Result.err(recorded.error);
      }
    }

    return Result.ok(List<FixtureRef>.unmodifiable(changed));
  }
}
