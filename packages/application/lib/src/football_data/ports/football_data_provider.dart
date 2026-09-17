import 'package:shared/shared.dart';

/// Error code a [FootballDataProvider] returns when it stops calling the
/// provider to keep a reserve of its daily request quota. A sync that sees it
/// stops for the rest of its run instead of trying the next league.
const String providerQuotaErrorCode = 'football_data.provider_quota';

/// Where a provider says a match stands.
enum ProviderMatchStatus {
  /// Not kicked off yet.
  scheduled,

  /// In play, at a break, or in extra time / a shoot-out.
  live,

  /// Over; the final score is known.
  finished,

  /// Moved to a later, possibly unknown, date.
  postponed,

  /// Called off or abandoned; no result will come.
  cancelled,

  /// A state the adapter does not recognise; never acted upon.
  unknown,
}

/// One match as an external football-data provider describes it, reduced to
/// what the automatic sync needs. Ids are the provider's own, as strings.
final class ProviderMatch {
  /// Creates the match.
  const ProviderMatch({
    required this.externalId,
    required this.leagueExternalId,
    required this.homeTeamExternalId,
    required this.awayTeamExternalId,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.kickoffAt,
    required this.status,
    this.homeGoals,
    this.awayGoals,
    this.currentHomeGoals,
    this.currentAwayGoals,
    this.minute,
  });

  /// The provider's match id.
  final String externalId;

  /// The provider's competition id.
  final String leagueExternalId;

  /// The provider's home team id.
  final String homeTeamExternalId;

  /// The provider's away team id.
  final String awayTeamExternalId;

  /// The provider's home team name (for logs only; teams resolve by id).
  final String homeTeamName;

  /// The provider's away team name (for logs only).
  final String awayTeamName;

  /// Kickoff, UTC.
  final DateTime kickoffAt;

  /// Where the match stands.
  final ProviderMatchStatus status;

  /// Final home goals once [status] is finished: after extra time when it was
  /// played, never including a penalty shoot-out.
  final int? homeGoals;

  /// Final away goals, same rule as [homeGoals].
  final int? awayGoals;

  /// The running home score while [status] is live (for display only;
  /// never recorded). May lag the real game on a delayed feed.
  final int? currentHomeGoals;

  /// The running away score while [status] is live (display only).
  final int? currentAwayGoals;

  /// The match minute while live, when the provider reports one.
  final int? minute;

  /// Whether a final scoreline can be recorded from this match.
  bool get hasFinalScore =>
      status == ProviderMatchStatus.finished &&
      homeGoals != null &&
      awayGoals != null;
}

/// Read port over an external football-data provider.
abstract interface class FootballDataProvider {
  /// The matches of [leagueExternalId] on the Riyadh calendar day
  /// [riyadhDay] (only its year, month and day are read).
  ///
  /// Returns an error with code [providerQuotaErrorCode] when the adapter is
  /// holding back the rest of its daily quota.
  Future<Result<List<ProviderMatch>>> matchesOn({
    required String leagueExternalId,
    required DateTime riyadhDay,
  });
}
