import 'package:application/src/common/id_generator.dart';
import 'package:application/src/gamification/get_my_streak.dart';
import 'package:application/src/ledger/ports/fixture_ledger_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Pays the streak bonus a participant's run has earned (P1-4).
///
/// The bonus is a `streak_bonus` entry in the append-only fixture ledger,
/// never a row in a second points table, and only the server writes it: the
/// amount comes from [StreakBonusPolicy], the run from [GetMyStreak], and
/// nothing here accepts a number from a client (Axiom 2).
///
/// **Which rungs.** Every rung the CURRENT run has reached
/// ([StreakBonusPolicy.reachedBy]) that the participant's ledger does not
/// already hold. Reaching a rung is `>=`, so a bonus that missed its
/// moment is paid on the next evaluation instead of being lost.
///
/// **Once per rung, per participant.** Three layers say the same thing: the
/// ledger is read first and a rung already on it is skipped; the entry's
/// `source_ref` is `streak:<threshold>`; and a partial unique index on
/// `(participant_id, source_ref)` (migration 0057) refuses a second one. Two
/// concurrent evaluations can both pass the read, and the loser then meets
/// the index; the adapter reports that as `ledger.already_posted`, which is
/// the same fact as "someone paid it" and is treated as success.
///
/// **Per participant means per season.** A participant belongs to one season,
/// so a run that carries into a new season is paid its rungs again there.
///
/// Each rung is appended in its own call, so one refused rung cannot take
/// the others down with it.
///
/// [participantId] MUST be the caller's own participant, resolved server-side
/// from the verified principal; this use-case never derives it. [now] is the
/// instant the bonus is granted, stamped on the entry as it is, and MUST be
/// UTC.
///
/// Never throws; returns a typed [Result] carrying the entries actually
/// appended by this call (empty when nothing was owed).
final class AwardStreakBonus {
  /// Creates the use-case over its collaborators.
  const AwardStreakBonus({
    required GetMyStreak getMyStreak,
    required FixtureLedgerRepository fixtureLedgerRepository,
    required IdGenerator idGenerator,
  }) : _getMyStreak = getMyStreak,
       _ledger = fixtureLedgerRepository,
       _ids = idGenerator;

  final GetMyStreak _getMyStreak;
  final FixtureLedgerRepository _ledger;
  final IdGenerator _ids;

  static const String _alreadyPosted = 'ledger.already_posted';

  /// Pays [principal]'s owed rungs against [fixture].
  Future<Result<List<FixturePointEntry>>> call({
    required AuthenticatedUser principal,
    required ParticipantId participantId,
    required FixtureRef fixture,
    required DateTime now,
  }) async {
    final streakResult = await _getMyStreak(principal: principal);
    if (streakResult is Err<StreakTally>) {
      return Result.err(streakResult.error);
    }
    final streak = (streakResult as Ok<StreakTally>).value;

    final reached = StreakBonusPolicy.reachedBy(streak.current);
    if (reached.isEmpty) {
      return const Result.ok(<FixturePointEntry>[]);
    }

    final existingResult = await _ledger.listEntries(participantId);
    if (existingResult is Err<List<FixturePointEntry>>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<List<FixturePointEntry>>).value;
    final alreadyPaid = <String>{
      for (final entry in existing)
        if (entry.kind == EntryKind.streakBonus) entry.sourceRef,
    };

    final paid = <FixturePointEntry>[];
    for (final rung in reached) {
      if (alreadyPaid.contains(rung.sourceRef)) {
        continue;
      }

      final idResult = PointEntryId.tryParse(_ids.newUuid());
      if (idResult is Err<PointEntryId>) {
        return Result.err(idResult.error);
      }
      final entryResult = FixturePointEntry.create(
        id: (idResult as Ok<PointEntryId>).value,
        participantId: participantId,
        fixture: fixture,
        kind: EntryKind.streakBonus,
        amount: rung.points,
        sourceRef: rung.sourceRef,
        occurredAt: now,
      );
      if (entryResult is Err<FixturePointEntry>) {
        return Result.err(entryResult.error);
      }
      final entry = (entryResult as Ok<FixturePointEntry>).value;

      final appended = await _ledger.appendEntries(<FixturePointEntry>[entry]);
      if (appended is Err<List<FixturePointEntry>>) {
        if (appended.error.code == _alreadyPosted) {
          continue;
        }
        return Result.err(appended.error);
      }
      paid.addAll((appended as Ok<List<FixturePointEntry>>).value);
    }
    return Result.ok(List<FixturePointEntry>.unmodifiable(paid));
  }
}
