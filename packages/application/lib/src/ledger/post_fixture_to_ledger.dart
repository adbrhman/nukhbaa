import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/ledger/ports/fixture_ledger_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin command: post a scored fixture's points to the append-only ledger.
///
/// A test fixture (migration 0098) posts nothing: the call succeeds with no
/// entries. Applied when the schedule repository is wired.
final class PostFixtureToLedger {
  const PostFixtureToLedger({
    required FixtureScoreRepository fixtureScoreRepository,
    required FixtureLedgerRepository fixtureLedgerRepository,
    required IdGenerator idGenerator,
    required Clock clock,
    FixtureScheduleRepository? fixtureScheduleRepository,
  }) : _scores = fixtureScoreRepository,
       _ledger = fixtureLedgerRepository,
       _ids = idGenerator,
       _clock = clock,
       _schedules = fixtureScheduleRepository;

  final FixtureScoreRepository _scores;
  final FixtureLedgerRepository _ledger;
  final IdGenerator _ids;
  final Clock _clock;

  /// Optional: without it every fixture is posted, as before 0098.
  final FixtureScheduleRepository? _schedules;

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

    final schedules = _schedules;
    if (schedules != null) {
      final scheduleResult = await schedules.findByFixture(fixture);
      if (scheduleResult is Err<FixtureSchedule?>) {
        return Result.err(scheduleResult.error);
      }
      if ((scheduleResult as Ok<FixtureSchedule?>).value?.isTest ?? false) {
        return const Result.ok(<FixturePointEntry>[]);
      }
    }

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
    // How many score entries each participant already has on this
    // fixture: the place of the next correction in that history.
    final postedCounts = <String, int>{};
    for (final entry in existingEntries) {
      // A streak bonus rides on the fixture that completed a match day, but
      // it is not part of that fixture's score. Counting it here would make
      // the first post look already posted and turn the fixture_score credit
      // into a correction that nets the bonus away.
      if (entry.kind == EntryKind.streakBonus) {
        continue;
      }
      final key = entry.participantId.value;
      postedTotals[key] = (postedTotals[key] ?? 0) + entry.amount;
      postedCounts[key] = (postedCounts[key] ?? 0) + 1;
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
      // or delete the original entry). The source_ref carries the place of
      // this correction in the participant's history on the fixture, so
      // successive corrections coexist while two posts racing over the
      // same one -- the admin's and the rescore sweep's, both reading the
      // ledger before either wrote -- build the same source_ref, and the
      // table's unique (participant, fixture, kind, source_ref) keeps
      // one. It used to embed the entry's fresh id, which let both in.
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
            '${score.participantId.value}:'
            '${postedCounts[score.participantId.value] ?? 0}',
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
