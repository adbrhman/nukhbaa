import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port: per-participant sums of the stored fixture scores for a set of
/// fixtures -- one line per participant instead of one row per participant
/// per fixture.
///
/// The adapter only sums what `ScoreFixture` already stored (Axioms 2/5); it
/// never scores and never writes.
abstract interface class FixtureTotalsReader {
  /// The totals of every participant scored on at least one of [fixtures].
  /// An empty [fixtures] list yields an empty list.
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  );
}
