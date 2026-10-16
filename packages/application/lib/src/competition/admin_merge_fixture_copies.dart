import 'package:application/src/competition/ports/fixture_merger.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/rescore_unscored_results.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin command: merge a copy of a match into the copy kept
/// (`POST /admin/fixtures/{id}/merge`, migration 0176, script 95).
///
/// On 2026-10-15/16 several matches were added twice; some players
/// predicted one copy, some the other, and hiding a copy took its
/// predictions out of sight with it. The merge moves them to the copy kept
/// as they are -- the same id, scoreline, stamp and double -- and hides the
/// copy for good, in one transaction, every trigger on
/// ([FixtureMerger.merge]). Those that may not move stay on the copy and
/// are counted: a player who predicted both, a prediction sent after the
/// kept copy's kickoff, a player not in its season. A double that would be
/// the player's second of the kept copy's day moves without its double.
/// The audit row is written by the merge itself.
///
/// With `apply` false it is a preview: the same counts, nothing written.
///
/// When something moved and the kept copy has its result, the kept copy is
/// scored and posted again through the official path ([FixtureRescorer]:
/// `ScoreFixture`, then `PostFixtureToLedger`, both idempotent). A failure
/// there does not undo the merge: the report says it was not rescored, and
/// the rescore sweep finishes it.
///
/// Never throws.
final class AdminMergeFixtureCopies {
  /// Creates the command over its collaborators; [rescore] is null in tests
  /// that do not look at the scoring.
  const AdminMergeFixtureCopies({
    required FixtureMerger merger,
    FixtureRescorer? rescore,
  }) : _merger = merger,
       _rescore = rescore;

  final FixtureMerger _merger;
  final FixtureRescorer? _rescore;

  /// Merges [duplicateId] into [keptId] ([apply] true) or previews it, on
  /// behalf of admin [principal].
  Future<Result<FixtureMergeReport>> call({
    required AuthenticatedUser principal,
    required String duplicateId,
    required String? keptId,
    required bool apply,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final duplicate = FixtureRef.tryParse(duplicateId);
    if (duplicate is Err<FixtureRef>) {
      return Result.err(duplicate.error);
    }
    final kept = FixtureRef.tryParse(keptId);
    if (kept is Err<FixtureRef>) {
      return const Result.err(
        AppError.validation(
          'competition.fixture_merge_into_invalid',
          'اختر النسخة التي تبقى.',
        ),
      );
    }

    final keptRef = (kept as Ok<FixtureRef>).value;
    final merged = await _merger.merge(
      duplicate: (duplicate as Ok<FixtureRef>).value,
      kept: keptRef,
      actor: principal.userId,
      apply: apply,
    );
    if (merged is Err<FixtureMergeReport>) {
      return Result.err(merged.error);
    }
    final report = (merged as Ok<FixtureMergeReport>).value;
    if (!apply) {
      return Result.ok(report);
    }

    final rescore = _rescore;
    var rescored = false;
    if (rescore != null && report.keptHasResult && report.moved > 0) {
      final scored = await rescore(fixtureId: keptRef.value);
      rescored = scored is Ok<void>;
    }
    return Result.ok(report.appliedWith(rescored: rescored));
  }
}
