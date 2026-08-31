import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/ledger/ports/fixture_ledger_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class PostFixtureToLedger {
  const PostFixtureToLedger({
    required FixtureScoreRepository fixtureScoreRepository,
    required FixtureLedgerRepository fixtureLedgerRepository,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _scores = fixtureScoreRepository,
       _ledger = fixtureLedgerRepository,
       _ids = idGenerator,
       _clock = clock;

  final FixtureScoreRepository _scores;
  final FixtureLedgerRepository _ledger;
  final IdGenerator _ids;
  final Clock _clock;

  Future<Result<List<FixturePointEntry>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final scoresResult = await _scores.listByFixture(fixture);
    if (scoresResult is Err<List<ParticipantFixtureScore>>) {
      return Result.err(scoresResult.error);
    }
    final fixtureScores =
        (scoresResult as Ok<List<ParticipantFixtureScore>>).value;

    // Read what has already been posted for this fixture, so a re-post
    // after a result correction can compute a compensating
    // EntryKind.correction instead of the dedupe constraint silently
    // dropping it (the bug this fixes: Admin Update Result -> Recalculate
    // -> Correct Points was a no-op on the ledger once the fixture had been
    // posted once).
    final existingResult = await _ledger.findByFixture(fixture);
    if (existingResult is Err<List<FixturePointEntry>>) {
      return Result.err(existingResult.error);
    }
    final existingEntries =
        (existingResult as Ok<List<FixturePointEntry>>).value;

    // Net already-posted amount per participant (fixture_score + any prior
    // corrections), mirroring the balance projection's own sum-of-entries
    // philosophy.
    final postedTotals = <String, int>{};
    for (final entry in existingEntries) {
      final key = entry.participantId.value;
      postedTotals[key] = (postedTotals[key] ?? 0) + entry.amount;
    }

    final now = _clock.nowUtc();
    final entries = <FixturePointEntry>[];
    for (final score in fixtureScores) {
      final alreadyPosted = postedTotals[score.participantId.value];

      if (alreadyPosted == null) {
        // First post for this participant on this fixture -- the original
        // fixture_score credit. ON CONFLICT DO NOTHING on the Postgres
        // adapter remains the backstop against a concurrent double-post.
        final idResult = PointEntryId.tryParse(_ids.newUuid());
        if (idResult is Err<PointEntryId>) {
          return Result.err(idResult.error);
        }
        final entryResult = FixturePointEntry.create(
          id: (idResult as Ok<PointEntryId>).value,
          participantId: score.participantId,
          fixture: fixture,
          kind: EntryKind.fixtureScore,
          amount: score.points,
          sourceRef:
              'fixture_score:${fixture.value}:${score.participantId.value}',
          occurredAt: now,
        );
        if (entryResult is Err<FixturePointEntry>) {
          return Result.err(entryResult.error);
        }
        entries.add((entryResult as Ok<FixturePointEntry>).value);
        continue;
      }

      final delta = score.points - alreadyPosted;
      if (delta == 0) {
        // Already posted and unchanged since -- nothing to correct.
        continue;
      }

      // The fixture's result was corrected after the original post: append
      // a compensating correction for the difference (Axiom 5 -- never edit
      // or delete the original entry). The source_ref embeds this entry's
      // own fresh id so more than one correction can coexist over time
      // (EntryKind.correction is intentionally not deduped on a fixed key).
      final idResult = PointEntryId.tryParse(_ids.newUuid());
      if (idResult is Err<PointEntryId>) {
        return Result.err(idResult.error);
      }
      final id = (idResult as Ok<PointEntryId>).value;
      final entryResult = FixturePointEntry.create(
        id: id,
        participantId: score.participantId,
        fixture: fixture,
        kind: EntryKind.correction,
        amount: delta,
        sourceRef:
            'fixture_score_correction:${fixture.value}:'
            '${score.participantId.value}:${id.value}',
        occurredAt: now,
      );
      if (entryResult is Err<FixturePointEntry>) {
        return Result.err(entryResult.error);
      }
      entries.add((entryResult as Ok<FixturePointEntry>).value);
    }

    return _ledger.appendEntries(entries);
  }
}
