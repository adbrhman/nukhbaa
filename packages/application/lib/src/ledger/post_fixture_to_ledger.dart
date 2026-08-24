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

    final now = _clock.nowUtc();
    final entries = <FixturePointEntry>[];
    for (final score in fixtureScores) {
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
    }

    return _ledger.appendEntries(entries);
  }
}
