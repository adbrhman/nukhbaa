import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for the append-only **fixture-scoped** Ledger
/// (docs/project-context.md, Axiom 4 Amendment) — the per-fixture sibling of
/// [LedgerRepository], kept as its own port for the same reason
/// [FixturePredictionRepository] is separate from `PredictionRepository`:
/// editing an existing `abstract interface class` would break every current
/// implementer.
///
/// **Known gap (documented, not silently accepted):** [LedgerBalance] is
/// currently projected only from [LedgerRepository.listEntries] (round-scoped
/// entries). A participant's true balance now spans two streams
/// (round-scoped legacy entries + fixture-scoped entries via this port).
/// Unifying the balance projection across both is deferred to Phase 7
/// (contract) of this amendment, mirroring the reproducibility gap already
/// documented on `ScoreFixture`.
///
/// General contract for every method (Application ADR §2), mirroring
/// [LedgerRepository]:
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a storage-only integrity conflict to [ErrorKind.invariant].
abstract interface class FixtureLedgerRepository {
  /// Appends [entries] to the fixture-scoped ledger **atomically** and
  /// **idempotently** on the natural dedupe key `(participant_id, fixture_id,
  /// entry_kind)` for a kind that [EntryKind.isDedupedPerFixture] (a
  /// `fixture_score` credit): re-appending an already-present row is
  /// skipped, never duplicated (Axiom 4).
  ///
  /// Returns the subset of [entries] that were **actually appended**.
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  );

  /// Lists every [FixturePointEntry] for [participantId], in stream order
  /// (occurred-at ascending, then entry id for a stable tie-break).
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  );

  /// Lists every [FixturePointEntry] posted for [fixture], across every
  /// participant, in stream order (occurred-at ascending, then entry id for a
  /// stable tie-break). Used to detect an already-posted credit so a re-post
  /// after a result correction can compute a compensating
  /// [EntryKind.correction] instead of silently skipping (Axiom 4/5/6).
  Future<Result<List<FixturePointEntry>>> findByFixture(FixtureRef fixture);
}
