import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port: every user's summed monthly fixture standings over one
/// sporting season (September through August), unranked.
///
/// The adapter only sums what the scoring context already stored per month;
/// it never scores and never writes.
abstract interface class SportingSeasonStandingsReader {
  /// The unranked standings of every user with at least one scored fixture
  /// in a month of [season].
  Future<Result<List<SportingSeasonStanding>>> standings(SportingSeason season);
}
